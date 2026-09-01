export class RuleSourceChildKind {
  static readonly TEXT: number = 0;
  static readonly AUDIO: number = 1;
}

export class RuleSourceChildStatus {
  static readonly KNOWN: number = 0;
  static readonly ACTIVE: number = 1;
  static readonly DISABLED: number = 2;
}

/** 聚合源内部的只读子源能力，不保存 Cookie、token 或远程脚本。 */
export class RuleSourceChild {
  id: string = '';
  parentSourceUrl: string = '';
  name: string = '';
  kind: number = RuleSourceChildKind.TEXT;
  status: number = RuleSourceChildStatus.KNOWN;
  resultCount: number = 0;
  responseTimeMs: number = 0;
  requiresLogin: boolean = false;
  loginUrl: string = '';

  static of(parentSourceUrl: string, name: string, kind: number,
    requiresLogin: boolean = false, loginUrl: string = ''): RuleSourceChild {
    const child = new RuleSourceChild();
    child.parentSourceUrl = parentSourceUrl;
    child.name = name;
    child.kind = kind;
    child.id = `${parentSourceUrl}:${kind}:${name}`;
    child.requiresLogin = requiresLogin;
    child.loginUrl = loginUrl;
    return child;
  }

  isAudio(): boolean {
    return this.kind === RuleSourceChildKind.AUDIO;
  }

  canOpenLogin(): boolean {
    return this.requiresLogin && this.loginUrl.startsWith('https://');
  }
}

export class RuleSourceChildLoadResult {
  items: RuleSourceChild[] = [];
  networkUpdated: boolean = false;
  errorMessage: string = '';
}
