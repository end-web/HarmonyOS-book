# 电子书正文处理规则对比分析

## 轻阅（Legado Harmony）的正文处理流程

### 1. 多层次正文提取与清洗

轻阅在 `WebBookService.ts` 中实现了非常完善的正文提取链路：

#### 1.1 规则提取阶段（`getContent` 方法）
```typescript
// 核心流程：
// 1. 通过 contentRule.content 规则提取原始正文
// 2. 支持多种提取规则：JSONPath、CSS、XPath、正则
// 3. 提取失败时自动回退到通用正文提取
```

**关键特性：**
- **分段提取**：支持将章节内容按段落分别匹配，每段一个节点
- **多页拼接**：支持 `nextContentUrl` 自动翻页拼接长章节
- **回退机制**：规则失败时调用 `tryExtractReadableContentFromHtml()` 通用提取
- **防漏提取**：检测是否误提取了规则脚本本身（`isBadExtractedContent`）

#### 1.2 书源内置替换规则（`applyContentReplaceRule` 方法）
```typescript
// contentRule.replaceRegex 字段：书源自带的净化规则
// 格式：正则##替换文本##js脚本
// 示例：广告文字##@@<js>result.replace(/推广/g, '')</js>
```

**处理流程：**
1. 解析 `##` 分隔的正则部分和 JS 部分
2. 支持正则替换：`/pattern/##replacement`
3. 支持 JS 后处理：`##<js>自定义脚本</js>`
4. 支持变量模板：`{{变量名}}`

#### 1.3 通用正文提取回退（`tryExtractReadableContentFromHtml`）
当规则提取失败时，自动尝试：
```typescript
const names = [
  'nr1', 'chaptercontent', 'chapter-content', 'chapter_content',
  'reader-content', 'read-content', 'article-content',
  'TxtContent', 'txtcontent', 'word_read', 'readtxt',
  'booktext', 'BookText', 'content', 'post'
];
```
- 按常见正文容器 ID/class 提取
- 自动清理导航链接、广告文字
- 评分机制选择最优候选

#### 1.4 正文标准化（`normalizeReaderContent`）
```typescript
// 统一处理：
// 1. 图片标签转换为 ReaderImageMarker
// 2. Markdown 图片语法转换
// 3. 段评/互动标记转换
// 4. 行内 <br> 转换为换行
// 5. 清理空行和噪音文本
```

### 2. 用户自定义替换规则系统

轻阅实现了完整的 **正文替换规则管理**，独立于书源规则：

#### 2.1 数据模型（`ReaderReplaceRule`）
```typescript
class ReaderReplaceRule {
  id: number;
  name: string;                    // 规则名称
  group: string;                   // 分组
  pattern: string;                 // 匹配模式
  replacement: string;             // 替换文本
  applyToTitle: boolean;           // 应用于章节标题
  applyToContent: boolean;         // 应用于正文
  isRegex: boolean;                // 是否正则
  scope: string;                   // 适用范围（书名/作者/来源）
  excludeScope: string;            // 排除范围
  timeoutMs: number;               // 超时限制
  enabled: boolean;                // 是否启用
}
```

#### 2.2 作用域匹配系统
```typescript
// scope 字段支持：
// 1. 书名、作者、来源名称关键词匹配
// 2. 通配符：*玄幻*、网络*
// 3. 正则表达式：/pattern/flags
// 4. 排除范围：excludeScope 优先级更高
```

#### 2.3 并发安全执行（TaskPool）
```typescript
// ReaderContentPreprocessor.ets
@Concurrent
function applyReaderRulesInTask(text: string, rulesJson: string, scopeText: string)
```
- 使用 **TaskPool** 隔离执行，防止恶意正则阻塞 UI
- 检测嵌套量词（灾难性回溯），自动跳过危险规则
- 超时保护机制

#### 2.4 实时验证功能（`checkRule`）
```typescript
// 返回结果：
state: 'effective' | 'matched' | 'noMatch' | 'disabled' | 'invalid' | 'outOfScope'
titleMatched: boolean      // 标题是否匹配
contentMatched: boolean    // 正文是否匹配
changed: boolean           // 替换后是否有变化
```

### 3. 特殊处理机制

#### 3.1 段评/互动标记（Reader Action Marker）
```typescript
// 支持三种交互标记：
// 1. 普通链接动作：[[LEGADO_READER_ACTION_V3:json]]
// 2. 来源脚本：legado-source-action:script
// 3. 第三方段评服务：provider-action://provider/book/chapter/paragraph
```

#### 3.2 图片处理
- 提取 `<img>` 标签转换为占位符
- 支持 base64 内联图片
- 支持漫画图片解密（`imageDecode` 规则）
- 支持懒加载属性：`data-src`, `data-original` 等

#### 3.3 反向文本修复
```typescript
// repairReversedLine：检测并修复顺序错乱的文本行
// 适用于某些网站防爬机制导致的文字反序
```

---

## ListenBook 的正文处理现状

### 当前实现

#### 1. 本地规则提取（`LocalRuleStageExtractor.ets`）
```typescript
// 支持的提取方式：
// 1. JSONPath
// 2. CSS Selector
// 3. XPath
// 4. 正则表达式
// 5. 脚本（@js）
```

#### 2. 净化功能（`applyCleanup`）
```typescript
// 仅支持书源内置的正则替换：
static applyCleanup(value: string, pattern: string): string {
  // pattern 格式：/regex/##replacement
  return value.replace(new RegExp(regexText, 'g'), replacement);
}
```

#### 3. HTML 清理（`stripHtml`）
```typescript
// 标准 HTML 标签清理：
// - 移除 script/style 标签
// - 转换 br/hr 为换行
// - 转换块级元素为换行
// - HTML 实体解码
```

### ❌ 缺失功能

1. **没有用户自定义替换规则系统**
   - 无法创建自定义净化规则
   - 无法管理规则分组
   - 无法按书籍作用域过滤
   
2. **没有正文提取回退机制**
   - 规则失败时直接返回空
   - 无通用提取器兜底

3. **没有替换规则验证工具**
   - 无法预览规则效果
   - 无法诊断规则问题

4. **没有并发安全保护**
   - 恶意正则可能阻塞主线程
   - 无超时保护

---

## 核心差距与实现建议

### 🔴 P0 - 必须实现

#### 1. 用户自定义替换规则系统

**文件结构：**
```
entry/src/main/ets/
  model/
    TextReplaceRule.ets           # 数据模型
  service/
    text/
      TextReplaceRuleService.ets  # 规则管理服务
      TextReplaceProcessor.ets    # 规则执行器（TaskPool）
  pages/
    TextReplaceRulePage.ets       # 规则管理页面
```

**核心 API：**
```typescript
// 1. 规则模型
class TextReplaceRule {
  id: string;
  name: string;
  pattern: string;
  replacement: string;
  scope: string;              // 书名/作者/来源关键词
  excludeScope: string;
  applyToTitle: boolean;
  applyToContent: boolean;
  isRegex: boolean;
  enabled: boolean;
  order: number;
}

// 2. 规则服务
class TextReplaceRuleService {
  static async loadRules(): Promise<TextReplaceRule[]>
  static async saveRules(rules: TextReplaceRule[]): Promise<void>
  static async importRules(json: string): Promise<number>
  static async exportRules(): Promise<string>
}

// 3. 执行器
class TextReplaceProcessor {
  static async apply(
    text: string,
    rules: TextReplaceRule[],
    book: Book,
    isTitle: boolean
  ): Promise<string>
  
  static checkRule(
    rule: TextReplaceRule,
    title: string,
    content: string
  ): RuleCheckResult
}
```

**存储方案：**
```typescript
// Preferences 存储：
// - 键：text_replace_rules
// - 值：JSON 序列化的规则数组
// - 路径：context.preferencesDir/text_replace_rules.preferences
```

#### 2. 正文提取回退机制

在 `LocalRuleContentService` 中添加：
```typescript
private tryExtractReadableContent(html: string): string {
  const containers = [
    'content', 'article', 'chapter-content',
    'main-content', 'read-content', 'text-content'
  ];
  // 1. 按常见容器 ID/class 提取
  // 2. 评分选择最优候选
  // 3. 清理噪音文本
}
```

### 🟡 P1 - 重要增强

#### 3. 书源内置 `replaceRegex` 字段

在 `LocalRuleSource` 数据模型中添加：
```typescript
class LocalRuleContentRule {
  content: string;
  images: string;
  nextContentUrl: string;
  replaceRegex: string;  // 新增：书源内置替换规则
}
```

在正文提取后应用：
```typescript
// LocalRuleContentService.extractContent()
let content = await this.extractByRule(/* ... */);
if (source.contentRule.replaceRegex) {
  content = this.applyReplaceRegex(content, source.contentRule.replaceRegex);
}
```

#### 4. 规则执行安全保护

```typescript
// 使用 TaskPool 隔离执行
@Concurrent
function applyRulesInTask(
  text: string,
  rules: string,
  scope: string
): string {
  // 1. 检测嵌套量词
  if (/(?:\([^)]*[+*][^)]*\)|\[[^\]]+\][+*])[+*{]/.test(pattern)) {
    return text; // 跳过危险规则
  }
  // 2. 应用替换
  // 3. 超时自动终止
}
```

### 🟢 P2 - 用户体验优化

#### 5. 替换规则管理页面

功能列表：
- ✅ 规则列表（名称、状态、作用域）
- ✅ 新建/编辑/删除规则
- ✅ 规则分组管理
- ✅ 启用/禁用开关
- ✅ 排序调整
- ✅ 导入/导出规则
- ✅ 规则测试预览（输入文本 → 查看替换效果）
- ✅ 作用域智能提示

#### 6. 阅读页内快速创建规则

在 `ReaderPage` 长按文本时：
```typescript
// 1. 选中广告文字
// 2. 弹出菜单："创建替换规则"
// 3. 自动填充 pattern，用户确认
// 4. 立即生效，当前章节重新加载
```

---

## 实现优先级建议

### 第一阶段（2 周）
1. 实现 `TextReplaceRule` 数据模型
2. 实现 `TextReplaceRuleService` 规则管理
3. 在 `OnlineTextPaginator` 中集成规则应用
4. 实现规则管理页面基础功能

### 第二阶段（1 周）
5. 实现 TaskPool 并发安全执行
6. 添加规则测试预览功能
7. 实现导入/导出

### 第三阶段（1 周）
8. 实现正文提取回退机制
9. 添加书源 `replaceRegex` 支持
10. 阅读页快速创建规则入口

---

## 关键代码参考

### 轻阅的替换规则执行器（核心逻辑）

```typescript
// D:/legado-harmony/entry/src/main/ets/core/concurrency/ReaderContentPreprocessor.ets

@Concurrent
function applyReaderRulesInTask(text: string, rulesJson: string, scopeText: string): string {
  let rules: Record<string, Object>[] = [];
  try {
    const parsed = JSON.parse(rulesJson || '[]') as Object;
    if (Array.isArray(parsed)) rules = parsed as Record<string, Object>[];
  } catch (_) {
    return text;
  }
  
  let result = text || '';
  const target = (scopeText || '').toLowerCase();
  
  for (let index = 0; index < rules.length; index++) {
    const rule = rules[index];
    if (rule['enabled'] === false || rule['applyToContent'] === false) continue;
    
    const pattern = String(rule['pattern'] || '');
    if (!pattern || pattern.length > 4096) continue;
    
    // 作用域检查
    let scopeAllowed = true;
    const includeTokens = String(rule['scope'] || '').split(/[\n,，;；]+/)
      .map((value: string): string => value.trim().toLowerCase())
      .filter((value: string): boolean => !!value);
    
    if (includeTokens.length > 0) {
      scopeAllowed = false;
      for (let tokenIndex = 0; tokenIndex < includeTokens.length; tokenIndex++) {
        const token = includeTokens[tokenIndex];
        let matches = false;
        
        // 正则匹配
        if (token.startsWith('/') && token.lastIndexOf('/') > 0) {
          const end = token.lastIndexOf('/');
          try {
            matches = new RegExp(token.substring(1, end), token.substring(end + 1)).test(target);
          } catch (_) {}
        }
        // 通配符匹配
        else if (token.includes('*')) {
          const escaped = token.replace(/[.+?^${}()|[\]\\]/g, '\\$&').replace(/\*/g, '.*');
          try {
            matches = new RegExp(escaped, 'i').test(target);
          } catch (_) {}
        }
        // 关键词匹配
        else {
          matches = target.includes(token);
        }
        
        if (matches) {
          scopeAllowed = true;
          break;
        }
      }
    }
    if (!scopeAllowed) continue;
    
    // 排除作用域检查（省略，逻辑同上）
    
    // 应用替换
    try {
      const replacement = String(rule['replacement'] || '');
      if (rule['isRegex'] !== false) {
        // 防止灾难性回溯
        if (/(?:\([^)]*[+*][^)]*\)|\[[^\]]+\][+*])[+*{]/.test(pattern)) continue;
        result = result.replace(new RegExp(pattern, 'g'), replacement);
      } else {
        result = result.split(pattern).join(replacement);
      }
    } catch (_) {
    }
  }
  return result;
}

export class ReaderContentPreprocessor {
  static async apply(text: string, rules: ReaderReplaceRule[], book: Book | null): Promise<string> {
    if (!text || !ReaderContentPreprocessor.hasActiveContentRules(rules)) return text;
    
    const scopeText = book ? `${book.name || ''}\n${book.author || ''}\n${book.originName || ''}\n` +
      `${book.origin || ''}\n${book.bookUrl || ''}` : '';
    
    try {
      const value = await taskpool.execute(applyReaderRulesInTask, text, JSON.stringify(rules), scopeText);
      return typeof value === 'string' ? value : text;
    } catch (error) {
      console.warn('[ReaderPreprocessor] TaskPool failed, keep original content:', error);
      return text;
    }
  }
}
```

### 轻阅的规则验证器

```typescript
// D:/legado-harmony/entry/src/main/ets/utils/ReaderReplaceRuleStore.ets

static checkRule(
  sourceRule: ReaderReplaceRule,
  book: Book | null,
  title: string,
  content: string
): ReaderReplaceRuleCheck {
  const result = new ReaderReplaceRuleCheck();
  const rule = ReaderReplaceRuleStore.normalize(sourceRule);
  
  if (!rule.enabled) {
    result.state = 'disabled';
    result.label = '已禁用';
    return result;
  }
  
  if (!rule.pattern) {
    result.state = 'invalid';
    result.label = '规则无效：匹配内容为空';
    result.valid = false;
    return result;
  }
  
  result.scopeMatched = ReaderReplaceRuleStore.matchesBookScope(rule, book);
  if (!result.scopeMatched) {
    result.state = 'outOfScope';
    result.label = '不适用于当前书籍';
    return result;
  }
  
  try {
    if (rule.isRegex) {
      const titleRegex = new RegExp(rule.pattern, 'g');
      const contentRegex = new RegExp(rule.pattern, 'g');
      result.titleMatched = rule.applyToTitle && !!title && titleRegex.test(title);
      result.contentMatched = rule.applyToContent && !!content && contentRegex.test(content);
      
      if (result.titleMatched) {
        result.changed = title.replace(new RegExp(rule.pattern, 'g'), rule.replacement) !== title;
      }
      if (result.contentMatched) {
        result.changed = result.changed ||
          content.replace(new RegExp(rule.pattern, 'g'), rule.replacement) !== content;
      }
    } else {
      result.titleMatched = rule.applyToTitle && !!title && title.includes(rule.pattern);
      result.contentMatched = rule.applyToContent && !!content && content.includes(rule.pattern);
      
      if (result.titleMatched) {
        result.changed = title.split(rule.pattern).join(rule.replacement) !== title;
      }
      if (result.contentMatched) {
        result.changed = result.changed || content.split(rule.pattern).join(rule.replacement) !== content;
      }
    }
  } catch (error) {
    result.state = 'invalid';
    result.label = `规则无效：${error instanceof Error ? error.message : String(error)}`;
    result.valid = false;
    return result;
  }
  
  if (result.titleMatched || result.contentMatched) {
    result.state = result.changed ? 'effective' : 'matched';
    result.label = result.changed ? '当前章节已生效' : '已匹配，替换结果未变化';
  }
  
  return result;
}
```

---

## 总结

轻阅在正文处理方面的核心优势：
1. **三层净化体系**：书源内置 → 用户自定义 → 实时验证
2. **智能回退机制**：规则失败时自动尝试通用提取
3. **作用域系统**：规则可按书籍/作者/来源精确匹配
4. **并发安全**：TaskPool 隔离执行，防止恶意规则
5. **完整管理界面**：规则 CRUD、测试、导入导出

ListenBook 需要从零开始构建用户自定义替换规则系统，建议参考轻阅的实现，优先完成 P0 功能以提升用户体验。
