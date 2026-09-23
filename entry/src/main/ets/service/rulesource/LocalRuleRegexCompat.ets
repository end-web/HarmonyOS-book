class LocalRuleRegexTranslation {
  pattern: string = '';
  flags: string = '';
  relaxedBacktracking: boolean = false;
}

/** 阅读/轻页常用 Java 正则方言；只转换语法，不执行书源脚本。 */
export class LocalRuleRegexCompat {
  private static readonly HORIZONTAL: string = ' \\t\\u00a0\\u1680\\u2000-\\u200a\\u202f\\u205f\\u3000';
  private static readonly VERTICAL: string = '\\n\\x0b\\f\\r\\x85\\u2028\\u2029';
  private static readonly END: string = '(?![\\s\\S])';

  static compile(pattern: string, flags: string = ''): RegExp {
    if (pattern.length > 32768) throw new Error('正则表达式超过 32 KiB');
    const translated = LocalRuleRegexCompat.translate(pattern, flags);
    // 占有量词/原子组降级会重新开放回溯，不接受会因此产生嵌套重复的表达式。
    if (translated.relaxedBacktracking &&
      new RegExp('\\([^)]*(?:[+*]|\\{\\d|\\|)[^)]*\\)[+*{]').test(translated.pattern)) {
      throw new Error('占有量词或原子组不能安全转换为嵌套重复正则');
    }
    return new RegExp(translated.pattern, translated.flags);
  }

  static replacement(value: string): string {
    let output = '';
    for (let index = 0; index < value.length; index++) {
      const character = value.charAt(index);
      if (character === '\\' && index + 1 < value.length) {
        const escaped = value.charAt(++index);
        output += escaped === '$' ? '$$' : escaped;
      } else if (character === '$' && value.charAt(index + 1) === '0' &&
        !new RegExp('[0-9]').test(value.charAt(index + 2))) {
        output += '$&';
        index++;
      } else output += character;
    }
    return output;
  }

  private static translate(pattern: string, flags: string): LocalRuleRegexTranslation {
    const result = new LocalRuleRegexTranslation();
    result.flags = flags;
    let inClass = false;
    let comments = false;
    let index = 0;
    while (index < pattern.length) {
      const character = pattern.charAt(index);
      if (character === '\\') {
        const escaped = pattern.charAt(index + 1);
        if (escaped === 'Q') {
          const end = pattern.indexOf('\\E', index + 2);
          result.pattern += LocalRuleRegexCompat.escapeLiteral(
            pattern.substring(index + 2, end < 0 ? pattern.length : end));
          index = end < 0 ? pattern.length : end + 2;
          continue;
        }
        if ((escaped === 'p' || escaped === 'P') && pattern.charAt(index + 2) === '{') {
          const end = pattern.indexOf('}', index + 3);
          if (end >= 0) {
            result.pattern += pattern.substring(index, end + 1);
            if (!result.flags.includes('u')) result.flags += 'u';
            index = end + 1;
            continue;
          }
        }
        if (escaped === 'h' || escaped === 'H' || escaped === 'v' || escaped === 'V' || escaped === 'R') {
          const horizontal = escaped.toLowerCase() === 'h';
          const content = horizontal ? LocalRuleRegexCompat.HORIZONTAL : LocalRuleRegexCompat.VERTICAL;
          if (inClass) {
            if (escaped === 'H' || escaped === 'V') throw new Error('字符类中的反向空白类暂不支持');
            result.pattern += content;
          } else if (escaped === 'R') result.pattern += `(?:\\r\\n|[${content}])`;
          else result.pattern += `[${escaped === 'H' || escaped === 'V' ? '^' : ''}${content}]`;
        } else if (!inClass && escaped === 'z') result.pattern += LocalRuleRegexCompat.END;
        else if (!inClass && escaped === 'Z') {
          result.pattern += `(?=(?:\\r\\n|[${LocalRuleRegexCompat.VERTICAL}])?${LocalRuleRegexCompat.END})`;
        } else if (!inClass && escaped === 'A') result.pattern += '(?<![\\s\\S])';
        else if (escaped === 'E') { /* 兼容孤立的 Java 引用结束标记。 */ }
        else result.pattern += `\\${escaped}`;
        index += escaped ? 2 : 1;
        continue;
      }
      if (inClass) {
        if (character === ']') inClass = false;
        result.pattern += character;
        index++;
        continue;
      }
      if (comments && new RegExp('\\s').test(character)) {
        index++;
        continue;
      }
      if (comments && character === '#') {
        const end = pattern.indexOf('\n', index);
        index = end < 0 ? pattern.length : end + 1;
        continue;
      }
      if (character === '[') {
        inClass = true;
        result.pattern += character;
        index++;
        continue;
      }
      if (character === '(' && pattern.charAt(index + 1) === '?') {
        const inline = new RegExp('^\\(\\?([imsxudU]*)(?:-([imsxudU]+))?\\)').exec(pattern.substring(index));
        if (inline !== null && ((inline[1] ?? '').length > 0 || (inline[2] ?? '').length > 0)) {
          for (const flag of inline[1] ?? '') {
            if ('ims'.includes(flag) && !result.flags.includes(flag)) result.flags += flag;
            if (flag === 'x') comments = true;
          }
          for (const flag of inline[2] ?? '') {
            if ('ims'.includes(flag)) result.flags = result.flags.replace(flag, '');
            if (flag === 'x') comments = false;
          }
          index += inline[0].length;
          continue;
        }
        if (pattern.charAt(index + 2) === '>') {
          result.pattern += '(?:';
          result.relaxedBacktracking = true;
          index += 3;
          continue;
        }
      }
      if (character === '{') {
        const quantifier = new RegExp('^\\{\\d+(?:,\\d*)?\\}').exec(pattern.substring(index));
        if (quantifier !== null) {
          result.pattern += quantifier[0];
          index += quantifier[0].length;
          if (pattern.charAt(index) === '+') {
            result.relaxedBacktracking = true;
            index++;
          }
          continue;
        }
      }
      result.pattern += character;
      index++;
      if ((character === '*' || character === '+' || character === '?') && pattern.charAt(index) === '+') {
        result.relaxedBacktracking = true;
        index++;
      }
    }
    return result;
  }

  private static escapeLiteral(value: string): string {
    let output = '';
    for (const character of value) {
      if (character === '-') output += '\\x2d';
      else if ('\\^$.*+?()[]{}|'.includes(character)) output += `\\${character}`;
      else output += character;
    }
    return output;
  }
}
