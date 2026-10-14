import { common } from '@kit.AbilityKit';

/** 合同办理期间的免费发行服务：不引用 IAP、不查订单、不重置用户设置。 */
@ObservedV2
export class MembershipService {
  private static readonly shared: MembershipService = new MembershipService();

  static get instance(): MembershipService { return MembershipService.shared; }

  @Trace busy: boolean = false;
  @Trace message: Resource = $r('app.string.features_free_access');

  async hasCurrentEntitlement(): Promise<boolean> { return true; }

  foreground(_context: common.UIAbilityContext): void {}

  background(): void {}

  async load(_context: common.UIAbilityContext, _restore: boolean = false): Promise<void> {}

  async refresh(_context: common.UIAbilityContext, _force: boolean = false,
    _recoverUnfinished: boolean = false): Promise<void> {}
}
