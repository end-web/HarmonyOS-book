import lazy { PreferenceService } from './PreferenceService';
import lazy { AutoBackupService } from './AutoBackupService';
import { DeveloperMembership } from './membership/DeveloperMembership';
import lazy { iap } from '@kit.IAPKit';
import { common } from '@kit.AbilityKit';
import { BusinessError } from '@kit.BasicServicesKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { MembershipState } from '../model/MembershipState';
import { PlatformCompat } from '../utils/PlatformCompat';
import { AppIconService } from './AppIconService';
import { SubscriptionOrder, SubscriptionPayload, SubscriptionPolicy, SubscriptionStatus } from './membership/SubscriptionData';
import { SubscriptionVerifier } from './membership/SubscriptionVerifier';
import { LifetimeOrder, LifetimePolicy } from './membership/LifetimeData';

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
  private abilityContext: common.UIAbilityContext | null = null;

  /** 共用已验签权益；到期、换号或核验失败时不放行新的会员操作。 */
  async hasCurrentEntitlement(): Promise<boolean> {
    if (MembershipState.current.developerAccess) return true;
    const context = this.abilityContext;
    if (!context || !this.supported) return false;
    await this.refresh(context);
    return MembershipState.current.hasAccess;
  }

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
    this.abilityContext = context;
    MembershipState.current.developerAccess = DeveloperMembership.allowed(context.applicationInfo.debug);
    this.inForeground = true;
    if (this.busy) return;
    this.sandboxChecked = false;
    MembershipState.current.clear();
    MembershipState.current.confirmedInactive = false;
    this.refresh(context, true).catch((): void => {});
  }

  async load(context: common.UIAbilityContext): Promise<void> {
    await this.refresh(context);
    if (!this.supported || this.busy) return;
    this.busy = true;
    try {
      await this.bounded(iap.queryEnvironmentStatus(context));
      const plans: MembershipPlan[] = [];
      try {
        const products = await this.bounded(iap.queryProducts(context, {
          productType: iap.ProductType.AUTORENEWABLE,
          productIds: [SubscriptionPolicy.month, SubscriptionPolicy.year]
        }));
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
          plans.length = 0;
          throw new Error('Subscription products must share one group');
        }
      } catch (_error) { /* 月/年商品不可售时，继续查询独立的终身商品。 */ }
      // 两种商品类型分开查询，遵守同一 API 的调用间隔；终身商品不可售不影响月/年套餐。
      this.plans = plans;
      await new Promise<void>((resolve): void => { setTimeout(resolve, 5100); });
      try {
        const lifetimeProducts = await this.bounded(iap.queryProducts(context, {
          productType: iap.ProductType.NONCONSUMABLE, productIds: [LifetimePolicy.product]
        }));
        for (const product of lifetimeProducts) {
          if (product.id === LifetimePolicy.product && product.type === iap.ProductType.NONCONSUMABLE &&
            (product.status === undefined || product.status === iap.ProductStatus.VALID) &&
            (product.localPrice || product.price)) plans.push(new MembershipPlan(product));
        }
      } catch (_error) { /* 套餐卡保留“暂不可购买”，不伪造终身价格。 */ }
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
    this.abilityContext = context;
    MembershipState.current.developerAccess = DeveloperMembership.allowed(context.applicationInfo.debug);
    if (MembershipState.current.developerAccess) {
      MembershipState.current.confirmedInactive = false;
      this.message = $r('app.string.membership_developer_active');
      return;
    }
    if (!this.supported) {
      MembershipState.current.clear();
      MembershipState.current.confirmedInactive = true;
      await this.resetDefaults(context);
      this.message = $r('app.string.membership_unsupported');
      return;
    }
    if (this.refreshTask) return this.refreshTask;
    if (this.busy) return;
    if (!force && this.refreshedAt > 0 && Date.now() - this.refreshedAt < 5000) return;
    this.busy = true;
    this.message = $r('app.string.membership_checking');
    this.refreshTask = this.refreshInner(context).catch(async (error: BusinessError): Promise<void> => {
      // 无有效会员凭据时恢复受限设置；不改变真实购买记录。
      MembershipState.current.clear();
      MembershipState.current.confirmedInactive = true;
      await this.resetDefaults(context);
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
    const payloads: SubscriptionPayload[] = [];
    for (const data of await this.queryData(context, type, iap.ProductType.AUTORENEWABLE)) {
      payloads.push(await SubscriptionVerifier.verify(context, data));
    }
    return payloads;
  }

  private async queryLifetime(context: common.UIAbilityContext, type: iap.PurchaseQueryType): Promise<LifetimeOrder[]> {
    const orders: LifetimeOrder[] = [];
    for (const data of await this.queryData(context, type, iap.ProductType.NONCONSUMABLE)) {
      const order = LifetimePolicy.validate(await SubscriptionVerifier.verifyLifetime(context, data), this.allowSandbox, Date.now());
      if (order) orders.push(order);
    }
    return orders;
  }

  private async queryData(context: common.UIAbilityContext, type: iap.PurchaseQueryType,
    productType: iap.ProductType): Promise<string[]> {
    let token = '';
    const seen = new Set<string>();
    const payloads: string[] = [];
    for (let page = 0; page < 20; page++) {
      const delay = Math.max(0, this.queryAt + 5100 - Date.now());
      if (delay > 0) await new Promise<void>((resolve): void => { setTimeout(resolve, delay); });
      this.queryAt = Date.now();
      const result = await this.bounded(iap.queryPurchases(context, {
        productType: productType, queryType: type, continuationToken: token || undefined
      }));
      if (result.purchaseDataList.length + payloads.length > 200) throw new Error('Too many subscription records');
      for (const data of result.purchaseDataList) {
        payloads.push(data);
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
    const lifetimeOrders = await this.queryLifetime(context, iap.PurchaseQueryType.CURRENT_ENTITLEMENT);
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
    if (lifetimeOrders.length > 0) {
      state.productId = LifetimePolicy.product;
      state.verifiedAt = now;
      for (const order of lifetimeOrders) orders.push(order);
    } else if (latest && latest.lastPurchaseOrder) {
      state.productId = latest.lastPurchaseOrder.productId;
      state.expiresAt = latest.expiresTime;
      state.autoRenew = latest.renewalInfo?.autoRenewStatusCode === '1';
      state.verifiedAt = now;
    }
    state.confirmedInactive = !state.active;
    this.refreshedAt = now;
    this.message = state.active ? $r('app.string.membership_active') : $r('app.string.membership_inactive');
    this.scheduleRefresh(context);
    if (state.confirmedInactive) await this.resetDefaults(context);
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
      const lifetimeUnfinished = await this.queryLifetime(context, iap.PurchaseQueryType.UNFINISHED);
      for (const order of lifetimeUnfinished) {
        if (state.active && lifetimeOrders.some((current: LifetimeOrder): boolean =>
          current.purchaseToken === order.purchaseToken && current.purchaseOrderId === order.purchaseOrderId)) {
          await this.finish(context, order, finished);
        }
      }
    } catch (_error) {
      this.confirmationPending = true;
    }
  }

  private async finish(context: common.UIAbilityContext, order: SubscriptionOrder, finished: Set<string>): Promise<void> {
    if (order.finishStatus === '1' || finished.has(order.purchaseOrderId)) return;
    try {
      await this.bounded(iap.finishPurchase(context, {
        productType: order.productType === '1' ? iap.ProductType.NONCONSUMABLE : iap.ProductType.AUTORENEWABLE,
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
    // 已有月/年会员切换订阅交给华为管理；终身会员允许一次性升级，已拥有时不再购买。
    await this.refresh(context, true);
    if (MembershipState.current.active) {
      if (MembershipState.current.lifetime) return;
      if (id !== LifetimePolicy.product) { await this.manage(context); return; }
    }
    if (Date.now() - this.refreshedAt > 30000 || this.refreshedAt === 0) return;
    this.busy = true;
    let reconcile = false;
    try {
      const result = await this.bounded(iap.createPurchase(context,
        { productType: id === LifetimePolicy.product ? iap.ProductType.NONCONSUMABLE : iap.ProductType.AUTORENEWABLE,
          productId: id }), 180000);
      if (id === LifetimePolicy.product) {
        LifetimePolicy.validate(await SubscriptionVerifier.verifyLifetime(context, result.purchaseData), this.allowSandbox, Date.now());
      } else {
        SubscriptionPolicy.validate(await SubscriptionVerifier.verify(context, result.purchaseData), this.allowSandbox, Date.now());
      }
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
      if (!state.lifetime && Date.now() >= state.expiresAt) {
        state.clear();
        state.confirmedInactive = true;
        this.resetDefaults(context);
      }
      this.refresh(context, true);
    }, state.lifetime ? 240000 : Math.max(1000, Math.min(240000, state.expiresAt - Date.now())));
  }

  private async resetDefaults(context: common.UIAbilityContext): Promise<void> {
    if (MembershipState.current.hasAccess) return;
    // 不等待备份任务：该任务可能正在等待本次会员查询，避免互相等待。
    AutoBackupService.instance.resetMembershipDefaults(context).catch((): void => {});
    try { await PreferenceService.setSearchConcurrency(3); } catch (_error) { /* 后续读取仍按默认并发执行。 */ }
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
