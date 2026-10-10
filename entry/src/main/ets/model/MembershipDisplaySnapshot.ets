/** 仅用于冷启动展示，绝不能作为会员权限或购买凭据。 */
export class MembershipDisplaySnapshot {
  productId: string = '';
  expiresAt: number = 0;
  autoRenew: boolean = false;
  verifiedAt: number = 0;

  static valid(value: MembershipDisplaySnapshot | null, now: number): boolean {
    if (!value || (value.productId !== 'iconMonth' && value.productId !== 'iconYear' && value.productId !== 'lastVip')) {
      return false;
    }
    return typeof value.autoRenew === 'boolean' && typeof value.verifiedAt === 'number' &&
      Number.isFinite(value.verifiedAt) && value.verifiedAt > 0 && now >= value.verifiedAt &&
      now - value.verifiedAt < 24 * 60 * 60 * 1000 && typeof value.expiresAt === 'number' &&
      Number.isFinite(value.expiresAt) &&
      (value.productId === 'lastVip' ? value.expiresAt === 0 : value.expiresAt > now);
  }
}
