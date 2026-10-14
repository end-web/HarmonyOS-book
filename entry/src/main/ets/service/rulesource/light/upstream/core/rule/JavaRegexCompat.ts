/**
 * Translates the Java/Kotlin regex dialect used by Android Legado (book sources and
 * replacement/purification rules) into a JavaScript RegExp.
 *
 * Android Legado compiles every rule with java.util.regex.Pattern, so rule authors write
 * constructs JavaScript has no syntax for. Such rules throw "Invalid group" / "Nothing to
 * repeat" at RegExp construction time here, and because every call site wraps the compile in
 * try/catch the rule is skipped silently: text keeps its HTML or punctuation and the user only
 * sees a red "规则无效" in the rule list.
 *
 * Everything rewritten below is either impossible or awkward to express in JS:
 * - inline flag groups `(?i)`, `(?m)`, `(?s)`, `(?is)`, `(?mi)`, `(?-i)` — JS只能把标志传给
 *   构造函数，所以标志被提升为 RegExp flags（位置信息丢失，见各 note）。
 * - possessive quantifiers `a*+`, `a++`, `a?+`, `a{2,3}+` — JS 只有贪婪/惰性，降级为贪婪。
 * - atomic groups `(?>…)` — JS 无原子组，降级为普通分组。
 * - `\Q…\E` 字面量引用、`\h`/`\H`/`\v`/`\V`/`\R`、`\z`/`\Z`、`\p{…}`。
 * - `\w`/`\W`/`\b`/`\B`/`\d`/`\D` — Android（ICU）按 Unicode 判定单词字符和数字，JS 只认 ASCII，
 *   改用同一字符集。
 * - replacement 串里的 `$0`（Java 的整个匹配）与 `\` 转义。
 */

export interface JavaRegexConversion {
  source: string;
  flags: string;
  /** 近似转换的说明，供界面提示或日志使用。 */
  notes: string[];
}

interface EscapeToken {
  text: string;
  next: number;
}

interface GroupToken {
  text: string;
  next: number;
  flags: string;
  removedFlags: string;
  commentsMode: boolean;
  inlineFlags: boolean;
}

export class JavaRegexCompat {
  private static readonly HORIZONTAL_CONTENT = ' \\t\\u00A0\\u1680\\u2000-\\u200A\\u202F\\u205F\\u3000';
  private static readonly VERTICAL_CONTENT = '\\n\\x0B\\f\\r\\x85\\u2028\\u2029';
  private static readonly LINE_BREAK = '(?:\\r\\n|[\\n\\x0B\\f\\r\\x85\\u2028\\u2029])';
  private static readonly INPUT_END = '(?![\\s\\S])';
  private static readonly INPUT_END_OR_TERMINATOR =
    '(?=(?:\\r\\n|[\\n\\r\\x85\\u2028\\u2029])?(?![\\s\\S]))';
  // Android 的 \w、\d（ICU 语义）在基本多文种平面内的字符范围及各自的补集，都是“字符类内容”。
  // 代理项（BMP 之外的字符）按非单词字符处理。由 scripts/generate-java-regex-word-class.mjs 生成，请勿手改。
  // <generated:word-class>
  private static readonly WORD_CONTENT: string =
    '\\u0030-\\u0039\\u0041-\\u005A\\u005F\\u0061-\\u007A\\u00AA\\u00B5\\u00BA\\u00C0-\\u00D6\\u00D8-\\u00F6\\u00F8-' +
    '\\u02C1\\u02C6-\\u02D1\\u02E0-\\u02E4\\u02EC\\u02EE\\u0300-\\u0374\\u0376-\\u037D\\u037F\\u0386\\u0388-\\u03F5' +
    '\\u03F7-\\u0481\\u0483-\\u0559\\u0560-\\u0588\\u0591-\\u05BD\\u05BF\\u05C1\\u05C2\\u05C4\\u05C5\\u05C7-\\u05F2' +
    '\\u0610-\\u061A\\u0620-\\u0669\\u066E-\\u06D3\\u06D5-\\u06DC\\u06DF-\\u06E8\\u06EA-\\u06FC\\u06FF\\u0710-' +
    '\\u07F5\\u07FA-\\u07FD\\u0800-\\u082D\\u0840-\\u085B\\u0860-\\u0887\\u0889-\\u088F\\u0897-\\u08E1\\u08E3-' +
    '\\u0963\\u0966-\\u096F\\u0971-\\u09F1\\u09FC\\u09FE-\\u0A75\\u0A81-\\u0AEF\\u0AF9-\\u0B6F\\u0B71\\u0B82-\\u0BEF' +
    '\\u0C00-\\u0C6F\\u0C80-\\u0C83\\u0C85-\\u0D4E\\u0D54-\\u0D57\\u0D5F-\\u0D6F\\u0D7A-\\u0DF3\\u0E01-\\u0E3A' +
    '\\u0E40-\\u0E4E\\u0E50-\\u0E59\\u0E81-\\u0F00\\u0F18\\u0F19\\u0F20-\\u0F29\\u0F35\\u0F37\\u0F39\\u0F3E-\\u0F84' +
    '\\u0F86-\\u0FBC\\u0FC6\\u1000-\\u1049\\u1050-\\u109D\\u10A0-\\u10FA\\u10FC-\\u135F\\u1380-\\u138F\\u13A0-' +
    '\\u13FD\\u1401-\\u166C\\u166F-\\u167F\\u1681-\\u169A\\u16A0-\\u16EA\\u16EE-\\u1734\\u1740-\\u17D3\\u17D7' +
    '\\u17DC-\\u17E9\\u180B-\\u180D\\u180F-\\u193B\\u1946-\\u19D9\\u1A00-\\u1A1B\\u1A20-\\u1A99\\u1AA7\\u1AB0-' +
    '\\u1B4C\\u1B50-\\u1B59\\u1B6B-\\u1B73\\u1B80-\\u1BF3\\u1C00-\\u1C37\\u1C40-\\u1C7D\\u1C80-\\u1CBF\\u1CD0-' +
    '\\u1CD2\\u1CD4-\\u1FBC\\u1FBE\\u1FC2-\\u1FCC\\u1FD0-\\u1FDB\\u1FE0-\\u1FEC\\u1FF2-\\u1FFC\\u200C\\u200D\\u203F' +
    '\\u2040\\u2054\\u2071\\u207F\\u2090-\\u209C\\u20D0-\\u20F0\\u2102\\u2107\\u210A-\\u2113\\u2115\\u2119-\\u211D' +
    '\\u2124\\u2126\\u2128\\u212A-\\u212D\\u212F-\\u2139\\u213C-\\u213F\\u2145-\\u2149\\u214E\\u2160-\\u2188\\u24B6-' +
    '\\u24E9\\u2C00-\\u2CE4\\u2CEB-\\u2CF3\\u2D00-\\u2D6F\\u2D7F-\\u2DFF\\u2E2F\\u3005-\\u3007\\u3021-\\u302F' +
    '\\u3031-\\u3035\\u3038-\\u303C\\u3041-\\u309A\\u309D-\\u309F\\u30A1-\\u30FA\\u30FC-\\u318E\\u31A0-\\u31BF' +
    '\\u31F0-\\u31FF\\u3400-\\u4DBF\\u4E00-\\uA48C\\uA4D0-\\uA4FD\\uA500-\\uA60C\\uA610-\\uA672\\uA674-\\uA67D' +
    '\\uA67F-\\uA6F1\\uA717-\\uA71F\\uA722-\\uA788\\uA78B-\\uA827\\uA82C\\uA840-\\uA873\\uA880-\\uA8C5\\uA8D0-' +
    '\\uA8F7\\uA8FB\\uA8FD-\\uA92D\\uA930-\\uA953\\uA960-\\uA9C0\\uA9CF-\\uA9D9\\uA9E0-\\uAA59\\uAA60-\\uAA76' +
    '\\uAA7A-\\uAADD\\uAAE0-\\uAAEF\\uAAF2-\\uAB5A\\uAB5C-\\uAB69\\uAB70-\\uABEA\\uABEC-\\uD7FB\\uF900-\\uFB28' +
    '\\uFB2A-\\uFBB1\\uFBD3-\\uFD3D\\uFD50-\\uFD8F\\uFD92-\\uFDC7\\uFDF0-\\uFDFB\\uFE00-\\uFE0F\\uFE20-\\uFE2F' +
    '\\uFE33\\uFE34\\uFE4D-\\uFE4F\\uFE70-\\uFEFC\\uFF10-\\uFF19\\uFF21-\\uFF3A\\uFF3F\\uFF41-\\uFF5A\\uFF66-\\uFFDC';
  private static readonly NON_WORD_CONTENT: string =
    '\\u0000-\\u002F\\u003A-\\u0040\\u005B-\\u005E\\u0060\\u007B-\\u00A9\\u00AB-\\u00B4\\u00B6-\\u00B9\\u00BB-' +
    '\\u00BF\\u00D7\\u00F7\\u02C2-\\u02C5\\u02D2-\\u02DF\\u02E5-\\u02EB\\u02ED\\u02EF-\\u02FF\\u0375\\u037E\\u0380-' +
    '\\u0385\\u0387\\u03F6\\u0482\\u055A-\\u055F\\u0589-\\u0590\\u05BE\\u05C0\\u05C3\\u05C6\\u05F3-\\u060F\\u061B-' +
    '\\u061F\\u066A-\\u066D\\u06D4\\u06DD\\u06DE\\u06E9\\u06FD\\u06FE\\u0700-\\u070F\\u07F6-\\u07F9\\u07FE\\u07FF' +
    '\\u082E-\\u083F\\u085C-\\u085F\\u0888\\u0890-\\u0896\\u08E2\\u0964\\u0965\\u0970\\u09F2-\\u09FB\\u09FD\\u0A76-' +
    '\\u0A80\\u0AF0-\\u0AF8\\u0B70\\u0B72-\\u0B81\\u0BF0-\\u0BFF\\u0C70-\\u0C7F\\u0C84\\u0D4F-\\u0D53\\u0D58-\\u0D5E' +
    '\\u0D70-\\u0D79\\u0DF4-\\u0E00\\u0E3B-\\u0E3F\\u0E4F\\u0E5A-\\u0E80\\u0F01-\\u0F17\\u0F1A-\\u0F1F\\u0F2A-' +
    '\\u0F34\\u0F36\\u0F38\\u0F3A-\\u0F3D\\u0F85\\u0FBD-\\u0FC5\\u0FC7-\\u0FFF\\u104A-\\u104F\\u109E\\u109F\\u10FB' +
    '\\u1360-\\u137F\\u1390-\\u139F\\u13FE-\\u1400\\u166D\\u166E\\u1680\\u169B-\\u169F\\u16EB-\\u16ED\\u1735-\\u173F' +
    '\\u17D4-\\u17D6\\u17D8-\\u17DB\\u17EA-\\u180A\\u180E\\u193C-\\u1945\\u19DA-\\u19FF\\u1A1C-\\u1A1F\\u1A9A-' +
    '\\u1AA6\\u1AA8-\\u1AAF\\u1B4D-\\u1B4F\\u1B5A-\\u1B6A\\u1B74-\\u1B7F\\u1BF4-\\u1BFF\\u1C38-\\u1C3F\\u1C7E\\u1C7F' +
    '\\u1CC0-\\u1CCF\\u1CD3\\u1FBD\\u1FBF-\\u1FC1\\u1FCD-\\u1FCF\\u1FDC-\\u1FDF\\u1FED-\\u1FF1\\u1FFD-\\u200B' +
    '\\u200E-\\u203E\\u2041-\\u2053\\u2055-\\u2070\\u2072-\\u207E\\u2080-\\u208F\\u209D-\\u20CF\\u20F1-\\u2101' +
    '\\u2103-\\u2106\\u2108\\u2109\\u2114\\u2116-\\u2118\\u211E-\\u2123\\u2125\\u2127\\u2129\\u212E\\u213A\\u213B' +
    '\\u2140-\\u2144\\u214A-\\u214D\\u214F-\\u215F\\u2189-\\u24B5\\u24EA-\\u2BFF\\u2CE5-\\u2CEA\\u2CF4-\\u2CFF' +
    '\\u2D70-\\u2D7E\\u2E00-\\u2E2E\\u2E30-\\u3004\\u3008-\\u3020\\u3030\\u3036\\u3037\\u303D-\\u3040\\u309B\\u309C' +
    '\\u30A0\\u30FB\\u318F-\\u319F\\u31C0-\\u31EF\\u3200-\\u33FF\\u4DC0-\\u4DFF\\uA48D-\\uA4CF\\uA4FE\\uA4FF\\uA60D-' +
    '\\uA60F\\uA673\\uA67E\\uA6F2-\\uA716\\uA720\\uA721\\uA789\\uA78A\\uA828-\\uA82B\\uA82D-\\uA83F\\uA874-\\uA87F' +
    '\\uA8C6-\\uA8CF\\uA8F8-\\uA8FA\\uA8FC\\uA92E\\uA92F\\uA954-\\uA95F\\uA9C1-\\uA9CE\\uA9DA-\\uA9DF\\uAA5A-\\uAA5F' +
    '\\uAA77-\\uAA79\\uAADE\\uAADF\\uAAF0\\uAAF1\\uAB5B\\uAB6A-\\uAB6F\\uABEB\\uD7FC-\\uF8FF\\uFB29\\uFBB2-\\uFBD2' +
    '\\uFD3E-\\uFD4F\\uFD90\\uFD91\\uFDC8-\\uFDEF\\uFDFC-\\uFDFF\\uFE10-\\uFE1F\\uFE30-\\uFE32\\uFE35-\\uFE4C' +
    '\\uFE50-\\uFE6F\\uFEFD-\\uFF0F\\uFF1A-\\uFF20\\uFF3B-\\uFF3E\\uFF40\\uFF5B-\\uFF65\\uFFDD-\\uFFFF';
  private static readonly DIGIT_CONTENT: string =
    '\\u0030-\\u0039\\u0660-\\u0669\\u06F0-\\u06F9\\u07C0-\\u07C9\\u0966-\\u096F\\u09E6-\\u09EF\\u0A66-\\u0A6F' +
    '\\u0AE6-\\u0AEF\\u0B66-\\u0B6F\\u0BE6-\\u0BEF\\u0C66-\\u0C6F\\u0CE6-\\u0CEF\\u0D66-\\u0D6F\\u0DE6-\\u0DEF' +
    '\\u0E50-\\u0E59\\u0ED0-\\u0ED9\\u0F20-\\u0F29\\u1040-\\u1049\\u1090-\\u1099\\u17E0-\\u17E9\\u1810-\\u1819' +
    '\\u1946-\\u194F\\u19D0-\\u19D9\\u1A80-\\u1A99\\u1B50-\\u1B59\\u1BB0-\\u1BB9\\u1C40-\\u1C49\\u1C50-\\u1C59' +
    '\\uA620-\\uA629\\uA8D0-\\uA8D9\\uA900-\\uA909\\uA9D0-\\uA9D9\\uA9F0-\\uA9F9\\uAA50-\\uAA59\\uABF0-\\uABF9' +
    '\\uFF10-\\uFF19';
  private static readonly NON_DIGIT_CONTENT: string =
    '\\u0000-\\u002F\\u003A-\\u065F\\u066A-\\u06EF\\u06FA-\\u07BF\\u07CA-\\u0965\\u0970-\\u09E5\\u09F0-\\u0A65' +
    '\\u0A70-\\u0AE5\\u0AF0-\\u0B65\\u0B70-\\u0BE5\\u0BF0-\\u0C65\\u0C70-\\u0CE5\\u0CF0-\\u0D65\\u0D70-\\u0DE5' +
    '\\u0DF0-\\u0E4F\\u0E5A-\\u0ECF\\u0EDA-\\u0F1F\\u0F2A-\\u103F\\u104A-\\u108F\\u109A-\\u17DF\\u17EA-\\u180F' +
    '\\u181A-\\u1945\\u1950-\\u19CF\\u19DA-\\u1A7F\\u1A9A-\\u1B4F\\u1B5A-\\u1BAF\\u1BBA-\\u1C3F\\u1C4A-\\u1C4F' +
    '\\u1C5A-\\uA61F\\uA62A-\\uA8CF\\uA8DA-\\uA8FF\\uA90A-\\uA9CF\\uA9DA-\\uA9EF\\uA9FA-\\uAA4F\\uAA5A-\\uABEF' +
    '\\uABFA-\\uFF0F\\uFF1A-\\uFFFF';
  // </generated:word-class>
  private static readonly INLINE_FLAG_LETTERS = 'imsuxdU';
  private static readonly CONVERTIBLE_FLAGS = 'ims';
  private static readonly LITERAL_METACHARACTERS = '\\^$.*+?()[]{}|';
  private static readonly BRACE_QUANTIFIER = /^\{\d+(?:,\d*)?\}|^\{,\d+\}/;
  private static readonly CACHE_LIMIT = 512;
  private static cache: Map<string, JavaRegexConversion> = new Map<string, JavaRegexConversion>();

  /**
   * Compiles a Legado regex into a fresh RegExp. A fresh object is returned on purpose: global
   * regexes carry lastIndex state, so sharing one instance between test() and replace() calls
   * would skip matches.
   */
  static compile(pattern: string, flags: string = ''): RegExp {
    const conversion = JavaRegexCompat.convert(pattern, flags);
    return new RegExp(conversion.source, conversion.flags);
  }

  /** 转换结果按 pattern+flags 缓存，因为界面会按帧对每条规则重复校验。 */
  static convert(pattern: string, flags: string = ''): JavaRegexConversion {
    const source = pattern || '';
    const key = `${flags}\u0001${source}`;
    const cached = JavaRegexCompat.cache.get(key);
    if (cached) {
      return cached;
    }
    const conversion = JavaRegexCompat.translate(source, flags);
    if (JavaRegexCompat.cache.size >= JavaRegexCompat.CACHE_LIMIT) {
      JavaRegexCompat.cache.clear();
    }
    JavaRegexCompat.cache.set(key, conversion);
    return conversion;
  }

  /** 转换说明，未做任何改写时返回空数组。 */
  static notes(pattern: string, flags: string = ''): string[] {
    return JavaRegexCompat.convert(pattern, flags).notes.slice();
  }

  static isSupported(pattern: string, flags: string = ''): boolean {
    try {
      JavaRegexCompat.compile(pattern, flags);
      return true;
    } catch (_) {
      return false;
    }
  }

  /**
   * 编译失败后的可读原因。引擎的原生报错只有一句 "Syntax error."，而这几类 Java 专有写法是
   * 转换层无法等价的，单独指出来才能让用户知道该改规则而不是怀疑应用。
   */
  static unsupportedHint(pattern: string): string {
    const source = pattern || '';
    const known: string[] = [];
    if (/\\[pP]\{(?:Is|In|java|com)/.test(source)) {
      known.push('Java 专有 Unicode 属性名');
    }
    if (/\(\?P[<=]/.test(source)) {
      known.push('Python 风格命名分组');
    }
    if (/\[[^\]]*&&/.test(source)) {
      known.push('字符类交集');
    }
    return known.length > 0 ? `含 JavaScript 无法等价的写法：${known.join('、')}` : '';
  }

  /**
   * Java 的替换串语义：`$0` 是整个匹配，`\` 是转义符（因此 `\d` 是字面量 d）。
   * JavaScript 用 `$&` 表示整个匹配，且反斜杠是普通字符，需要在此对齐。
   */
  static convertReplacement(replacement: string): string {
    const text = replacement || '';
    let result = '';
    for (let index = 0; index < text.length; index++) {
      const ch = text.charAt(index);
      if (ch === '\\') {
        const escaped = index + 1 < text.length ? text.charAt(index + 1) : '';
        if (escaped) {
          result += escaped === '$' ? '$$' : escaped;
          index++;
        }
        continue;
      }
      const after = text.charAt(index + 1);
      if (ch === '$' && after === '0' && !JavaRegexCompat.isDigit(text.charAt(index + 2))) {
        result += '$&';
        index++;
        continue;
      }
      result += ch;
    }
    return result;
  }

  private static isDigit(value: string): boolean {
    return value.length === 1 && value >= '0' && value <= '9';
  }

  private static translate(pattern: string, extraFlags: string): JavaRegexConversion {
    const notes: string[] = [];
    let flags = extraFlags || '';
    // `\p{…}` 在 JavaScript 里必须配合 u 标志，否则会被当成字面量 p{…}。
    const needsUnicode = /\\[pP]\{/.test(pattern);
    if (needsUnicode && !flags.includes('u')) {
      flags += 'u';
    }
    let result = '';
    let index = 0;
    let inClass = false;
    let commentsMode = false;

    while (index < pattern.length) {
      const ch = pattern.charAt(index);

      if (ch === '\\') {
        const token = JavaRegexCompat.translateEscape(pattern, index, inClass, notes, flags.includes('u'));
        result += token.text;
        index = token.next;
        continue;
      }

      if (inClass) {
        if (ch === ']') {
          inClass = false;
        } else if (ch === '&' && pattern.charAt(index + 1) === '&') {
          notes.push('字符类交集（&&）在 JavaScript 中按字面量处理，结果与 Android 不同');
        }
        result += ch;
        index++;
        continue;
      }

      if (commentsMode) {
        if (JavaRegexCompat.isPatternWhitespace(ch)) {
          index++;
          continue;
        }
        if (ch === '#') {
          while (index < pattern.length && pattern.charAt(index) !== '\n') {
            index++;
          }
          continue;
        }
      }

      if (ch === '[') {
        result += '[';
        index++;
        if (pattern.charAt(index) === '^') {
          result += '^';
          index++;
        }
        if (pattern.charAt(index) === ']') {
          // `[]a]` 里首个 `]` 是字面量，Java 与 JS 规则一致，这里显式转义避免歧义。
          result += '\\]';
          index++;
        }
        inClass = true;
        continue;
      }

      if (ch === '(' && pattern.charAt(index + 1) === '?') {
        const group = JavaRegexCompat.translateGroup(pattern, index, notes);
        if (group) {
          const previousFlags = flags;
          commentsMode = commentsMode || group.commentsMode;
          for (let i = 0; i < group.flags.length; i++) {
            const flag = group.flags.charAt(i);
            if (!flags.includes(flag)) {
              flags += flag;
            }
          }
          for (let i = 0; i < group.removedFlags.length; i++) {
            flags = flags.replace(group.removedFlags.charAt(i), '');
          }
          if (group.inlineFlags) {
            if (result.length > 0 && group.flags) {
              notes.push('内联标志不在规则开头，已提升为整条规则的标志');
            }
            for (let i = 0; i < group.removedFlags.length; i++) {
              const flag = group.removedFlags.charAt(i);
              if (previousFlags.includes(flag)) {
                notes.push(`内联关闭标志 (?-${flag}) 无法只作用于局部，已关闭整条规则的该标志`);
              }
            }
          }
          result += group.text;
          index = group.next;
          continue;
        }
      }

      if (ch === '{') {
        const quantifier = JavaRegexCompat.BRACE_QUANTIFIER.exec(pattern.substring(index));
        if (quantifier) {
          result += quantifier[0];
          index += quantifier[0].length;
          if (pattern.charAt(index) === '+') {
            notes.push('占有量词（+）已降级为贪婪量词');
            index++;
          }
          continue;
        }
        result += needsUnicode ? '\\{' : '{';
        index++;
        continue;
      }

      if (ch === '*' || ch === '+' || ch === '?') {
        result += ch;
        index++;
        if (pattern.charAt(index) === '+') {
          notes.push('占有量词（+）已降级为贪婪量词');
          index++;
        }
        continue;
      }

      if (ch === '}' && needsUnicode) {
        result += '\\}';
        index++;
        continue;
      }

      result += ch;
      index++;
    }

    return { source: result, flags: flags, notes: JavaRegexCompat.unique(notes) };
  }

  private static isPatternWhitespace(ch: string): boolean {
    return ch === ' ' || ch === '\t' || ch === '\n' || ch === '\r' || ch === '\f' || ch === '\u000B';
  }

  private static unique(values: string[]): string[] {
    const result: string[] = [];
    for (let i = 0; i < values.length; i++) {
      if (result.indexOf(values[i]) < 0) {
        result.push(values[i]);
      }
    }
    return result;
  }

  private static translateEscape(pattern: string, index: number, inClass: boolean,
    notes: string[], unicode: boolean): EscapeToken {
    const next = pattern.charAt(index + 1);
    if (!next) {
      return { text: '\\', next: index + 1 };
    }
    if (next === 'Q') {
      const end = pattern.indexOf('\\E', index + 2);
      const literal = end < 0 ? pattern.substring(index + 2) : pattern.substring(index + 2, end);
      if (end < 0) {
        notes.push('\\Q 缺少配对的 \\E，已按字面量处理到规则结尾');
      }
      return { text: JavaRegexCompat.escapeLiteral(literal), next: end < 0 ? pattern.length : end + 2 };
    }
    if (next === 'E') {
      notes.push('孤立的 \\E 已忽略');
      return { text: '', next: index + 2 };
    }
    // Android 的正则基于 ICU，`\w` 恒为 Unicode 语义（汉字是单词字符）；JavaScript 的 `\w` 只认
    // ASCII，`\W*` 因此会吞掉整段中文正文，`\b` 也落在错误的位置。这里统一换成 Android 的字符集。
    if (next === 'w') {
      return { text: inClass ? JavaRegexCompat.WORD_CONTENT : `[${JavaRegexCompat.WORD_CONTENT}]`, next: index + 2 };
    }
    if (next === 'W') {
      // 字符类内部无法取反，改用预先算好的补集；带 u 标志时补上 BMP 之外的码位。
      const astral = unicode ? '\\u{10000}-\\u{10FFFF}' : '';
      return {
        text: inClass ? JavaRegexCompat.NON_WORD_CONTENT + astral : `[^${JavaRegexCompat.WORD_CONTENT}]`,
        next: index + 2
      };
    }
    // `\d` 同理：Android 上匹配所有十进制数字（含全角 ０-９），JavaScript 只认 ASCII 的 0-9。
    if (next === 'd') {
      return { text: inClass ? JavaRegexCompat.DIGIT_CONTENT : `[${JavaRegexCompat.DIGIT_CONTENT}]`, next: index + 2 };
    }
    if (next === 'D') {
      const astral = unicode ? '\\u{10000}-\\u{10FFFF}' : '';
      return {
        text: inClass ? JavaRegexCompat.NON_DIGIT_CONTENT + astral : `[^${JavaRegexCompat.DIGIT_CONTENT}]`,
        next: index + 2
      };
    }
    if ((next === 'b' || next === 'B') && !inClass) {
      // 字符类内的 `\b` 是退格符，保持原样。
      const word = `[${JavaRegexCompat.WORD_CONTENT}]`;
      return {
        text: next === 'b' ? `(?:(?<=${word})(?!${word})|(?<!${word})(?=${word}))` :
          `(?:(?<=${word})(?=${word})|(?<!${word})(?!${word}))`,
        next: index + 2
      };
    }
    if (next === 'h') {
      return {
        text: inClass ? JavaRegexCompat.HORIZONTAL_CONTENT : `[${JavaRegexCompat.HORIZONTAL_CONTENT}]`,
        next: index + 2
      };
    }
    if (next === 'H') {
      if (inClass) {
        notes.push('字符类内的 \\H 无法取反，已按水平空白字符处理');
        return { text: JavaRegexCompat.HORIZONTAL_CONTENT, next: index + 2 };
      }
      return { text: `[^${JavaRegexCompat.HORIZONTAL_CONTENT}]`, next: index + 2 };
    }
    if (next === 'v') {
      return {
        text: inClass ? JavaRegexCompat.VERTICAL_CONTENT : `[${JavaRegexCompat.VERTICAL_CONTENT}]`,
        next: index + 2
      };
    }
    if (next === 'V') {
      if (inClass) {
        notes.push('字符类内的 \\V 无法取反，已按垂直空白字符处理');
        return { text: JavaRegexCompat.VERTICAL_CONTENT, next: index + 2 };
      }
      return { text: `[^${JavaRegexCompat.VERTICAL_CONTENT}]`, next: index + 2 };
    }
    if (next === 'R') {
      return {
        text: inClass ? JavaRegexCompat.VERTICAL_CONTENT : JavaRegexCompat.LINE_BREAK,
        next: index + 2
      };
    }
    if (next === 'z') {
      return { text: inClass ? '$' : JavaRegexCompat.INPUT_END, next: index + 2 };
    }
    if (next === 'Z') {
      return { text: inClass ? '$' : JavaRegexCompat.INPUT_END_OR_TERMINATOR, next: index + 2 };
    }
    if ((next === 'p' || next === 'P') && pattern.charAt(index + 2) === '{') {
      const close = pattern.indexOf('}', index + 3);
      if (close > 0) {
        const body = pattern.substring(index + 3, close);
        if (!JavaRegexCompat.isJavaScriptPropertyName(body)) {
          notes.push(`\\p{${body}} 的属性名 JavaScript 不支持，规则可能仍无法编译`);
        }
        return { text: pattern.substring(index, close + 1), next: close + 1 };
      }
    }
    if (next === 'u' && pattern.charAt(index + 2) === '{') {
      // JS 的 `\u{1F600}` 形式：整体复制，避免后续把 `{` 当成量词或字面量花括号处理。
      const close = pattern.indexOf('}', index + 3);
      if (close > 0) {
        return { text: pattern.substring(index, close + 1), next: close + 1 };
      }
    }
    if (next === 'G' || next === 'X' || next === 'A') {
      // Java 的 `\G`（上次匹配结尾）、`\X`（字形簇）、`\A`（输入开头）在 JavaScript 中
      // 没有对应语义，会被当成字面量字符，必须提示而不是静默给出错误结果。
      notes.push(`\\${next} 在 JavaScript 中没有对应语义，将按字面量字符处理`);
    }
    return { text: `\\${next}`, next: index + 2 };
  }

  private static isJavaScriptPropertyName(body: string): boolean {
    // JS 只认通用类别名（L、Lu、Letter、Nd…）和 `Script=…`/`sc=…` 形式，Java 的
    // `IsGreek`、`InCJKUnifiedIdeographs`、`javaLowerCase` 一类名字会被 u 模式拒绝。
    return /^[A-Za-z]+(?:=[A-Za-z_]+)?$/.test(body) && !/^(?:Is|In|java)/.test(body);
  }

  private static translateGroup(pattern: string, index: number, notes: string[]): GroupToken | null {
    let cursor = index + 2;
    let enabled = '';
    while (cursor < pattern.length &&
      JavaRegexCompat.INLINE_FLAG_LETTERS.indexOf(pattern.charAt(cursor)) >= 0) {
      enabled += pattern.charAt(cursor);
      cursor++;
    }
    let disabled = '';
    if (pattern.charAt(cursor) === '-') {
      let probe = cursor + 1;
      let letters = '';
      while (probe < pattern.length &&
        JavaRegexCompat.INLINE_FLAG_LETTERS.indexOf(pattern.charAt(probe)) >= 0) {
        letters += pattern.charAt(probe);
        probe++;
      }
      if (letters) {
        disabled = letters;
        cursor = probe;
      }
    }

    if (pattern.charAt(cursor) === ')' && (enabled || disabled)) {
      return JavaRegexCompat.translateInlineFlags(enabled, disabled, cursor + 1, notes);
    }

    const marker = pattern.charAt(index + 2);
    if (marker === '>') {
      notes.push('原子组 (?>…) 在 JavaScript 中没有对应实现，已按普通分组处理');
      return JavaRegexCompat.passThrough('(?:', index + 3);
    }
    if (marker === ':' || marker === '=' || marker === '!') {
      return JavaRegexCompat.passThrough(`(?${marker}`, index + 3);
    }
    if (marker === '<') {
      const after = pattern.charAt(index + 3);
      if (after === '=' || after === '!') {
        return JavaRegexCompat.passThrough(`(?<${after}`, index + 4);
      }
      return JavaRegexCompat.passThrough('(?<', index + 3);
    }
    // 未知构造（例如 Java 不支持的 Python 式分组）：保留原文，让引擎给出真实报错。
    return JavaRegexCompat.passThrough('(?', index + 2);
  }

  private static translateInlineFlags(enabled: string, disabled: string, next: number,
    notes: string[]): GroupToken {
    let flags = '';
    let removedFlags = '';
    let commentsMode = false;
    for (let i = 0; i < enabled.length; i++) {
      const letter = enabled.charAt(i);
      if (JavaRegexCompat.CONVERTIBLE_FLAGS.includes(letter)) {
        if (!flags.includes(letter)) {
          flags += letter;
        }
      } else if (letter === 'x') {
        commentsMode = true;
        notes.push('(?x) 自由空白模式已按 Java 语义忽略空白与 # 注释');
      } else {
        notes.push(`内联标志 (?${letter}) 在 JavaScript 中没有对应项，已忽略`);
      }
    }
    for (let i = 0; i < disabled.length; i++) {
      const letter = disabled.charAt(i);
      if (JavaRegexCompat.CONVERTIBLE_FLAGS.includes(letter)) {
        removedFlags += letter;
      }
    }
    return {
      text: '', next: next, flags: flags, removedFlags: removedFlags,
      commentsMode: commentsMode, inlineFlags: true
    };
  }

  private static passThrough(text: string, next: number): GroupToken {
    return {
      text: text, next: next, flags: '', removedFlags: '',
      commentsMode: false, inlineFlags: false
    };
  }

  private static escapeLiteral(text: string): string {
    let result = '';
    for (let index = 0; index < text.length; index++) {
      const ch = text.charAt(index);
      if (ch === '\n') {
        result += '\\n';
      } else if (ch === '\r') {
        result += '\\r';
      } else if (ch === '\t') {
        result += '\\t';
      } else if (ch === '\f') {
        result += '\\f';
      } else if (ch === '\u000B') {
        result += '\\x0B';
      } else if (JavaRegexCompat.LITERAL_METACHARACTERS.includes(ch)) {
        result += `\\${ch}`;
      } else {
        result += ch;
      }
    }
    return result;
  }
}
