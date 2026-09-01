export class RuleSourceLoginRouteParams {
  sourceUrl: string = '';
  displayName: string = '';
  loginUrl: string = '';
  isMainAccount: boolean = false;

  static of(sourceUrl: string, displayName: string, loginUrl: string): RuleSourceLoginRouteParams {
    const params = new RuleSourceLoginRouteParams();
    params.sourceUrl = sourceUrl.trim();
    params.displayName = displayName.trim();
    params.loginUrl = loginUrl.trim();
    return params;
  }

  static forMainAccount(sourceUrl: string, displayName: string,
    loginUrl: string): RuleSourceLoginRouteParams {
    const params = RuleSourceLoginRouteParams.of(sourceUrl, displayName, loginUrl);
    params.isMainAccount = true;
    return params;
  }

  isValid(): boolean {
    return this.sourceUrl.length > 0 && this.displayName.length > 0 &&
      this.loginUrl.toLowerCase().startsWith('https://');
  }
}
