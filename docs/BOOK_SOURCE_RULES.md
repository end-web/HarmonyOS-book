# 简听书源规则编写指南

本文面向希望为「简听」编写书源的作者，依据当前项目的导入解析器、请求分析器、规则执行器和页面调用链整理。核对日期：2026-09-22。

书源文件使用 **UTF-8 JSON**，规则在手机本地执行，不需要部署简听服务端。支持小说正文源和有声书源；与 Legado / Reader 的规则格式有兼容交集，但不是完整兼容实现。

与 Legado 系源码的具体语义差异和补齐顺序见 [书源兼容性对照](BOOK_SOURCE_COMPATIBILITY.md)。

文中 `example.com` / `example.org` 均为占位域名。模板展示完整字段关系，**需要按目标站点替换地址、选择器和接口字段后才能获取实际内容**，不是已经联通的在线书源。

## 目录

- [1. 先了解内容链路](#1-先了解内容链路)
- [2. 文件格式与顶层字段](#2-文件格式与顶层字段)
- [3. 五组规则字段](#3-五组规则字段)
- [4. 提取规则语法](#4-提取规则语法)
- [5. 请求地址、POST 与请求头](#5-请求地址post-与请求头)
- [6. 完整示例：HTML 小说源](#6-完整示例html-小说源)
- [7. 完整示例：JSON 听书源](#7-完整示例json-听书源)
- [8. 发现分类与首页](#8-发现分类与首页)
- [9. JavaScript 与变量](#9-javascript-与变量)
- [10. 登录、Cookie 与动态网页](#10-登录cookie-与动态网页)
- [11. 兼容范围与执行上限](#11-兼容范围与执行上限)
- [12. 导入、调试与交付](#12-导入调试与交付)
- [13. 常见问题](#13-常见问题)
- [14. 实现依据](#14-实现依据)

## 1. 先了解内容链路

通常按以下顺序编写，先跑通一本书，再补充发现、登录等能力。

```text
搜索关键词
  → searchUrl 发起请求
  → ruleSearch.bookList 选出书籍列表
  → 对每本书提取 name、bookUrl 等
  → 请求 bookUrl，使用 ruleBookInfo 提取详情和 tocUrl
  → 请求 tocUrl，使用 ruleToc 提取章节列表
  → 请求 chapterUrl，使用 ruleContent 提取正文或音频地址

发现入口
  → exploreUrl 提供分类名称和分类地址
  → 请求某个分类地址，使用 ruleExplore 提取书籍列表
  → 进入同一套详情、目录、正文 / 播放链路
```

| App 中看到的内容 | 作者需要配置 |
| --- | --- |
| 搜索结果 | `searchUrl`、`ruleSearch` |
| 书籍详情 | `ruleBookInfo` |
| 章节目录 | `ruleBookInfo.tocUrl`、`ruleToc` |
| 小说正文 | `ruleContent.content` |
| 音频播放 | `ruleContent.audioUrl`，或目录直接提供可识别的音频直链 |
| 发现分类 | `enabledExplore`、`exploreUrl`、`ruleExplore` |
| 首页推荐与分类 | 用户选择的已启用听书源及其发现内容 |

书源定义导入后存入本地加密数据库。作者只需要交付 JSON，不需要创建数据库表或修改 App 页面。

## 2. 文件格式与顶层字段

### 2.1 外层格式

可以导入单个书源对象或书源数组，推荐数组，便于一个文件发布多个源：

```json
[
  {
    "bookSourceName": "我的小说源",
    "bookSourceUrl": "https://novel.example.com",
    "bookSourceType": 0
  }
]
```

上例只能验证导入结构，还没有搜索和阅读能力。完整模板见第 6、7 节。

也识别对象中 `value`、`data`、`sources`、`bookSources`、`bookSourceList`、`list` 数组包装。一次最多解析 1000 个书源。JSON 不允许注释、尾随逗号或单引号字符串。

### 2.2 常用字段

| 字段 | 类型 | 默认值 / 要求 | 作用 |
| --- | --- | --- | --- |
| `bookSourceName` | string | 必填、非空 | 书源显示名称 |
| `bookSourceUrl` | string | 必填、非空 | 书源唯一标识和请求基地址；普通源使用稳定的 HTTP(S) 站点地址 |
| `bookSourceType` | number | `0` | `0` 小说；`1` 音频 |
| `bookSourceGroup` | string | `""` | 分组；新源推荐使用清晰的字符串 |
| `bookSourceComment` | string | `""` | 使用说明、作者、版本、登录要求等 |
| `enabled` | boolean | `true` | 启用状态；参与搜索还需有完整搜索规则 |
| `enabledExplore` | boolean | 有非空 `exploreUrl` 时为 `true`，否则 `false` | 是否启用发现；显式 `false` 保持关闭，重导保留本机开关 |
| `searchUrl` | string | `""` | 搜索请求模板 |
| `exploreUrl` | string | `""` | 发现分类定义，不是直接填写列表选择器 |
| `header` | object / string | 空 | 公共 HTTP 请求头；推荐对象，也接受 JSON 字符串或逐行 Header |
| `enabledCookieJar` | boolean | `true` | 是否使用 Cookie 管理 |
| `respondTime` | number | `18000` | 请求超时，毫秒；实际限制在 3000–60000 |
| `concurrentRate` | string | `""` | 请求限流，见第 5 节 |
| `ruleSearch` | object | 空规则组 | 搜索提取规则 |
| `ruleExplore` | object | 空规则组 | 发现列表提取规则 |
| `ruleBookInfo` | object | 空规则组 | 详情规则 |
| `ruleToc` | object | 空规则组 | 目录规则 |
| `ruleContent` | object | 空规则组 | 正文 / 音频规则 |

`bookSourceUrl` 是保存收藏、会话等数据时的重要标识，不应随意改动。同一站点有多个定义时应保持各自身份稳定，并确认基地址仍能正确解析相对链接。

### 2.3 可选高级字段

| 字段 | 类型 | 说明 |
| --- | --- | --- |
| `loginUrl` | string | HTTPS 登录页地址，或兼容登录面板使用的脚本定义 |
| `loginUi` | array / string | 登录面板；数组导入时会转为 JSON 字符串保存 |
| `loginCheckJs` | string | 登录结果检查脚本，返回文本 `false` 表示失败 |
| `jsLib` | string | 公共 JavaScript，或远程库地址；多地址须写成 JSON 数组字符串 |
| `variable` | object / string | 来源初始变量配置 |
| `lastUpdateTime` | number | 更新时间，毫秒时间戳 |
| `isLocked` | boolean | 默认 `false`；锁定后不能直接修改、重导入、改分组、改启用或删除 |
| `isPinned` | boolean | 默认 `false`；置顶 |
| `customOrder` | number | 默认 `0`；自定义排序 |

不要在发布模板中预设锁定，也不要携带个人 Cookie、Token、密码或设备会话。

导入器还保留部分未知字段以便再次导出，**字段被保留不代表已被执行**。类型枚举中的 `2`、`3` 也不代表已有完整漫画或网络文件阅读能力；新书源请使用 `0` / `1`。

### 2.4 兼容的规则组写法

支持 `searchRule`、`exploreRule`、`bookInfoRule`、`tocRule`、`contentRule` 作为对应 `ruleXxx` 的旧别名，也支持 `@{name=规则;bookUrl=规则}` 紧凑规则组及 JSON 对象字符串。

新源统一使用 `ruleXxx` 对象形式，便于校验和维护；每个具体提取字段的值写字符串，别将规则写成嵌套对象。

## 3. 五组规则字段

### 3.1 `ruleSearch` / `ruleExplore`

| 字段 | 提取目标 | 上下文 / 注意事项 |
| --- | --- | --- |
| `bookList` | 书籍节点或对象数组 | 整个列表响应 |
| `name` | 书名 | 单本书节点 / 对象 |
| `bookUrl` | 详情 URL | 单本书；空地址或空书名会导致该结果被跳过 |
| `author` | 作者 / 演播信息 | 单本书 |
| `coverUrl` | 封面 URL | 单本书；支持相对 URL |
| `intro` | 简介 | 单本书 |
| `kind` | 分类标签 | 单本书 |
| `status` | 连载 / 完结 | 单本书 |
| `lastChapter` | 最新章节名称 | 单本书 |
| `wordCount` | 字数或数量文案 | 单本书 |
| `updateTime` | 更新时间规则 | 搜索、发现与详情保留源返回文本，并传入详情页和书籍缓存 |
| `nextPageUrl` | 下一页列表 URL | 当前发现链会提取；搜索链不会据此自动追页 |

参与聚合搜索的最低条件：源已启用，且 `searchUrl`、`ruleSearch.bookList`、`ruleSearch.name`、`ruleSearch.bookUrl` 都非空。

`ruleExplore` 只有同时具备 `bookList`、`name`、`bookUrl` 时才被选用，否则发现提取整体回退到 `ruleSearch`。并非逐字段回退。

### 3.2 `ruleBookInfo`

| 字段 | 含义 |
| --- | --- |
| `init` | 可选预处理：先提取一个 HTML 区块、JSON 对象或脚本结果，再在其上提取详情字段；结果为空时仍使用原响应 |
| `name`、`author`、`coverUrl`、`intro` | 书名、作者、封面、简介 |
| `kind`、`status`、`lastChapter`、`wordCount` | 分类、状态、最新章节、字数文案 |
| `tocUrl` | 目录请求地址；为空时使用详情请求地址 |
| `updateTime` | 导入保留，当前通用详情映射未使用 |

例如响应是 `{"data":{"name":"示例书","toc":"/toc/1"}}`，可以配置 `init: "$.data"`，然后 `name: "$.name"`、`tocUrl: "$.toc"`。使用 `init` 后，不要继续在字段中写 `$.data.name`。

### 3.3 `ruleToc`

| 字段 | 含义 |
| --- | --- |
| `chapterList` | 从目录响应选择章节节点 / 对象列表 |
| `chapterName` | 从单章节点提取章节名；为空时生成章节序号名称 |
| `chapterUrl` | 从单章节点提取内容请求地址；空地址跳过，重复地址去重 |
| `nextTocUrl` | 从整个目录响应提取下一页目录地址；自动追页并检测重复 |
| `isVip`、`isPay` | VIP / 付费标记；不是自动解锁付费内容 |
| `isVolume` | 分卷标记；仍需符合章节条目的地址要求 |
| `updateTime` | 章节更新时间文本 |
| `duration` | 音频时长；数字按秒，也接受 `12:30`、`01:02:03` |

布尔字段应返回 `true` / `false` 或 `1` / `0`。实现还将 `yes`、`vip`、`pay`、`paid`、`付费`、`收费`、`完结` 视为真；**任意非空文本并不自动为真**。

若网站目录倒序，可在列表规则前加 `-`，如 `-$.chapters[*]`。这是对本次选出的列表倒序；分页目录不会因此自动整体反转页序。

### 3.4 `ruleContent`

| 字段 | 含义 |
| --- | --- |
| `content` | 小说正文；音频源中也可作为音频 URL 的兼容回退 |
| `title` | 正文标题 |
| `audioUrl` | 优先提取音频地址，推荐音频源显式配置 |
| `nextContentUrl` | 同一章节的下一分页地址；不是下一章 |
| `replaceRegex` | 正文清理，格式 `正则##替换值`；只写正则表示删除匹配内容 |
| `sourceRegex` | 音频兜底匹配 / 网页资源过滤正则 |

正文若返回 HTML，会清除标签、脚本和样式并保留常见段落换行，再执行 `replaceRegex`。正文多页按顺序拼接。

`sourceRegex` 对响应文本匹配时取第一个捕获组，没有捕获组则取完整匹配。对网页资源 URL 则用来筛选候选地址。不要用它返回错误提示或整段播放器 HTML。

## 4. 提取规则语法

### 轻页小说与听书规则兼容

通用链接受轻页的小说、文本文件和有声书定义，不依赖站点域名或专用协议适配。支持以下执行语义：

- 原始规则组与未知扩展字段保留；CSS、XPath、JSONPath、模板和组合规则在各自当前元素上求值。
- CSS 复合选择器点号索引、`.0:5` 范围、三个以上数字的显式索引列表、`!` 排除；表格行和单元格片段保留节点结构。
- `@json:`、`.field` 和裸 JSON 路径、单花括号 JSONPath；JSON 字段接脚本时保留对象结构。
- Java 正则常见内联标志、`\Q…\E`、空白/换行转义、`$0` 与直接正则捕获组；简单占有量词和原子组会降级，危险嵌套转换拒绝执行。局部标志、特殊属性名和字符类交集不保证 Java 完全等价。
- 响应头 `headers().get(name)` 大小写无关及 `names()`；元素 `ownText()`、`hasAttr()`；无连接响应以 599 回放给脚本判断，不视为成功内容。
- Java 兼容层的 `Cipher.getInstance('ChaCha20-Poly1305')` 支持 `SecretKeySpec`、`IvParameterSpec` / `GCMParameterSpec(128, nonce)` 和 `updateAAD`，使用 32 字节密钥、12 字节 nonce、16 字节认证标签；解密前校验认证标签。固定算法运行在受限 QuickJS 中，不依赖 API 22 的系统 Poly1305 接口，也不开放任意 Java 类。
- 显式 `session` 即使关闭普通 Cookie Jar 仍生效，按源和目标域隔离持久化；跨源重定向清除目标相关请求头。
- 音频源无正文提取规则时，允许无扩展名的 HTTP(S) GET 签名直链；显式 `webView` 仍执行网页抓取。脚本通过 `source.put('type', 'audio'/'text')` 声明类型，书籍保存所选类型，后续切换源分类不会改变已有书籍类型。
- 搜索、发现、详情的 `updateTime` 保留站点原文；字数、最新章节、更新时间写入书籍缓存，详情标签下展示更新时间。目录的 `updateTime`、`isVip`、`isPay` 同时保存在章节上下文。

执行环境继续采用受限 QuickJS 和受控网页桥，不需要复制轻页的引擎路由实现。现有 `@html` 返回元素内部 HTML，列表中间值保留外层 HTML；不宣称与轻页所有 HTML 字符串输出逐字一致。网页脚本使用请求选项 `webView`/`webJs`；音频正文的 `content` / `audioUrl` 也接受完整 `@webjs:` 规则，通过隔离网页和受控 DOM 动作执行，最多轮询十次，仅接收 HTTP(S) 音频地址。普通 `webJs` 空结果仍回退交互后的 DOM，`@webjs:` 音频未取到地址则明确报错。漫画图片阅读和段评交互不在本轮小说/听书范围内。

### 4.1 HTML：CSS 与 XPath

推荐标准 CSS 选择器：

| 规则 | 作用 |
| --- | --- |
| `.book-list .book` | 选出书籍节点列表 |
| `h3@text` | 读取子节点文本 |
| `a.detail@href` | 读取子链接地址 |
| `img@src` / `img@data-src` | 普通封面 / 懒加载封面 |
| `#content@html` | 正文 HTML，交给正文链清理并保留段落 |
| `@text` / `@html` | 当前节点文本 / 内部 HTML |
| `@href` | 当前节点自身的链接属性 |
| `div@ownText` | 节点自身文本，不含子元素文本 |
| `div@textNodes` | 提取文本节点 |
| `@css:.book a@href` | 显式 CSS 前缀 |
| `@xpath://div[@id='content']` | 显式 XPath |
| `@xpath://a[@class='detail']/@href` | XPath 提取属性 |

**上下文很重要：**若 `chapterList` 已选中 `#chapters a`，`chapterName` 应写 `@text`，`chapterUrl` 写 `@href`；不要再找一个并不存在的子级 `a`。

兼容常见 `class.foo`、`id.foo`、`tag.a`、`a.0` 和 `@` 选择链，例如 `class.book@tag.a@href`。新规则建议优先用清晰的标准 CSS，特殊伪类和历史语法需在 App 内验证。

普通 HTML 提取只解析已下载内容，不会自动执行网站 JavaScript。浏览器里看得到、原始响应里没有的数据，需要寻找 JSON 接口，或显式使用动态网页选项。

### 4.2 JSON：JSONPath

| 规则 | 作用 |
| --- | --- |
| `$.data.books[*]` | 选择书籍数组每个元素 |
| `$.data.books` | 直接选择数组，列表提取时也会展开 |
| `$.name` | 当前对象的名称 |
| `$['book-name']` | 带特殊字符的属性 |
| `$.items[0]` | 数组第一个元素 |
| `$.items[0:10]` | 数组切片 |
| `$.items[?(@.enabled == true)]` | 条件过滤 |
| `$..title` | 递归提取同名属性，建议仅在确实需要时使用 |

支持属性、索引、通配、索引联合、切片、过滤和递归下降；过滤有逻辑、比较、存在性及正则匹配子集。复杂第三方 JSONPath 表达式仍需单独验证。

JSON 响应中也接受 `name`、`data.books` 等简写及 `@json:` 前缀，推荐完整 `$.` 写法。

### 4.3 拼接 URL、备选与组合

字段规则可以通过模板拼接 URL：

```json
{
  "bookUrl": "https://api.example.com/books/{{$.id}}",
  "coverUrl": "img@data-src||img@src"
}
```

| 语法 | 含义 |
| --- | --- |
| `规则A||规则B` | A 有非空结果就用 A，否则用 B |
| `规则A&&规则B` | 顺序合并两组结果 |
| `规则A%%规则B` | 交错合并两组结果 |
| `-列表规则` | 反转选出的列表 |
| `{{$.id}}` | 在当前 JSON 对象提取字段后插入模板 |

字段多值通常以换行合并；URL 字段通常选第一个可解析地址。列表字段则保持列表语义。带 `<js>...</js>` 的备选字段分别基于原始节点求值，脚本内部的 `||` 不作为字段分隔符。

简介展示会解码 HTML 实体，清除 `<br>`、`</br>`、段落等标签并保留换行；这一转换在字段规则执行完成后进行，不影响脚本读取 HTML 或章节正文。

相对 URL 通常依据**当前响应地址**补全；初始请求依据 `bookSourceUrl` 补全。支持 `/path`、`../path`、`?page=2`、`//cdn.example.com/a.jpg`。不要返回 `javascript:`、`file:` 或空锚点作为书籍、章节地址。

### 4.4 正则处理

字段后处理格式：`基础规则##正则##替换值`。

```json
{
  "author": ".author@text##^作者[:：]\\s*##",
  "name": "$.title##\\s+## "
}
```

正文净化不需要基础规则：

```json
{
  "content": "#content@html",
  "replaceRegex": "请收藏本站[^\\n]*##"
}
```

正则表达式本身使用 `\s`、`\n`、`\.`；将表达式放入 JSON 字符串时，每个反斜杠都必须再转义一次（参见上方可直接解析的 JSON 示例）。JSON 字符串中的换行转义与正则文本的反斜杠转义不可混淆。`##` 是处理分隔符，表达式确实需要该字面量时需转义。

## 5. 请求地址、POST 与请求头

### 5.1 GET 与模板变量

```json
{
  "searchUrl": "https://novel.example.com/search?q={{key}}&page={{page}}"
}
```

| 变量 | 含义 |
| --- | --- |
| `{{key}}`、`{{searchKey}}`、`{{keyword}}` | 搜索关键词；普通 URL 模板会做 URL 编码 |
| `{{searchKeyRaw}}` | 未编码关键词，只有自己处理编码时才用 |
| `{{page}}`、`{{pageIndex}}` | 从 1 开始的页码 |
| `{{page-1}}` | 适配从 0 开始的页码 |
| `{{(page-1)*20}}` | 脚本模板计算偏移量 |
| `{{source.bookSourceUrl}}` | 来源地址 |
| `{{source.bookSourceName}}` | 来源名称 |

兼容轻页的页码候选地址，如 `/yanqing/<,index_{{page}}.html>`：第 1 页为 `/yanqing/`，第 2 页为 `/yanqing/index_2.html`；后续页继续使用最后一个候选并展开页码。

地址分析支持页码，不等于所有页面都会自动加载后续页。当前聚合搜索页面调用默认搜索页；不要假定填写分页变量就能搜索完整站点。

### 5.2 URL 请求选项

规则中的实际格式是一个字符串：`URL,{请求选项JSON}`。以下都是可以放进书源的 JSON 片段。

表单 POST：

```json
{
  "searchUrl": "https://novel.example.com/search,{\"method\":\"POST\",\"headers\":{\"Content-Type\":\"application/x-www-form-urlencoded\"},\"body\":\"q={{key}}&page={{page}}\"}"
}
```

JSON POST：

```json
{
  "searchUrl": "https://api.example.com/search,{\"method\":\"POST\",\"headers\":{\"Content-Type\":\"application/json\"},\"body\":{\"keyword\":\"{{key}}\",\"page\":\"{{page}}\"}}"
}
```

结构化 body 中关键词保持原文；上例 `page` 是字符串。若接口严格要求数字，可用 JavaScript 构造对象再序列化。不要对关键词重复 `encodeURIComponent`。

| 选项 | 含义 |
| --- | --- |
| `method` | `GET`、`POST`、`PUT`、`PATCH`、`DELETE`、`HEAD`；默认 GET |
| `headers` / `header` | 本次请求头，合并到公共 Header；支持对象或 Header 字符串 |
| `body` | 字符串或对象；GET / HEAD 不发送 body |
| `rawBody` | 禁用非结构化 body 的后续字符编码处理；不是二进制上传开关 |
| `charset` | 字符集，默认 `utf-8`；非 UTF-8 站点需与实际响应一致 |
| `retry` | 额外重试次数，限制 0–2 |
| `redirect` / `followRedirects` | 是否跟随重定向，默认 true |
| `bodyJs` | 转换当前响应的脚本 |
| `webView` | 显式启用网页渲染 |
| `webJs` | 受限网页交互脚本；存在时也会启用网页渲染 |
| `webHtml` | 网页模式下提供 HTML 输入，高级用法 |
| `session` | 声明式请求会话，见第 10 节 |

兼容 `@https://站点/接口?表单内容` 形式的旧 POST 规则，但新源建议使用显式 `method` 和 `body`。

### 5.3 公共 Header 与媒体 Header

```json
{
  "header": {
    "User-Agent": "Mozilla/5.0",
    "Referer": "https://audio.example.com/"
  }
}
```

音频字段也可以返回附带请求头的 URL，例如脚本最终返回：

```text
https://cdn.example.com/1.mp3,{"headers":{"Referer":"https://audio.example.com/"}}
```

App 会拆分实际播放 URL 和请求头。Cookie 按来源、目标站点隔离，不能假定主站登录 Cookie 自动适用于任意 CDN；播放成功后还应验证下载。

### 5.4 限流

| `concurrentRate` | 含义 |
| --- | --- |
| `""` / `"0"` | 不施加此项书源限流 |
| `"1000"` | 同一来源请求启动间隔至少 1000 毫秒 |
| `"5/1000"` | 同一来源每 1000 毫秒滑动窗口最多启动 5 次请求 |
| `"-2"` | 同一来源最多 2 个同时进行的请求 |

无法识别的配置会记诊断并忽略，限流等待过久可能超时。建议按目标服务承载能力设置。

## 6. 完整示例：HTML 小说源

假设站点具有这些页面结构：

| 页面 | HTML 约定 |
| --- | --- |
| `/search?q=关键词&page=1` | 每本书是 `.book-list .book`，内含 `a.detail`、`.author`、`img` |
| 详情页 | `h1`、`.author`、`.cover img`、`#intro`、`a.toc` |
| 目录页 | `#chapters a` 依次给出章节名和 href，`a.next-toc` 指向下一页目录 |
| 正文页 | `h1` 为标题，`#content` 为正文，`a.next-content` 指向本章下一分页 |

保存为 `novel-source.json`，替换占位域名和选择器后导入：

```json
[
  {
    "bookSourceName": "示例小说源",
    "bookSourceUrl": "https://novel.example.com",
    "bookSourceType": 0,
    "bookSourceGroup": "小说",
    "bookSourceComment": "作者：你的名字；版本：1；无需登录。示例域名需替换。",
    "enabled": true,
    "enabledExplore": false,
    "enabledCookieJar": true,
    "respondTime": 18000,
    "concurrentRate": "1000",
    "searchUrl": "/search?q={{key}}&page={{page}}",
    "ruleSearch": {
      "bookList": ".book-list .book",
      "name": "a.detail@text",
      "bookUrl": "a.detail@href",
      "author": ".author@text##^作者[:：]\\s*##",
      "coverUrl": "img@data-src||img@src"
    },
    "ruleBookInfo": {
      "name": "h1@text",
      "author": ".author@text##^作者[:：]\\s*##",
      "coverUrl": ".cover img@src",
      "intro": "#intro@text",
      "tocUrl": "a.toc@href"
    },
    "ruleToc": {
      "chapterList": "#chapters a",
      "chapterName": "@text",
      "chapterUrl": "@href",
      "nextTocUrl": "a.next-toc@href"
    },
    "ruleContent": {
      "title": "h1@text",
      "content": "#content@html",
      "nextContentUrl": "a.next-content@href"
    }
  }
]
```

如果详情页直接包含目录，可以去掉 `tocUrl`。若无目录分页或本章分页，对应字段留空或省略；不要把网站的“下一章”按钮误填进 `nextContentUrl`。

## 7. 完整示例：JSON 听书源

### 7.1 假设接口返回

搜索 `/search?keyword=示例&page=1` 和分类 `/categories/story?page=1`：

```json
{
  "data": {
    "books": [
      {
        "id": "b001",
        "name": "示例有声书",
        "author": "示例演播者",
        "cover": "https://cdn.example.com/b001.jpg",
        "intro": "一本示例有声书"
      }
    ],
    "next": ""
  }
}
```

详情 `/books/b001`：

```json
{
  "data": {
    "name": "示例有声书",
    "author": "示例演播者",
    "cover": "https://cdn.example.com/b001.jpg",
    "intro": "一本示例有声书",
    "toc": "/books/b001/chapters"
  }
}
```

目录 `/books/b001/chapters`：

```json
{
  "data": {
    "chapters": [
      { "id": "c001", "name": "第一集", "duration": 900, "vip": false }
    ],
    "next": ""
  }
}
```

章节 `/chapters/c001`：

```json
{
  "data": {
    "title": "第一集",
    "audio": "https://cdn.example.com/b001/c001.mp3"
  }
}
```

### 7.2 对应完整书源

```json
[
  {
    "bookSourceName": "示例听书源",
    "bookSourceUrl": "https://api.example.com",
    "bookSourceType": 1,
    "bookSourceGroup": "听书",
    "bookSourceComment": "作者：你的名字；版本：1。使用文档约定的 JSON 接口，域名需替换。",
    "enabled": true,
    "enabledExplore": true,
    "enabledCookieJar": true,
    "searchUrl": "/search?keyword={{key}}&page={{page}}",
    "exploreUrl": "故事::/categories/story?page={{page}}\n历史::/categories/history?page={{page}}",
    "ruleSearch": {
      "bookList": "$.data.books[*]",
      "name": "$.name",
      "author": "$.author",
      "coverUrl": "$.cover",
      "intro": "$.intro",
      "bookUrl": "https://api.example.com/books/{{$.id}}"
    },
    "ruleExplore": {
      "bookList": "$.data.books[*]",
      "name": "$.name",
      "author": "$.author",
      "coverUrl": "$.cover",
      "bookUrl": "https://api.example.com/books/{{$.id}}",
      "nextPageUrl": "$.data.next"
    },
    "ruleBookInfo": {
      "init": "$.data",
      "name": "$.name",
      "author": "$.author",
      "coverUrl": "$.cover",
      "intro": "$.intro",
      "tocUrl": "$.toc"
    },
    "ruleToc": {
      "chapterList": "$.data.chapters[*]",
      "chapterName": "$.name",
      "chapterUrl": "https://api.example.com/chapters/{{$.id}}",
      "duration": "$.duration",
      "isVip": "$.vip",
      "nextTocUrl": "$.data.next"
    },
    "ruleContent": {
      "title": "$.data.title",
      "audioUrl": "$.data.audio"
    }
  }
]
```

改成 JSON 小说接口时，设置 `bookSourceType: 0`，把内容字段改成 `content: "$.data.text"`，并让章节接口实际返回该正文属性即可；同时按实际站点调整其他字段。

若目录直接返回 `.mp3` 等可识别的 GET 媒体直链，可将 `chapterUrl` 直接指向媒体。需要签名、POST 或二次解析的地址，建议保留“章节接口 → `audioUrl`”链路，避免把临时音频地址当作稳定章节身份。

## 8. 发现分类与首页

最简单的 `exploreUrl` 使用 `分类名::地址`，多个分类用换行或 `&&` 分隔：

```json
{
  "enabledExplore": true,
  "exploreUrl": "热门::/hot?page={{page}}\n新书::/new?page={{page}}"
}
```

也支持 JSON 面板数组，但 **`exploreUrl` 本身是字符串字段**，不能直接写成数组。正确写法：

```json
{
  "exploreUrl": "[{\"title\":\"热门\",\"url\":\"/hot?page={{page}}\"},{\"title\":\"新书\",\"url\":\"/new?page={{page}}\"}]"
}
```

高级面板可使用 `title`、`type`、`url`、`action`、`value`、`placeholder`、`chars`、`children` / `items`。支持分类、分组、输入框、密码框、选择、开关和按钮等；初次编写只需分类项。脚本形式的 `exploreUrl` 也可以生成面板字符串。

首页选择已启用且支持发现的 **小说或音频源**。通用首页预览源定义的前 4 个可用分类，每个分类最多展示 12 本书；分类里的动作按钮不作为首页分类。用户需要在书源页选择首页源，不会自动汇总所有导入源。

听友与其他通用导入源使用相同解析链路，首页、分类、详情及播放均按源规则执行，不注入“恐怖惊悚”等固定分类，也不自动改写为专用 API。

## 9. JavaScript 与变量

### 9.1 脚本入口与返回值

使用 `@js:` 或 `<js>...</js>`，最后一个表达式作为结果：

```json
{
  "name": "@js: var data = JSON.parse(src); data.name.trim();",
  "bookUrl": "@js: var data = JSON.parse(src); 'https://api.example.com/books/' + encodeURIComponent(data.id);"
}
```

`src` 是当前原始内容字符串。在列表字段中通常是单个书籍 / 章节对象的序列化文本，不是整个响应。`result` 在不同执行阶段可能是原始文本、已解析 JSON 或上一段规则的结果；解析原始 JSON 时优先 `JSON.parse(src)`，不要始终假设 `result` 是字符串。

支持提取后处理链，例如：

```json
{
  "name": "$.name@js: String(result).trim()"
}
```

直接写顶层 `return` 并非普通 JavaScript 的合法用法；简单脚本用最后一个表达式，需要 `return` 时放在函数内。

### 9.2 常见上下文

| 名称 | 用途 |
| --- | --- |
| `src` | 当前原始内容字符串 |
| `result` | 当前阶段 / 上一段规则结果 |
| `baseUrl`、`url` | 当前执行基地址 |
| `key`、`searchKey`、`keyword` | 搜索关键词 |
| `page`、`pageIndex` | 数字页码 |
| `source` | 当前来源元信息和来源状态方法 |
| `book` | 当前链路已有的书籍变量，不是完整原生 Book 对象 |
| `chapter` | 当前章节信息，如 `name`、`index`、`url`；index 从 0 开始 |
| `infoMap` | 登录 / 面板表单值，以控件标题作为键 |

这些变量依赖当前执行阶段。单独调试正文时，不应假定先前搜索、详情才产生的字段一定存在。

详情规则执行前会设置 `book.bookUrl`（当前请求的书籍地址），并通过详情、目录返回的变量传入正文脚本。
字段模板支持 `{{$.bookStatus == 1 ? '完结' : '连载'}}`、`{{$.wordCount + 1}}` 等以 JSON 数据为根的 JavaScript 表达式，仍在受限 QuickJS 中执行；普通 JSONPath、过滤、切片及带特殊字符的方括号属性继续按提取规则处理。

非 JSON 内容中的 `{{id}}` 在没有显式同名变量时，兼容从书籍 URL 派生：优先取查询参数 `book_id`、`bookid`、`id`，其次取 `/book/` 后的末段（保留 `.html` 等后缀），再尝试末尾的字母、数字、下划线或连字符路径段（3–40 字符）。例如 `https://example.com/book/123456.html` 配合 `/book/indexList-{{id}}` 得到 `/book/indexList-123456.html`。JSON 内容中的 `{{id}}` 仍提取 JSON 字段，不会被 URL 默认值覆盖；新规则推荐显式提取需要的 ID，避免依赖 URL 结构。

目录脚本可直接返回对象数组或其 JSON 字符串，无需为引擎路由添加 `try/catch`；音频源可以在 `ruleContent.content` 返回音频 URL，作为 `audioUrl` 的回退。规则自己推算章节或对所有章节返回同一音轨时，解析器会照其定义执行，不会自动补齐真实章节或逐集音频。

### 9.3 常用兼容方法

| 方法 | 用途 / 返回 |
| --- | --- |
| `java.ajax(url)` | 通过受控请求桥获取响应文本 |
| `java.connect(url, headers)` | GET，返回兼容响应对象，可调用 `.body()` |
| `java.post(url, body, headers)` | POST，返回兼容响应对象 |
| `java.getString(rule)` / `java.getStringList(rule)` | 提取当前内容 |
| `java.put(key, value)` / `java.getVariable(key)` | 当前规则变量读写 |
| `java.log(value)` | 记录调试信息 |
| `java.toast(value)` | 面板提示 |
| `java.base64Encode(value)` / `java.base64DecodeToString(value)` | Base64 编解码 |
| `java.urlEncode(value)` / `java.urlDecode(value)` | URL 编解码 |
| `source.getKey()` / `source.getTag()` | 来源地址 / 名称 |
| `source.put(key, value)` / `source.get(key)` | 按来源保存、读取状态 |
| `source.getVariable()` / `source.setVariable(value)` | 来源变量配置读写 |
| `cache.put(key, value, seconds)` / `cache.get(key)` | 来源隔离的缓存 |
| `source.getLoginInfoMap()` / `source.putLoginInfo(value)` | 登录信息 |
| `source.putLoginHeader(value)` / `source.getLoginHeader()` | 登录请求头 |

这是常用子集，不是全部 Java / Android API。`java.get()` 还兼容“读取变量 / 发 HTTP 请求”的重载，新源建议用明确的 `getVariable()` 和 `connect()` 避免歧义。

网络等动作受次数和总响应量限制。脚本可能因外部动作恢复而重放，不要依赖无限循环或不受控副作用。

### 9.4 `@put` / `@get`

```json
{
  "name": "@put:{bookId:$.id}$.name",
  "bookUrl": "https://api.example.com/books/@get:{bookId}"
}
```

第一条规则在当前上下文保存 `bookId`，同时返回书名；第二条读取它。变量随受支持的书籍、章节链路传递，不应把它当作跨书共享全局变量。需要持久来源配置时使用 `source` 状态方法。

### 9.5 `jsLib`

推荐内联小型纯计算函数：

```json
{
  "jsLib": "function cleanName(s) { return String(s).trim(); }",
  "ruleSearch": {
    "bookList": "$.data.books[*]",
    "name": "@js: cleanName(JSON.parse(src).name)",
    "bookUrl": "$.url"
  }
}
```

也支持单个 HTTP(S) 库地址，或装有地址数组的 JSON 字符串；最多 8 个远程库，总长度上限 2 Mi 字符，缓存约 5 分钟。普通 Node.js 包、依赖文件系统的脚本和完整浏览器库不能直接搬进来。

## 10. 登录、Cookie 与动态网页

### 10.1 普通网页登录

配置 HTTPS 登录页和 Cookie 管理：

```json
{
  "loginUrl": "https://novel.example.com/login",
  "enabledCookieJar": true
}
```

用户在 App 的书源登录入口完成登录，站点 Cookie 按“书源 + origin”存入加密存储。网页登录使用独立隐私会话，关闭时清理网页会话。导出的书源定义不携带当前登录会话，接收者需自行登录。

可增加 `loginCheckJs` 检查实际返回页面，例如：

```json
{
  "loginCheckJs": "@js: src.indexOf('退出登录') >= 0"
}
```

判断依据应换成目标站点可靠的登录标志。若登录页完成后没有转到含该标志的页面，此检查会失败。

### 10.2 登录面板

`loginUi` 可用数组描述账号、密码和提交按钮，`action` 脚本通过 `infoMap` 读取输入，调用受控 HTTP 方法完成站点协议，再使用 `source.putLoginHeader()` 等保存会话。字段类型和标题必须与脚本对应。

此处不提供虚构的通用账号登录接口：不同站点的 CSRF、签名、验证码和认证流程必须按实际协议实现。普通网站登录优先使用 HTTPS 登录页。

### 10.3 声明式请求会话

URL 选项里的 `session` 支持查询参数映射 Cookie、生成设备 Cookie 和设置 Referer：

```json
{
  "searchUrl": "https://api.example.com/search?q={{key}},{\"session\":{\"generatedCookies\":{\"device_id\":\"@uuid\"},\"referer\":\"origin\"}}"
}
```

| session 字段 | 示例 | 含义 |
| --- | --- | --- |
| `queryCookies` | `{"sid":"session_id"}` | 将本次 URL 的 `session_id` 查询值写入 Cookie `sid` |
| `generatedCookies` | `{"device_id":"@uuid"}` | 目标 Cookie 缺失时生成，已有时复用 |
| `referer` | `"origin"` / `"request"` / HTTP(S) 地址 | 未显式设置 Referer 时补充 |

生成值还支持 `@random`、`@timestamp_random` 及 `{{timestamp}}`、`{{random}}`、`{{uuid}}` 等模板。这是**请求选项**，不要误写成顶层会话凭据字段。

### 10.4 动态网页与嗅探

必须执行网站脚本才能出现的数据，可以在请求 URL 选项中设置 `webView: true`：

```json
{
  "searchUrl": "https://novel.example.com/search?q={{key}},{\"webView\":true}"
}
```

这会使用受控网页渲染，成本高于普通 HTTP。`webJs` 支持受限 DOM 查询、输入、点击、事件、表单、滚动和跳转，以及有预算的定时回调 / Promise；它不是任意平台脚本入口。`bodyJs` 只转换当前响应。

音频源可以结合网页资源候选与 `sourceRegex` 查找媒体，但 DRM、无法访问的资源、登录失败和不支持的格式不会因为嗅探而自动变为可播放。

等待用户登录的 `java.startBrowserAwait()` 和展示页面的 `java.showBrowser()` 属于高级兼容能力，受互斥、超时和输入输出预算约束。需要在真实设备上验证用户取消、登录完成和重新请求流程。

## 11. 兼容范围与执行上限

### 11.1 已有能力与边界

| 能力 | 当前范围 |
| --- | --- |
| HTML / JSON 声明式规则 | CSS、XPath、JSONPath、模板、正则、规则组合 |
| JavaScript | 独立 QuickJS 上下文，受限网络、存储及网页动作桥 |
| Java / Android 数据兼容 | 部分集合、正则、数值、JSON、编码、内存流、压缩、日期和密码学类；按已注册类与已实现方法执行 |
| 任意 Java 类 / Android 平台能力 | 不支持；`Java.type`、`Packages` 等不能访问任意平台 |
| 任意文件、数据库、进程、直接平台网络 | 不支持；不要使用 Node.js、直接 `fetch`、XHR、WebSocket 或平台对象 |
| 小说 | 通用在线章节正文链路 |
| 音频 | 通用提取、媒体 URL 与请求头；最终格式能力取决于播放器和资源 |
| 漫画、完整网络文件阅读器 | 不属于当前完整适配范围 |
| 光遇 / 书山 / Talebook | 已有特定导入源身份与原生协议适配，不是可在 JSON 中任意声明的新协议插件 |

新网站优先写普通规则。不能仅把源名称改成某个原生适配器名称，就获得其能力；新增原生协议需要 App 代码支持。Talebook 请使用 App 提供的 NAS 添加入口生成对应定义。

### 11.2 当前通用执行预算

以下为代码上限，不是性能目标；特定协议、调试、批测和网页模式还可能有更严格的总时限。

| 项目 | 上限 |
| --- | --- |
| 单次导入 | 1000 个源 |
| 单次搜索 / 发现候选列表 | 最多处理 50 条 |
| 单次目录收集 | 100 页、20000 条章节 |
| 单章分页收集 | 50 页 |
| 单个响应正文 | 4 × 1024 × 1024 字符 |
| 目录 / 正文阶段累计响应 | 16 × 1024 × 1024 字符 |
| 单章最终正文 | 8 × 1024 × 1024 字符 |
| 普通字段 / 简介 | 通常 8192 / 1200 字符；书名等有更小限制 |
| 请求超时 | 3–60 秒，默认 18 秒 |
| 额外请求重试 | 最多 2 次 |
| 单段规则代码与库合计 | 2 × 1024 × 1024 字符 |
| 脚本外部动作重放 | 最多 64 步 |
| `bodyJs` / `webJs` 文本 | 各 256 × 1024 字符 |

达到预算可能停止继续收集、截断或报错，不能把缺少后续结果都当作网站没有更多内容。QuickJS 另有堆、栈、执行时间、待处理任务和输入输出约束，不应通过忙等模拟延时。

## 12. 导入、调试与交付

### 12.1 推荐编写步骤

1. 查看目标网站的实际 HTML 或 JSON，记录搜索、详情、目录、章节四类响应。
2. 明确类型：小说 `0`，音频 `1`，选择稳定的 `bookSourceUrl`。
3. 先配置 `bookList`、`name`、`bookUrl`，用能确定有结果的关键词测试。
4. 打开一本书，配置详情与 `tocUrl`。
5. 配置目录，检查章节顺序、地址唯一性、分页和公开章节。
6. 配置正文或音频；确认不是错误页、登录页或临时占位内容。
7. 补充封面、简介、分类、Header、Cookie、限流等必要字段。
8. 最后配置发现分类、登录面板和高级脚本。

### 12.2 App 内验证

在“书源”的导入入口使用 JSON 内容、远程链接或本地文件导入；远程链接应返回实际 JSON，不是网盘分享页或 HTML 页面。

从书源操作进入“书源调试”，按搜索、详情、目录、正文等阶段定位。需要前置变量的规则先跑完整链路；日志可用于检查请求、提取数量和 `java.log()` 输出，分享日志前检查其中是否包含个人数据。

当前“目录”调试先执行详情提取，因此测试地址应填写**书籍详情 URL**，再由 `ruleBookInfo.tocUrl` 找到目录；“正文”调试填写章节 URL。“完整流程”从搜索首本结果继续详情、目录和章节内容，适合检查上下文传递。

验证清单：

- 搜索：普通关键词能命中，空结果不会被错误识别为书籍。
- 详情：书名、封面、简介正常，目录地址可达。
- 目录：首章、末章、分页边界正确，没有重复和乱序。
- 小说：打开公开章节，切下一章并返回，正文无导航 / 广告混入，阅读位置可恢复。
- 音频：播放公开章节，暂停续播、切章，再验证下载和导出。
- 发现：分类能进入，第二页不重复；听书源选为首页源后能展示内容。
- 登录源：新安装未登录时提示合理，登录后可请求，会话过期时可重新登录。

批量“搜索测试”不能证明正文 / 音频可用。“发现 / 阅读”测试会采样公开章节验证内容，单源测试有结果时也继续检查内容；仍应手动完成一次真正阅读或播放。测试状态用于诊断，不等于整个源的永久可用保证。

### 12.3 分享给别人

交付书源 JSON，同时在 `bookSourceComment` 写明：作者、版本 / 日期、适用站点、小说 / 音频、是否需登录、已验证能力和已知限制。

首次发布推荐 `enabled: true`、`isLocked: false`。发给他人前用无现成会话的环境复查，不要依靠作者本机的 Cookie 才能“测试通过”。

禁用源仍保留定义供已有收藏解析；删除源会删除对应会话和 Cookie。修改源身份或章节 URL 结构前，应考虑已有收藏和进度的关联。

## 13. 常见问题

| 现象 | 优先检查 |
| --- | --- |
| 导入失败 | 是否标准 JSON；名称 / 地址是否为空；规则字符串的双引号、反斜杠是否正确转义 |
| 能导入但不参与搜索 | `enabled` 和搜索四个必要字段是否齐全 |
| 搜索选择到了节点但结果为空 | 单条 `name`、`bookUrl` 是否为空；列表已选中 `a` 时是否误用了子级 `a@href` |
| JSON 字段全为空 | 是否在单条对象上仍写整个响应路径；`init` 后路径是否还多一层 |
| 浏览器正常，App 返回空列表 | 原始响应是否依赖 JS 渲染、登录、请求头或字符集；先看实际响应 |
| URL 出现重复域名或关键词乱码 | 相对地址基准、模板编码、手工编码是否重复 |
| 目录只有一页 | 是否有 `nextTocUrl`；下一页是否解析成同一 URL；是否达到预算 |
| 多章正文连成一章 | `nextContentUrl` 是否错误指向“下一章” |
| 目录顺序反了 | 对单页列表使用 `-`；多页目录还需确认页顺序 |
| 音频提取成功但播不了 | 是否真实媒体 URL；有效期、Header、Cookie、CDN、格式是否匹配 |
| 能播放不能下载 | 媒体地址有效期、下载请求头、资源访问条件是否相同 |
| 发现入口为空 | `enabledExplore` 是否启用；`exploreUrl` 是否为正确字符串；分类是否有 URL |
| 首页找不到小说源 | 首页仅接受已启用音频源，这是产品行为 |
| JS 提示方法 / 类不存在 | 使用了未实现的 Java、Android、Node 或浏览器 API；改用受支持的兼容方法 |
| JS 解析 JSON 失败 | 检查 `src` 是否真是 JSON；`result` 可能已经是对象 |
| 布尔标记不生效 | 不要返回任意提示文本，改为 `true` / `false` 或 `1` / `0` |
| 提示锁定无法覆盖 | 先由用户解锁已安装源，再修改或重导入 |
| 批测通过仍有章节失败 | 批测只覆盖样本，核对付费章节、签名过期、分页及特殊内容响应 |

## 14. 实现依据

本文以项目代码为准，而非通用阅读器文档。下列链接便于随代码更新复核；将本文件单独分享时，不影响前述规则说明和模板阅读。

| 内容 | 项目文件 |
| --- | --- |
| 字段模型、搜索准入 | [LocalRuleSource.ets](../entry/src/main/ets/model/LocalRuleSource.ets) |
| 导入格式、别名、默认值 | [LocalRuleSourceImportParser.ets](../entry/src/main/ets/service/rulesource/LocalRuleSourceImportParser.ets) |
| URL、POST、Header、编码、选项 | [LocalRuleUrlAnalyzer.ets](../entry/src/main/ets/service/rulesource/LocalRuleUrlAnalyzer.ets) |
| 提取、组合、变量、正则 | [LocalRuleStageExtractor.ets](../entry/src/main/ets/service/rulesource/LocalRuleStageExtractor.ets) |
| JSONPath | [LocalRuleJsonPath.ets](../entry/src/main/ets/service/rulesource/LocalRuleJsonPath.ets) |
| 搜索、详情、目录、正文的实际行为 | [LocalRuleDispatcher.ets](../entry/src/main/ets/service/rulesource/LocalRuleDispatcher.ets) |
| JavaScript 上下文 | [LocalRuleScriptRuntime.ets](../entry/src/main/ets/service/rulesource/LocalRuleScriptRuntime.ets)、[LocalRuleScriptCompat.ets](../entry/src/main/ets/service/rulesource/LocalRuleScriptCompat.ets) |
| 发现 / 登录面板 | [LocalRulePanelService.ets](../entry/src/main/ets/service/rulesource/LocalRulePanelService.ets) |
| 首页范围 | [HomeSourceService.ets](../entry/src/main/ets/service/rulesource/HomeSourceService.ets) |
| 限流、声明式会话 | [LocalRuleRequestLimiter.ets](../entry/src/main/ets/service/rulesource/LocalRuleRequestLimiter.ets)、[LocalRuleRequestSession.ets](../entry/src/main/ets/service/rulesource/LocalRuleRequestSession.ets) |
| 通用预算 | [LocalRuleRuntimeTypes.ets](../entry/src/main/ets/service/rulesource/LocalRuleRuntimeTypes.ets) |
| 兼容行为示例 | [LocalRuleRuntime.test.ets](../entry/src/test/LocalRuleRuntime.test.ets)、[LocalRuleCompatibility.test.ets](../entry/src/test/LocalRuleCompatibility.test.ets) |

验证范围：本文按当前实现及已有测试用例核对字段和语法，模板为占位接口示例，不代表已完成真实站点或设备联调。
