# HarmonyOS 项目配置参考

本文档提供 HarmonyOS 项目中与废弃接口检查相关的配置示例。

## code-linter.json5 配置

在项目根目录配置代码检查规则：

```json5
{
  "files": [
    "**/*.ets"
  ],
  "ignore": [
    "**/oh_modules/**",
    "**/build/**"
  ],
  "ruleSet": [
    "plugin:@typescript-eslint/recommended"
  ],
  "rules": {
    "no-unused-vars": "warn",
    "@typescript-eslint/no-explicit-any": "warn"
  }
}
```

## build-profile.json5 配置

```json5
{
  "app": {
    "products": [
      {
        "name": "default",
        "signingConfig": "default",
        "compileSdkVersion": "5.0.0(12)",
        "compatibleSdkVersion": "5.0.0(12)",
        "runtimeOS": "HarmonyOS"
      }
    ]
  }
}
```

## 配置说明

### compileSdkVersion

- 指定编译时使用的 SDK 版本
- 建议使用最新稳定版本
- 格式：`"主版本.次版本.修订版(API级别)"`

### compatibleSdkVersion

- 指定应用最低兼容的 SDK 版本
- 影响废弃 API 的可用性
- 迁移时需注意此版本要求

### code-linter 规则

- `no-unused-vars`: 检测未使用的变量
- `@typescript-eslint/no-explicit-any`: 禁止使用 any 类型
- 可根据项目需求自定义规则
