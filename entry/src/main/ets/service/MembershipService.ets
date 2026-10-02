import lazy { iap } from '@kit.IAPKit';
import { common } from '@kit.AbilityKit';
import { BusinessError } from '@kit.BasicServicesKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { MembershipState } from '../model/MembershipState';
import { PlatformCompat } from '../utils/PlatformCompat';
import { AppIconService } from './AppIconService';
import { SubscriptionOrder, SubscriptionPayload, SubscriptionPolicy, SubscriptionStatus } from './membership/SubscriptionData';
import { SubscriptionVerifier } from './membership/SubscriptionVerifier';

export class MembershipPlan {
  id: string;
  price: string;
  groupId: string;
  constructor(product: iap.Product) {
    this.id = product.id;
    this.price = product.localPrice || product.price;
    this.groupId = product.subscriptionInfo?.groupId || '';
  }
}

class MembershipTimeout extends Error implements BusinessError {
  code: number = -2;
  constructor() { super('IAP request timed out'); }
}

/** 无自有服务器：每次查询都向华为获取凭据，在本机验签，不持久化 VIP 布尔值。 */
@ObservedV2
export class MembershipService {
  private static singleton: MembershipService | null = null;
  static get instance(): MembershipService {
    if (!MembershipService.singleton) MembershipService.singleton = new MembershipService();
    return MembershipService.singleton;
  }
  @Trace plans: MembershipPlan[] = [];
  @Trace busy: boolean = false;
  @Trace message: Resource = $r('app.string.membership_checking');
  @Trace productsMessage: Resource = $r('app.string.membership_products_loading');
  @Trace confirmationPending: boolean = false;
  private refreshTask: Promise<void> | null = null;
  private queryAt: number = 0;
  private refreshedAt: number = 0;
  private expiryTimer: number = -1;
  private allowSandbox: boolean = false;
  private sandboxChecked: boolean = false;
  private inForeground: boolean = true;

  get supported(): boolean {
    return !PlatformCompat.wearable && canIUse('SystemCapability.Payment.IAP');
  }

  private bounded<T>(operation: Promise<T>, timeout: number = 20000): Promise<T> {
    return new Promise<T>((resolve, reject): void => {
      const timer = setTimeout((): void => { reject(new MembershipTimeout()); }, timeout);
      operation.then((result: T): void => { clearTimeout(timer); resolve(result); },
        (error: BusinessError): void => { clearTimeout(timer); reject(error); });
    });
  }

  /** 前台恢复时必须重新核对系统华为账号下的订阅，不使用 App 头像登录状态代替购买凭据。 */
  foreground(context: common.UIAbilityContext): void {
    this.inForeground = true;
    if (!this.supported || this.busy) return;
    this.sandboxChecked = false;
    MembershipState.current.clear();
    this.refresh(context, true).catch((): void => {});
  }

  async load(context: common.UIAbilityContext): Promise<void> {
    await this.refresh(context);
    if (!this.supported || this.busy) return;
    this.busy = true;
    try {
      await this.bounded(iap.queryEnvironmentStatus(context));
      const products = await this.bounded(iap.queryProducts(context, {
        productType: iap.ProductType.AUTORENEWABLE,
        productIds: [SubscriptionPolicy.month, SubscriptionPolicy.year]
      }));
      const plans: MembershipPlan[] = [];
      for (const product of products) {
        const info = product.subscriptionInfo;
        if (!SubscriptionPolicy.knownProduct(product.id) || product.type !== iap.ProductType.AUTORENEWABLE ||
          (product.status !== undefined && product.status !== iap.ProductStatus.VALID) ||
          !info || !info.groupId || !product.price) continue;
        // 套餐文案与华为实际计费周期一致；不把周商品当作月商品销售。
        const expected = product.id === SubscriptionPolicy.month ? iap.PeriodUnit.MONTH : iap.PeriodUnit.YEAR;
        if ((info.periodUnit !== expected || info.periodCount !== 1) &&
          !(this.allowSandbox && info.periodUnit === iap.PeriodUnit.MINUTE)) continue;
        plans.push(new MembershipPlan(product));
      }
      if (plans.length === 2 && plans[0].groupId !== plans[1].groupId) {
        throw new Error('Subscription products must share one group');
      }
      this.plans = plans.sort((a: MembershipPlan, b: MembershipPlan): number => a.id.localeCompare(b.id));
      this.productsMessage = plans.length > 0 ? $r('app.string.membership_price_hint') : $r('app.string.membership_products_unavailable');
    } catch (error) {
      this.plans = [];
      this.productsMessage = this.errorMessage(error);
    } finally {
      this.busy = false;
    }
  }

  async refresh(context: common.UIAbilityContext, force: boolean = false): Promise<void> {
    if (!this.supported) {
      this.message = $r('app.string.membership_unsupported');
      return;
    }
    if (this.refreshTask) return this.refreshTask;
    if (this.busy) return;
    if (!force && this.refreshedAt > 0 && Date.now() - this.refreshedAt < 5000) return;
    this.busy = true;
    this.message = $r('app.string.membership_checking');
    this.refreshTask = this.refreshInner(context).catch((error: BusinessError): void => {
      // 未能查询不等于已过期：禁止新的付费图标切换，但不擅自重置桌面上现有图标。
      MembershipState.current.clear();
      this.refreshedAt = 0;
      if (this.expiryTimer !== -1) clearTimeout(this.expiryTimer);
      this.expiryTimer = -1;
      this.message = this.errorMessage(error);
    }).finally((): void => {
      this.busy = false;
      this.refreshTask = null;
    });
    return this.refreshTask;
  }

  private async checkSandbox(context: common.UIAbilityContext): Promise<void> {
    if (this.sandboxChecked) return;
    this.allowSandbox = false;
    if (context.applicationInfo.debug) {
      try { this.allowSandbox = await this.bounded(iap.isSandboxActivated(context)); } catch (_error) { /* 生产凭据仍可验签。 */ }
    }
    this.sandboxChecked = true;
  }

  private async query(context: common.UIAbilityContext, type: iap.PurchaseQueryType): Promise<SubscriptionPayload[]> {
    let token = '';
    const seen = new Set<string>();
    const payloads: SubscriptionPayload[] = [];
    for (let page = 0; page < 20; page++) {
      const delay = Math.max(0, this.queryAt + 5100 - Date.now());
      if (delay > 0) await new Promise<void>((resolve): void => { setTimeout(resolve, delay); });
      this.queryAt = Date.now();
      const result = await this.bounded(iap.queryPurchases(context, {
        productType: iap.ProductType.AUTORENEWABLE, queryType: type, continuationToken: token || undefined
      }));
      if (result.purchaseDataList.length + payloads.length > 200) throw new Error('Too many subscription records');
      for (const data of result.purchaseDataList) {
        payloads.push(await SubscriptionVerifier.verify(context, data));
      }
      token = result.continuationToken || '';
      if (!token) return payloads;
      if (seen.has(token)) throw new Error('Repeated subscription continuation token');
      seen.add(token);
    }
    throw new Error('Subscription pagination limit');
  }

  private async refreshInner(context: common.UIAbilityContext): Promise<void> {
    await this.checkSandbox(context);
    const payloads = await this.query(context, iap.PurchaseQueryType.CURRENT_ENTITLEMENT);
    let latest: SubscriptionStatus | undefined = undefined;
    const orders: SubscriptionOrder[] = [];
    const now = Date.now();
    for (const payload of payloads) {
      const status = SubscriptionPolicy.validate(payload, this.allowSandbox, now);
      if (status && SubscriptionPolicy.active(status, now)) {
        if (!latest || status.expiresTime > latest.expiresTime) latest = status;
        if (status.lastPurchaseOrder) orders.push(status.lastPurchaseOrder);
      }
    }
    // 先原子替换权益，再确认发货；重复查询只是覆盖到期时间，不累计增加月份。
    const state = MembershipState.current;
    state.clear();
    if (latest && latest.lastPurchaseOrder) {
      state.productId = latest.lastPurchaseOrder.productId;
      state.expiresAt = latest.expiresTime;
      state.autoRenew = latest.renewalInfo?.autoRenewStatusCode === '1';
      state.verifiedAt = now;
    }
    this.refreshedAt = now;
    this.message = state.active ? $r('app.string.membership_active') : $r('app.string.membership_inactive');
    this.scheduleRefresh(context);
    if (!state.active) await this.resetIcon();
    this.confirmationPending = false;
    const finished = new Set<string>();
    for (const order of orders) await this.finish(context, order, finished);
    // 补发货不覆盖 CURRENT_ENTITLEMENT 的最新状态，防止历史凭据恢复已撤销的权益。
    try {
      const unfinished = await this.query(context, iap.PurchaseQueryType.UNFINISHED);
      for (const payload of unfinished) {
        const status = SubscriptionPolicy.validate(payload, this.allowSandbox, Date.now());
        if (!state.active || !status || !SubscriptionPolicy.active(status, Date.now()) || !status.lastPurchaseOrder) continue;
        const order = status.lastPurchaseOrder;
        const belongsToCurrent = orders.some((current: SubscriptionOrder): boolean => current.purchaseToken === order.purchaseToken);
        if (belongsToCurrent) await this.finish(context, order, finished);
      }
    } catch (_error) {
      this.confirmationPending = true;
    }
  }

  private async finish(context: common.UIAbilityContext, order: SubscriptionOrder, finished: Set<string>): Promise<void> {
    if (order.finishStatus === '1' || finished.has(order.purchaseOrderId)) return;
    try {
      await this.bounded(iap.finishPurchase(context, {
        productType: iap.ProductType.AUTORENEWABLE,
        purchaseOrderId: order.purchaseOrderId, purchaseToken: order.purchaseToken
      }));
      finished.add(order.purchaseOrderId);
    } catch (error) {
      const failure: BusinessError = error;
      if (failure.code !== iap.IAPErrorCode.PURCHASE_FINISHED) this.confirmationPending = true;
    }
  }

  async purchase(context: common.UIAbilityContext, id: string): Promise<void> {
    if (this.busy || !this.supported || !this.plans.some((plan: MembershipPlan): boolean => plan.id === id)) return;
    // 已有会员在华为订阅管理中切换，避免重复订阅。
    await this.refresh(context, true);
    if (MembershipState.current.active) { await this.manage(context); return; }
    if (Date.now() - this.refreshedAt > 30000 || this.refreshedAt === 0) return;
    this.busy = true;
    let reconcile = false;
    try {
      const result = await this.bounded(iap.createPurchase(context,
        { productType: iap.ProductType.AUTORENEWABLE, productId: id }), 180000);
      const payload = await SubscriptionVerifier.verify(context, result.purchaseData);
      SubscriptionPolicy.validate(payload, this.allowSandbox, Date.now());
      reconcile = true;
    } catch (error) {
      const failure: BusinessError = error;
      this.message = this.errorMessage(failure);
      reconcile = failure.code !== iap.IAPErrorCode.USER_CANCELED;
    } finally {
      this.busy = false;
    }
    if (reconcile) await this.refresh(context, true);
  }

  async manage(context: common.UIAbilityContext): Promise<boolean> {
    if (this.busy || !this.supported) return false;
    this.busy = true;
    try {
      await this.bounded(iap.showManagedSubscriptions(context, { windowScreenMode: iap.WindowScreenMode.FULLSCREEN }));
    } catch (error) {
      this.message = this.errorMessage(error);
      return false;
    } finally {
      this.busy = false;
    }
    await this.refresh(context, true);
    return true;
  }

  background(): void {
    this.inForeground = false;
    if (this.expiryTimer !== -1) clearTimeout(this.expiryTimer);
    this.expiryTimer = -1;
  }

  private scheduleRefresh(context: common.UIAbilityContext): void {
    if (this.expiryTimer !== -1) clearTimeout(this.expiryTimer);
    this.expiryTimer = -1;
    const state = MembershipState.current;
    if (!state.active || !this.inForeground) return;
    this.expiryTimer = setTimeout((): void => {
      this.expiryTimer = -1;
      if (Date.now() >= state.expiresAt) {
        state.clear();
        this.resetIcon();
      }
      this.refresh(context, true);
    }, Math.max(1000, Math.min(240000, state.expiresAt - Date.now())));
  }

  private async resetIcon(): Promise<void> {
    if (!AppIconService.instance.supported) return;
    try { await AppIconService.instance.select(''); } catch (_error) { /* 下次前台刷新重试系统图标。 */ }
  }

  private errorMessage(error: BusinessError): Resource {
    hilog.warn(0x0000, 'MembershipService', 'IAP operation failed, code=%{public}d', error.code ?? -1);
    switch (error.code) {
      case -2: return $r('app.string.membership_timeout');
      case 1001860000: return $r('app.string.membership_cancelled');
      case 1001860050: return $r('app.string.membership_login_required');
      case 1001860003: return $r('app.string.membership_products_unavailable');
      case 1001860002: return $r('app.string.membership_not_authorized');
      case 1001860004: return $r('app.string.membership_retry_later');
      case 1001860005: return $r('app.string.membership_network_error');
      case 1001860007:
      case 1001860054:
      case 801: return $r('app.string.membership_unsupported');
      default: return $r('app.string.membership_verification_failed');
    }
  }
}
