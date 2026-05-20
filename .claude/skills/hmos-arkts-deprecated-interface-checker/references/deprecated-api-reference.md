# HarmonyOS 废弃 API 参考

本文档提供 HarmonyOS 常见废弃 API 的详细替代方案和迁移指导。

## 单位转换相关

| 废弃 API | 替代方案 | 说明 | 最低 API 版本 |
|---------|---------|------|-------------|
| `px2vp(value: number)` | 使用新的签名 | 参数类型变更 | API 9+ |
| `vp2px(value: number)` | 使用新的签名 | 参数类型变更 | API 9+ |

## UI 组件相关

| 废弃 API | 替代方案 | 说明 | 最低 API 版本 |
|---------|---------|------|-------------|
| 旧版 `@Component` 装饰器 | 新版装饰器 | API 升级 | API 9+ |
| 旧版状态管理 | `@State`、`@Prop` 等 | 状态管理升级 | API 9+ |

## 网络请求相关

| 废弃 API | 替代方案 | 说明 | 最低 API 版本 |
|---------|---------|------|-------------|
| `@ohos.net.http` 旧接口 | 新版 HTTP 接口 | API 重构 | API 9+ |

## 文件操作相关

| 废弃 API | 替代方案 | 说明 | 最低 API 版本 |
|---------|---------|------|-------------|
| `@ohos.fileio` | `@ohos.file.fs` | 模块迁移 | API 9+ |

## 迁移示例

### 单位转换迁移

```typescript
// 旧代码（已废弃）
const vpValue = px2vp(100);

// 新代码（推荐）
import { px2vp } from '@kit.ArkUI';
const vpValue = px2vp(100);
```

### 文件操作迁移

```typescript
// 旧代码（已废弃）
import fileio from '@ohos.fileio';
const file = fileio.openSync(path, 0o102);

// 新代码（推荐）
import { fileIo } from '@kit.CoreFileKit';
const file = fileIo.openSync(path, fileIo.OpenMode.READ_ONLY);
```

## 诊断错误码参考

| 错误码 | 类型 | 说明 | 处理建议 |
|-------|------|------|---------|
| 6133 | Warning | 未使用的变量/符号 | 删除未使用的变量 |
| 6387 | Information | 使用了废弃的 API | 迁移到新 API |
| 其他 | Error/Warning | 语法或类型错误 | 根据具体错误修复 |

## 诊断结果格式

```json
{
  "range": {
    "start": { "line": 7, "character": 12 },
    "end": { "line": 7, "character": 17 }
  },
  "severity": "Information",
  "message": "The signature '(value: number): number' of 'px2vp' is deprecated.",
  "code": 6387,
  "data": "depreciatedSymbol"
}
```

## 相关资源

- [HarmonyOS API 参考](https://developer.huawei.com/consumer/cn/doc/harmonyos-references/)
- [HarmonyOS 开发指南](https://developer.huawei.com/consumer/cn/doc/harmonyos-guides/)
- [ArkTS 语法规范](https://developer.huawei.com/consumer/cn/doc/harmonyos-guides/arkts-get-started)
- [HarmonyOS 版本变更说明](https://developer.huawei.com/consumer/cn/doc/harmonyos-releases/)
