/** 仅用于开发者自己的调试包；改为 true 后重新构建 debug 包。正式包始终禁用。 */
export class DeveloperMembership {
  static readonly ENABLED: boolean = false;

  static allowed(debug: boolean): boolean {
    return debug && DeveloperMembership.ENABLED;
  }
}
