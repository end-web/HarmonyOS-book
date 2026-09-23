/** 将规则返回的简介转换为展示文本；不改动规则中间结果或正文 HTML。 */
export class LocalRuleMetadataText {
  static intro(value: string): string {
    let text = value;
    // 兼容网页实体及二次转义的标签，轮数有界。
    for (let pass = 0; pass < 3; pass++) {
      const decoded = LocalRuleMetadataText.decodeEntities(text);
      if (decoded === text) break;
      text = decoded;
    }
    text = text.replace(/<!--[\s\S]*?-->/g, '')
      .replace(/<(script|style|noscript)\b[^>]*>[\s\S]*?<\/\1\s*>/gi, '')
      .replace(/<\/?(?:br|hr)\b[^>]*>/gi, '\n')
      .replace(/<\/?(?:p|div|section|article|li|ul|ol|h[1-6]|tr)\b[^>]*>/gi, '\n')
      .replace(/<\/?[a-z][^>]*>/gi, '')
      .replace(/\r\n?/g, '\n')
      .replace(/[\t \u00a0\u2002\u2003]+/g, ' ')
      .replace(/ *\n */g, '\n')
      .replace(/\n{3,}/g, '\n\n')
      .trim();
    const compact = text.replace(/\s+/g, '');
    const placeholders: string[] = ['=.=','==', '暂无', '暂无简介', '暂无介绍', '无'];
    return placeholders.includes(compact) ? '' : text;
  }

  private static decodeEntities(value: string): string {
    return value.replace(/&(?:#(?:x[0-9a-f]+|[0-9]+)|[a-z][a-z0-9]+);/gi,
      (entity: string): string => {
        const name = entity.substring(1, entity.length - 1).toLowerCase();
        if (name.startsWith('#')) {
          const hexadecimal = name.startsWith('#x');
          const code = Number.parseInt(name.substring(hexadecimal ? 2 : 1), hexadecimal ? 16 : 10);
          if (!Number.isFinite(code) || code <= 0 || code > 0x10FFFF ||
            (code >= 0xD800 && code <= 0xDFFF)) return '\uFFFD';
          return String.fromCodePoint(code);
        }
        switch (name) {
          case 'amp': return '&';
          case 'lt': return '<';
          case 'gt': return '>';
          case 'quot': return '"';
          case 'apos': return "'";
          case 'nbsp': case 'ensp': case 'emsp': case 'thinsp': return ' ';
          case 'ldquo': return '“';
          case 'rdquo': return '”';
          case 'lsquo': return '‘';
          case 'rsquo': return '’';
          case 'hellip': return '…';
          case 'mdash': return '—';
          case 'ndash': return '–';
          case 'middot': return '·';
          case 'copy': return '©';
          case 'reg': return '®';
          default: return entity;
        }
      });
  }
}
