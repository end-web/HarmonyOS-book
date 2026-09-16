import { LocalRuleSource } from '../../../model/LocalRuleSource';

/** 协议标记只存在于用户添加的定义中，不注册任何内置 NAS。 */
export class TalebookSourceIdentity {
  static isSourceUrl(value: string | undefined): boolean {
    return value !== undefined && new RegExp('^https?://[^/?#]+/#talebook-(audio|text)$').test(value);
  }

  static origin(value: string): string {
    const clean = value.trim().replace(new RegExp('/#talebook-(audio|text)$'), '').replace(new RegExp('/+$'), '');
    if (!new RegExp('^https?://(?:\\[[0-9a-fA-F:]+\\]|[a-zA-Z0-9.-]+)(?::[0-9]{1,5})?$').test(clean)) {
      throw new Error('请输入完整的 NAS 地址，例如 http://nas.example.com:58080，不要附带路径或账号');
    }
    return clean.toLowerCase();
  }

  static isAudio(value: string): boolean {
    return value.endsWith('/#talebook-audio');
  }

  static create(origin: string, name: string, audio: boolean): LocalRuleSource {
    const source = new LocalRuleSource();
    source.bookSourceUrl = `${TalebookSourceIdentity.origin(origin)}/#talebook-${audio ? 'audio' : 'text'}`;
    source.bookSourceName = `${name || 'Talebook'} · ${audio ? '听书' : '阅读'}`;
    source.bookSourceType = audio ? 1 : 0;
    source.bookSourceGroup = 'Talebook';
    source.enabledExplore = true;
    source.enabledCookieJar = true;
    source.searchUrl = `${origin}/api/${audio ? 'audios' : 'search?name={{key}}'}`;
    source.exploreUrl = `${audio ? '有声书' : '电子书'}::${origin}/api/${audio ? 'audios' : 'recent'}`;
    source.ruleSearch.bookList = '$.books';
    source.ruleSearch.name = '$.title';
    source.ruleSearch.bookUrl = '$.id';
    source.bookSourceComment = 'Talebook 原生适配：在书源登录入口更新访问码；会话不包含在导出定义中。';
    return source;
  }
}
