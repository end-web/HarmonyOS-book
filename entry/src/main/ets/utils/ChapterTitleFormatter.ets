/**
 * 章节标题展示层清洗
 *
 * 书源经常把书名拼到章节标题里，例如：
 *   "遮天 第001章 素问"        → "第001章 素问"
 *   "遮天-0002_素问-"           → "0002_素问-"
 *   "斗罗大陆：第1集 唐三"      → "第1集 唐三"
 *   "<<苗疆蛊事>> 第一集 序章"  → "第一集 序章"
 *   "《苗疆蛊事》001"            → "001"
 *   "【苗疆蛊事】序章"           → "序章"
 *
 * 策略：以"可选括号 + 书名 + 可选括号 + 分隔符"开头时剥掉，否则原样。
 * - 不依赖"第"等中文关键字（很多章节没有：素问 / 今昔 / 荒古铜刻）
 * - 在 BookSourceService.getBookToc 取目录时统一清洗一次，
 *   详情页/播放页/迷你播放器/媒体卡片/桌面卡片都自动拿干净标题。
 */
export class ChapterTitleFormatter {
  /** 标题里书名两侧可能出现的括号/引号开符号（中英 + 全/半角） */
  private static readonly WRAP_OPEN = '\\s<«《【「『\\[\\("\'（';
  /** 标题里书名两侧可能出现的括号/引号闭符号（中英 + 全/半角） */
  private static readonly WRAP_CLOSE = '\\s>»》】」』\\]\\)"\'）';
  /** 书名剥掉后紧跟的分隔符：空格、连字符、下划线、冒号、点等 */
  private static readonly LEADING_SEP = /^[\s\-_·•:：、，,\.。\|\\/]+/;

  /**
   * 章节标题去书名前缀。
   * @param rawTitle 章节原始标题
   * @param bookName 书名（用于精确剥除）
   * @returns 清洗后的标题；书名为空 / 不以书名开头 / 剥光后会变空 时原样返回
   */
  static stripBookPrefix(rawTitle: string | undefined | null, bookName: string | undefined | null): string {
    if (!rawTitle) return '';
    const title = rawTitle.trim();
    if (!title) return '';
    if (!bookName) return title;
    const book = bookName.trim();
    if (!book) return title;

    // 标题恰好就是书名（书源把书名当成章节）→ 原样返回，避免清洗成空串
    if (title === book) return title;

    // 转义书名里的正则元字符（《》[]() 等不需转，但用户书名可能含 . * + 等）
    const escaped = book.replace(/[.*+?^${}()|[\]\\]/g, '\\$&');

    // 匹配："可选括号*书名可选括号*"，必须从行首开始
    const wrapPattern = new RegExp(
      '^[' + ChapterTitleFormatter.WRAP_OPEN + ']*' +
      escaped +
      '[' + ChapterTitleFormatter.WRAP_CLOSE + ']*'
    );
    const match = title.match(wrapPattern);
    if (!match || match[0].length === 0) return title;

    let rest = title.substring(match[0].length);
    // 再剥掉紧跟的分隔符
    rest = rest.replace(ChapterTitleFormatter.LEADING_SEP, '');
    // 全部被剥光说明这条标题就是"书名+括号+分隔符"没实际章节信息 → 退回原标题
    if (!rest) return title;
    return rest;
  }
}
