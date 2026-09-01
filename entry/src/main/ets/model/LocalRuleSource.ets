import { BookSource } from './BookSource';

export class LocalRuleSourceType {
  static readonly TEXT: number = 0;
  static readonly AUDIO: number = 1;
  static readonly COMIC: number = 2;
  static readonly WEB_FILE: number = 3;
}

export class LocalRuleSourceStatus {
  static readonly UNCHECKED: number = 0;
  static readonly READY: number = 1;
  static readonly FAILED: number = 2;
  static readonly UNSUPPORTED: number = 3;
}

/** 本地规则源会话。未登录时 token 可为空，用于保留稳定设备标识；凭据不写回书源 JSON。 */
export class LocalRuleSourceSession {
  sourceUrl: string = '';
  token: string = '';
  deviceId: string = '';
  accountLabel: string = '';
  updatedAt: number = 0;

  static of(sourceUrl: string, token: string, deviceId: string,
    accountLabel: string = ''): LocalRuleSourceSession {
    const session = new LocalRuleSourceSession();
    session.sourceUrl = sourceUrl;
    session.token = token;
    session.deviceId = deviceId;
    session.accountLabel = accountLabel;
    return session;
  }
}

/** 本地规则源按站点隔离的 Cookie 快照，存放于加密规则源数据库。 */
export class LocalRuleSourceCookie {
  sourceUrl: string = '';
  origin: string = '';
  cookieHeader: string = '';
  updatedAt: number = 0;

  static of(sourceUrl: string, origin: string, cookieHeader: string): LocalRuleSourceCookie {
    const cookie = new LocalRuleSourceCookie();
    cookie.sourceUrl = sourceUrl;
    cookie.origin = origin;
    cookie.cookieHeader = cookieHeader;
    return cookie;
  }
}

export class LocalRuleSearchRule {
  bookList: string = '';
  name: string = '';
  author: string = '';
  coverUrl: string = '';
  bookUrl: string = '';
  intro: string = '';
  kind: string = '';
  status: string = '';
  lastChapter: string = '';
  wordCount: string = '';
  updateTime: string = '';
}

export class LocalRuleBookInfoRule {
  init: string = '';
  name: string = '';
  author: string = '';
  coverUrl: string = '';
  intro: string = '';
  kind: string = '';
  status: string = '';
  lastChapter: string = '';
  wordCount: string = '';
  updateTime: string = '';
  tocUrl: string = '';
}

export class LocalRuleTocRule {
  chapterList: string = '';
  chapterName: string = '';
  chapterUrl: string = '';
  nextTocUrl: string = '';
  isVip: string = '';
  isPay: string = '';
  isVolume: string = '';
  updateTime: string = '';
  duration: string = '';
}

export class LocalRuleContentRule {
  content: string = '';
  title: string = '';
  audioUrl: string = '';
  nextContentUrl: string = '';
  replaceRegex: string = '';
  sourceRegex: string = '';
}

@ObservedV2
export class LocalRuleSource implements BookSource {
  bookSourceUrl: string = '';
  bookSourceName: string = '';
  bookSourceType: number = LocalRuleSourceType.TEXT;
  bookSourceGroup: string = '';
  bookSourceComment: string = '';
  @Trace enabled: boolean = true;
  enabledExplore: boolean = false;
  enabledCookieJar: boolean = true;
  searchUrl: string = '';
  exploreUrl: string = '';
  header: string = '';
  loginUrl: string = '';
  loginUi: string = '';
  loginCheckJs: string = '';
  jsLib: string = '';
  variable: string = '';
  respondTime: number = 18000;
  concurrentRate: string = '';
  lastUpdateTime: number = 0;
  rawSourceJson: string = '';
  @Trace validationStatus: number = LocalRuleSourceStatus.UNCHECKED;
  @Trace validationMessage: string = '';
  ruleSearch: LocalRuleSearchRule = new LocalRuleSearchRule();
  ruleBookInfo: LocalRuleBookInfoRule = new LocalRuleBookInfoRule();
  ruleToc: LocalRuleTocRule = new LocalRuleTocRule();
  ruleContent: LocalRuleContentRule = new LocalRuleContentRule();

  static descriptor(sourceUrl: string, sourceName: string): LocalRuleSource {
    const source = new LocalRuleSource();
    source.bookSourceUrl = sourceUrl;
    source.bookSourceName = sourceName;
    return source;
  }

  isAudio(): boolean {
    return this.bookSourceType === LocalRuleSourceType.AUDIO;
  }

  isText(): boolean {
    return this.bookSourceType === LocalRuleSourceType.TEXT ||
      this.bookSourceType === LocalRuleSourceType.WEB_FILE;
  }

  isSearchEnabled(): boolean {
    return this.enabled && this.canExecute();
  }

  canExecute(): boolean {
    return this.validationStatus !== LocalRuleSourceStatus.UNSUPPORTED;
  }
}

export class LocalRuleSourceImportReport {
  sources: LocalRuleSource[] = [];
  rejectedCount: number = 0;
  unsupportedCount: number = 0;
  message: string = '';
}

export class LocalRuleSourceHealth {
  sourceUrl: string = '';
  status: number = LocalRuleSourceStatus.UNCHECKED;
  message: string = '';
  responseTimeMs: number = 0;
  checkedAt: number = 0;
}

export class LocalRuleField {
  name: string = '';
  rule: string = '';
  resolveUrl: boolean = false;

  static of(name: string, rule: string, resolveUrl: boolean = false): LocalRuleField {
    const field = new LocalRuleField();
    field.name = name;
    field.rule = rule;
    field.resolveUrl = resolveUrl;
    return field;
  }
}

export class LocalRuleRecord {
  values: Record<string, string> = {};

  get(name: string): string {
    return this.values[name] ?? '';
  }
}
