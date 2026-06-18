# run-book-source

验证 Legado 书源兼容性的测试 skill。

## 用途

测试 ListenBook 规则引擎对 Legado 书源格式的支持程度，验证搜索、详情、目录、正文等完整链路。

## 使用场景

- 验证新书源 JSON 是否可用
- 测试规则引擎功能完整性
- 调试书源规则解析问题

## 参数

- `source_name`: 书源名称（搬山人小说网 / 笔趣📖 / 水山听书）
- `test_type`: 测试类型（search / detail / toc / content / full）

## 工作流程

1. 读取 `小说json.txt` 中的目标书源配置
2. 根据 test_type 执行对应测试：
   - search: 搜索关键词 "斗破苍穹"，验证返回结果
   - detail: 获取书籍详情（书名、作者、简介、封面）
   - toc: 获取章节列表
   - content: 获取章节正文
   - full: 完整链路测试（搜索→详情→目录→正文）
3. 输出测试结果和规则引擎日志

## 运行器（Node，本目录）

实际验证由本目录的 Node 运行器 `run.mjs` 完成（忠实复刻 legado 语义：CSS / JSONPath / `@js`+完整 java 桥 / `data:` 契约 / GBK-POST / XPath / AES / 同步 HTTP）。

```bash
# 一次性装依赖（仅首次）
npm --prefix .claude/skills/run-book-source install

# 用法: node run.mjs <书源名/关键字|文件> <action> [arg]
# action: search | detail <bookUrl> | toc <tocUrl> | content <chapterUrl> | full [关键词] | book <bookUrl>
node .claude/skills/run-book-source/run.mjs 猫眼 full 深空彼岸
node .claude/skills/run-book-source/run.mjs 福书 book https://www.fushucun.com/2021/75280.html
node .claude/skills/run-book-source/run.mjs ./我的源.json search 斗破苍穹
```

书源自动从项目根 `*.txt`（每个一个源）与 `1780478078.json` 等集合加载，按名称（支持部分匹配）选取；正文落到运行目录的 `./out/`。

## 实现状态（运行器）

- [x] Stage 1: CSS 选择器（逗号 OR、多类名、范围索引、`.0/.1`、`@text/@href/@src/@html/@attr`）
- [x] Stage 2: `{{}}` 模板、`##regex##repl`、`{$.x}` JSONPath 内嵌
- [x] Stage 3: POST、charset=gbk（请求体编码+响应解码）、java 桥（ajax/ajaxAll→StrResponse、base64/hex、md5、encodeURI、timeFormatUTC、log/toast）、`source.getVariable/setVariable` 持久化
- [x] Stage 4: `data:;base64,B,{type}`→hex 契约、AES `createSymmetricCrypto`、XPath `//select option`、`@js` 列表/正文、Jsoup 垫片、4011 限频跳域

## 已验证（实站拿到正文）

- ✅ **福书网[分页]** fushucun.com：GBK+POST 搜索 / XPath option 分页目录 / `@js`+正则+Jsoup 正文
- ✅ **猫眼看书(优++)**：加密 API（动态域名+JWT、`data:`hex、`md5(aesKey)`头、AES/CBC 解章节 path），目录 1455 章
- ⛔ **笔趣📖** biqun.cc：纯 CSS，引擎支持，**站点 2026-06 宕机(522)** 暂无法实测

## 注意事项

- 需要网络连接访问书源网站
- App 内对照：复杂 API 源（如猫眼）走 `service/builtin/` 原生源（如 `Maoyan.ets`）；HTML 规则源走 `service/rule/` 引擎
- 旧版 `localhost:3737` JS 代理已不需要（`@js` 走 `run.mjs` 内的 vm + java 桥）
