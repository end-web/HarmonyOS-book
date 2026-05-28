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

## 实现状态

- [x] Stage 1: CSS 选择器增强（逗号 OR、多类名、范围索引）+ DOM shim
- [x] Stage 2: {{@@...}} CSS 内嵌、text.关键字@href、##regex##、.0/.1 索引
- [ ] Stage 3: POST 请求、java 桥（connect/ajax/log）、cookie、source.key、loginCheckJs
- [ ] Stage 4: bookSourceType=1 音频、sourceRegex、checkKeyWord、Jsoup 桥

## 示例

```bash
# 测试搬山人书源的搜索功能
/run-book-source source_name="搬山人小说网" test_type="search"

# 完整链路测试笔趣📖
/run-book-source source_name="笔趣📖" test_type="full"
```

## 注意事项

- 需要网络连接访问书源网站
- 部分书源可能需要 JS 代理服务（localhost:3737）
- Stage 3-4 功能尚未完全实现，复杂书源可能失败
