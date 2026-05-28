# fetch-yiove-book-sources

从 yiove 书源仓库批量获取听书书源的完整 JSON 数据，用于测试和完善 ListenBook 的规则引擎。

## 触发条件

当用户需要：
- 获取 yiove 书源数据
- 测试规则引擎兼容性
- 分析书源 JSON 结构
- 批量导入书源

## 功能

1. 从 `https://shuyuan-api.yiove.com` 获取听书书源列表
2. 批量拉取每个书源的完整 JSON（包含 `origin_json` 字段）
3. 过滤有效书源（`is_valid: true`）
4. 保存到本地 JSON 文件供后续使用
5. 生成书源统计报告

## 输出

- `book_sources_all.json`: 所有书源的完整数据
- `book_sources_valid.json`: 仅有效书源
- `book_sources_report.txt`: 统计报告（总数、有效数、规则类型分布等）

## 使用示例

```
/fetch-yiove-book-sources
/fetch-yiove-book-sources --max 50
/fetch-yiove-book-sources --valid-only
```
