/**
 * SourceDefinition - 规则配置格式定义
 *
 * 设计原则：
 * 1. 声明式：用 JSON 配置描述抓取逻辑，不写命令式代码
 * 2. 简洁性：只保留 JSONPath + CSS + 模板变量，不支持复杂 JS
 * 3. 可扩展：特殊需求（加密/复杂登录）仍可保留 TS 插件
 */

/**
 * HTTP 请求配置
 */
export interface RequestRule {
  /** URL 模板，支持 {{key}} / {{page}} / {{bookId}} 等变量 */
  url: string;
  /** HTTP 方法 */
  method?: 'GET' | 'POST';
  /** POST body（支持模板变量） */
  body?: string;
  /** 自定义请求头 */
  headers?: Record<string, string>;
  /** 响应类型：json 会自动 parse，html 保持字符串 */
  responseType?: 'json' | 'html';
  /** 字符集（默认 UTF-8） */
  charset?: string;
}

/**
 * 提取规则（支持 JSONPath 或 CSS）
 */
export interface ExtractRule {
  /** JSONPath: $.data.title 或 CSS: .title@text */
  rule: string;
  /** 可选：简单后处理（仅支持单行表达式，如 result.trim() / result.replace(/\s+/g,'') ） */
  postProcess?: string;
}

export interface SearchItemRule {
  name: string;          // 书名
  author: string;        // 作者
  cover: string;         // 封面 URL
  bookId: string;        // 书籍 ID（用于拼接 detail.url）
  intro?: string;        // 简介
  status?: string;       // 状态（连载/完结）
}

export interface DetailFieldsRule {
  name: string;
  author: string;
  cover: string;
  intro: string;
  status?: string;
  /** 目录 URL（可以是提取规则或固定模板） */
  tocUrl: string;
}

export interface TocItemRule {
  name: string;          // 章节名
  chapterId: string;     // 章节 ID（用于拼接 audio/content url）
  chapterUrl?: string;   // 或直接提取完整章节 URL
  duration?: string;     // 音频时长（秒数，可选）
  isVip?: string;        // VIP 标记
}

export interface TocPaginationRule {
  /** 下一页 URL 提取规则 */
  nextPageRule: string;
  /** 最大抓取页数（防死循环） */
  maxPages: number;
}

export interface WebViewRule {
  /** 是否启用 WebView */
  enabled: boolean;
  /** WebView 中执行的 JS 表达式（返回音频 URL） */
  jsExpr?: string;
  /** 从 JS 结果中提取 URL 的正则 */
  sourceRegex?: string;
}

export interface CategoryTabRule {
  title: string;      // 标签标题（如"言情"）
  url: string;        // 分类列表 URL
}

export interface CategoryMenuRule {
  title: string;        // 菜单标题（如"小说"）
  tabs: CategoryTabRule[];
}

export interface HomeBookItemRule {
  name: string;
  author: string;
  cover: string;
  bookId: string;
  intro?: string;
}

export interface HomeBlockItemRule {
  title: string;        // 板块标题
  moreUrl?: string;     // "更多"链接
  layout?: string;      // 布局类型：horizontal / grid
  /** 板块内书籍列表 */
  books: string;
  /** 书籍字段（复用 SearchRule.item） */
  bookItem: HomeBookItemRule;
}

/**
 * 搜索规则
 */
export interface SearchRule {
  /** 搜索请求配置 */
  request: RequestRule;
  /** 书籍列表提取规则（返回数组） */
  list: string;
  /** 列表项字段提取 */
  item: SearchItemRule;
}

/**
 * 详情规则
 */
export interface DetailRule {
  /** 详情请求配置（url 支持 {{bookId}} 变量） */
  request: RequestRule;
  /** 字段提取 */
  fields: DetailFieldsRule;
}

/**
 * 目录规则
 */
export interface TocRule {
  /** 目录请求配置（url 支持 {{tocUrl}} / {{bookId}} 变量） */
  request: RequestRule;
  /** 章节列表提取规则 */
  list: string;
  /** 章节项字段提取 */
  item: TocItemRule;
  /** 是否需要多页抓取（某些源章节列表分散在多个页面） */
  pagination?: TocPaginationRule;
}

/**
 * 音频规则（音频源专用）
 */
export interface AudioRule {
  /** 音频 URL 请求配置 */
  request: RequestRule;
  /** 音频地址提取规则 */
  extract: string;
  /** 可选：WebView 嗅探（当音频地址由 JS 动态生成时） */
  webView?: WebViewRule;
}

/**
 * 正文规则（文本源专用）
 */
export interface ContentRule {
  /** 正文请求配置 */
  request: RequestRule;
  /** 正文内容提取规则 */
  extract: string;
  /** 下一章 URL 提取规则（用于多页拼接） */
  nextPageRule?: string;
}

/**
 * 分类规则（发现页/分类页）
 */
export interface CategoryRule {
  /** 分类菜单（固定配置，不需要抓取） */
  menus: CategoryMenuRule[];
  /** 分类列表规则（复用 SearchRule 结构） */
  list: SearchRule;
}

/**
 * 首页推荐规则
 */
export interface HomeRule {
  /** 首页请求配置 */
  request: RequestRule;
  /** 板块列表提取 */
  blocks: string;
  /** 板块字段提取 */
  blockItem: HomeBlockItemRule;
}

/**
 * 完整源定义
 */
export interface SourceDefinition {
  /** 源 ID（唯一标识） */
  id: string;
  /** 显示名称 */
  name: string;
  /** 站点首页 */
  baseUrl: string;
  /** 描述 */
  desc?: string;
  /** 源类型：0=文本, 1=音频 */
  type: 0 | 1;
  /** 是否支持搜索 */
  searchable: boolean;

  /** 全局请求头（所有请求都会带上） */
  headers?: Record<string, string>;

  /** 搜索规则 */
  search?: SearchRule;
  /** 详情规则 */
  detail: DetailRule;
  /** 目录规则 */
  toc: TocRule;
  /** 音频规则（type=1 时必填） */
  audio?: AudioRule;
  /** 正文规则（type=0 时必填） */
  content?: ContentRule;
  /** 分类规则（可选） */
  category?: CategoryRule;
  /** 首页推荐规则（可选） */
  home?: HomeRule;

  /** 特殊标记：使用自定义引擎（保留 TS 插件） */
  customEngine?: boolean;
}
