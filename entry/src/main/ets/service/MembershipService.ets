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
import { MembershipDisplaySnapshot } from '../model/MembershipDisplaySnapshot';
import { MembershipDisplayStore } from './membership/MembershipDisplayStore';

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
  @Trace productsLoading: boolean = false;
  private productsTask: Promise<void> | null = null;
  private productsAt: number = 0;
  private productsQueryAt: number = 0;
  private queryAt: number = 0;
  private refreshedAt: number = 0;
  private expiryTimer: number = -1;
  private allowSandbox: boolean = false;
  private sandboxChecked: boolean = false;
  private sandboxTask: Promise<void> | null = null;
  private inForeground: boolean = true;
  private abilityContext: common.UIAbilityContext | null = null;
  private displayRestoreStarted: boolean = false;
  private displayRevision: number = 0;
  private displayWriteTask: Promise<void> = Promise.resolve();

  private async restoreDisplay(context: common.UIAbilityContext): Promise<void> {
    if (this.displayRestoreStarted) return;
    this.displayRestoreStarted = true;
    const revision = this.displayRevision;
    try {
      const snapshot = await MembershipDisplayStore.read(context);
      // 联网结果始终优先，迟到的磁盘读取不能恢复已撤销的展示。
      if (revision === this.displayRevision && !MembershipState.current.active &&
        !MembershipState.current.confirmedInactive) MembershipState.current.restoreDisplay(snapshot);
    } catch (_error) { /* 缓存损坏或读取失败不影响真实会员核验。 */ }
  }

  private persistDisplay(context: common.UIAbilityContext, snapshot: MembershipDisplaySnapshot | null): Promise<void> {
    this.displayRevision++;
    MembershipState.current.restoreDisplay(snapshot);
    this.displayWriteTask = this.displayWriteTask.then((): Promise<void> =>
      MembershipDisplayStore.write(context, snapshot)).catch((): void => {
      hilog.warn(0x0000, 'MembershipService', 'Membership display cache could not be saved');
    });
    return this.displayWriteTask;
  }

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
    this.productsAt = 0;
    const state = MembershipState.current;
    // 有效快照继续用于徽标和套餐展示；不清零再等待 IAP，避免前台恢复时闪烁。
    if (!state.active) state.clearEntitlement();
    state.confirmedInactive = false;
    state.revalidating = true;
    this.refresh(context, true).catch((): void => {});
  }

  async load(context: common.UIAbilityContext, restore: boolean = false): Promise<void> {
    // 价格不依赖权益查询；两个请求各自合并，慢价格不会锁住会员操作。
    await Promise.all([this.refresh(context, restore, restore), this.loadProducts(context, restore)]);
  }

  private async loadProducts(context: common.UIAbilityContext, force: boolean = false): Promise<void> {
    if (!this.supported) return;
    if (this.productsTask) return this.productsTask;
    const age = Date.now() - this.productsAt;
    if (!force && this.productsAt > 0 && age >= 0 && age < 5 * 60 * 1000) return;
    this.productsLoading = true;
    this.productsMessage = $r('app.string.membership_products_loading');
    this.productsTask = this.loadProductsInner(context).finally((): void => {
      this.productsLoading = false;
      this.productsTask = null;
    });
    return this.productsTask;
  }

  private async loadProductsInner(context: common.UIAbilityContext): Promise<void> {
    try {
      const delay = Math.max(0, this.productsQueryAt + 5100 - Date.now());
      if (delay > 0) await new Promise<void>((resolve): void => { setTimeout(resolve, delay); });
      this.productsQueryAt = Date.now();
      await this.bounded(iap.queryEnvironmentStatus(context));
      await this.checkSandbox(context);
      // API 20 起支持跨商品类型批量查询，最低支持版本已覆盖。
      const products = await this.bounded(iap.queryProducts(context,
        [SubscriptionPolicy.month, SubscriptionPolicy.year, LifetimePolicy.product]));
      const plans: MembershipPlan[] = [];
      for (const product of products) {
        if ((product.status !== undefined && product.status !== iap.ProductStatus.VALID) ||
          !(product.localPrice || product.price)) continue;
        if (product.id === LifetimePolicy.product && product.type === iap.ProductType.NONCONSUMABLE) {
          plans.push(new MembershipPlan(product));
          continue;
        }
        const info = product.subscriptionInfo;
        if (!SubscriptionPolicy.knownProduct(product.id) || product.type !== iap.ProductType.AUTORENEWABLE ||
          !info || !info.groupId) continue;
        const expected = product.id === SubscriptionPolicy.month ? iap.PeriodUnit.MONTH : iap.PeriodUnit.YEAR;
        if ((info.periodUnit !== expected || info.periodCount !== 1) &&
          !(this.allowSandbox && info.periodUnit === iap.PeriodUnit.MINUTE)) continue;
        plans.push(new MembershipPlan(product));
      }
      const subscriptions = plans.filter((plan: MembershipPlan): boolean => plan.id !== LifetimePolicy.product);
      this.plans = subscriptions.length === 2 && subscriptions[0].groupId !== subscriptions[1].groupId ?
        plans.filter((plan: MembershipPlan): boolean => plan.id === LifetimePolicy.product) : plans;
      this.productsAt = Date.now();
      this.productsMessage = this.plans.length > 0 ? $r('app.string.membership_price_hint') :
        $r('app.string.membership_products_unavailable');
    } catch (error) {
      this.plans = [];
      this.productsAt = 0;
      this.productsMessage = this.errorMessage(error);
    }
  }

  async refresh(context: common.UIAbilityContext, force: boolean = false, recoverUnfinished: boolean = false): Promise<void> {
    this.abilityContext = context;
    MembershipState.current.developerAccess = DeveloperMembership.allowed(context.applicationInfo.debug);
    if (MembershipState.current.developerAccess) {
      MembershipState.current.revalidating = false;
      MembershipState.current.confirmedInactive = false;
      this.message = $r('app.string.membership_developer_active');
      return;
    }
    if (!this.supported) {
      MembershipState.current.revalidating = false;
      MembershipState.current.clear();
      MembershipState.current.confirmedInactive = true;
      await this.persistDisplay(context, null);
      await this.resetDefaults(context);
      this.message = $r('app.string.membership_unsupported');
      return;
    }
    this.restoreDisplay(context);
    if (this.refreshTask) {
      await this.refreshTask;
      if (!recoverUnfinished) return;
    }
    if (this.busy) return;
    const age = Date.now() - this.refreshedAt;
    // 普通入口共用权益自身的有效窗口；过期、换号及强制核验不会命中。
    if (!force && (MembershipState.current.active ||
      (this.refreshedAt > 0 && age >= 0 && age < 60000 && MembershipState.current.confirmedInactive))) return;
    this.busy = true;
    this.message = $r('app.string.membership_checking');
    this.refreshTask = this.refreshInner(context, recoverUnfinished).catch(async (error: BusinessError): Promise<void> => {
      // 无有效会员凭据时恢复受限设置；不改变真实购买记录。
      MembershipState.current.clear();
      // 查询失败表示状态未知，不能据此引导用户重新开通。
      MembershipState.current.confirmedInactive = false;
      await this.persistDisplay(context, null);
      await this.resetDefaults(context);
      this.refreshedAt = 0;
      if (this.expiryTimer !== -1) clearTimeout(this.expiryTimer);
      this.expiryTimer = -1;
      this.message = this.errorMessage(error);
    }).finally((): void => {
      MembershipState.current.revalidating = false;
      this.busy = false;
      this.refreshTask = null;
    });
    return this.refreshTask;
  }

  private async checkSandbox(context: common.UIAbilityContext): Promise<void> {
    if (this.sandboxChecked) return;
    if (this.sandboxTask) return this.sandboxTask;
    this.sandboxTask = this.checkSandboxInner(context).finally((): void => { this.sandboxTask = null; });
    return this.sandboxTask;
  }

  private async checkSandboxInner(context: common.UIAbilityContext): Promise<void> {
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
      // 无购买记录时，实机 IAP 可能省略列表或返回 null；仅在查询成功后将空值视为空列表。
      const purchaseDataList: string[] = result.purchaseDataList ?? [];
      if (!Array.isArray(purchaseDataList)) throw new Error('Invalid purchase list');
      if (context.applicationInfo.debug) {
        hilog.info(0x0000, 'MembershipService',
          'IAP query succeeded, type=%{public}d, query=%{public}d, count=%{public}d, absent=%{public}s',
          productType, type, purchaseDataList.length, String(result.purchaseDataList === undefined || result.purchaseDataList === null));
      }
      if (purchaseDataList.length + payloads.length > 200) throw new Error('Too many subscription records');
      for (const data of purchaseDataList) {
        payloads.push(data);
      }
      token = result.continuationToken || '';
      if (!token) return payloads;
      if (seen.has(token)) throw new Error('Repeated subscription continuation token');
      seen.add(token);
    }
    throw new Error('Subscription pagination limit');
  }

  private async refreshInner(context: common.UIAbilityContext, recoverUnfinished: boolean): Promise<void> {
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
    await this.persistDisplay(context, state.createDisplaySnapshot());
    if (state.confirmedInactive) await this.resetDefaults(context);
    this.confirmationPending = false;
    const finished = new Set<string>();
    for (const order of orders) await this.finish(context, order, finished);
    // 日常核验只确认当前订单；手动恢复及支付结果不确定时再扫描历史未完成订单。
    if (!recoverUnfinished) return;
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
    if (reconcile) await this.refresh(context, true, true);
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
        this.persistDisplay(context, null);
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
