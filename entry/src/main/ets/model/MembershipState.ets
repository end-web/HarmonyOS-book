/** 仅保存本次进程中已验签的权益；不从偏好设置恢复 VIP 开关。 */
@ObservedV2
export class MembershipState {
  private static singleton: MembershipState | null = null;
  static get current(): MembershipState {
    if (!MembershipState.singleton) MembershipState.singleton = new MembershipState();
    return MembershipState.singleton;
  }
  @Trace expiresAt: number = 0;
  @Trace productId: string = '';
  @Trace autoRenew: boolean = false;
  @Trace verifiedAt: number = 0;

  get active(): boolean {
    const now = Date.now();
    return this.productId.length > 0 && now >= this.verifiedAt && now < this.expiresAt &&
      now - this.verifiedAt < 5 * 60 * 1000;
  }

  clear(): void {
    this.expiresAt = 0;
    this.productId = '';
    this.autoRenew = false;
    this.verifiedAt = 0;
  }
}
