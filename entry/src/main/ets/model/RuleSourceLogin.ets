import { url } from '@kit.ArkTS';

export class RuleSourceLoginRouteParams {
  sourceUrl: string = '';
  displayName: string = '';
  loginUrl: string = '';
  isMainAccount: boolean = false;
  requestId: string = '';
  initialHtml: string = '';

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
    if (this.sourceUrl.length === 0 || this.displayName.length === 0) return false;
    try {
      const parsed = new url.URL(this.loginUrl);
      return parsed.protocol === 'https:' && parsed.hostname.length > 0 && !parsed.username && !parsed.password;
    } catch (_error) { return false; }
  }

  documentUrl(): string {
    try {
      const parsed = new url.URL(this.loginUrl);
      parsed.hash = '';
      return parsed.toString();
    } catch (_error) { return ''; }
  }
}
