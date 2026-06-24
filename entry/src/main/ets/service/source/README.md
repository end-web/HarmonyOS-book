# Source Engine

这里放项目原生的声明式书源规则。

当前内置规则源：

- `Api69TextSource.ets`：69 书吧 APP API 文本源。

## 接入方式

规则源在 `SourceRegistry.ets` 中注册：

```ts
this.register(Api69TextSource);
```

注册后会由 `BuiltInSourceRegistry` 转成普通 `BookSource`，源地址格式为：

```text
source://api69_text
```

## 规则能力

- JSONPath 提取 JSON 字段。
- CSS 选择器提取 HTML 字段。
- POST/GET 请求。
- 模板变量：`{{key}}`、`{{page}}`、`{{bookId}}`、`{{tocUrl}}`、`{{aid}}`、`{{cid}}`。
- `{{timestamp}}` 和 `{{token}}` 由 `SourceEngine` 自动生成。

69 API 的 token 生成逻辑：

```text
timestamp = 当前秒级时间戳
token = md5("chuanshuo_09_03" + timestamp)
```
