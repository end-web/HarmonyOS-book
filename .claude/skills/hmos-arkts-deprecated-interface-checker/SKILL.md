---
name: hmos-arkts-deprecated-interface-checker
description: "检查 HarmonyOS 项目中的废弃 SDK 接口并提供修复建议。当需要清理废弃 API、升级 API 版本、优化代码质量或进行静态语法检查时使用。提供详细的迁移方案、修复优先级分类和代码示例。"
---
# HarmonyOS 废弃接口检查与修复

## 技能概述

本技能专门用于检查 HarmonyOS 项目中使用的废弃（Deprecated）SDK 接口，并提供详细的修复建议和迁移方案。帮助开发者保持代码的现代性和可维护性。

## 使用场景

- ✅ 项目升级 HarmonyOS API 版本前
- ✅ 清理技术债务，移除废弃 API 调用
- ✅ 准备发布新版本，提升代码质量
- ✅ 代码审查时发现废弃接口警告
- ✅ 迁移到新 HarmonyOS 版本（如 API 10/11/12）

## 工作流程

### 0. 检查MCP工具依赖

**⚠️ 重要提示：本技能依赖MCP工具**

在执行任何检查操作之前，必须先检查MCP工具是否可用：

**依赖的MCP工具**：

- `mcp_codegenie-mcp_check_ets_files` - ETS文件静态语法检查
- `mcp_codegenie-mcp_harmonyos_knowledge_search` - HarmonyOS知识搜索（可选）

**检查方法**：

```
尝试调用 mcp_codegenie-mcp_check_ets_files
如果工具不可用，会收到错误提示
```

**如果MCP工具未安装**：

```
❌ MCP工具未安装或不可用

本技能需要依赖 CodeGenie MCP Server 工具才能正常工作。

📦 安装方式：

在 MCP 配置文件中添加以下配置：

{
  "mcpServers": {
    "codegenie-mcp": {
      "command": "npx",
      "args": [
        "-y",
        "@deveco-codegenie/mcp@beta",
        "--registry=https://registry.npmjs.org"
      ],
      "env": {
        "PROJECT_PATH": "${workspaceFolder}",
        "DEVECO_PATH": "path to deveco studio"
      }
    }
  }
}

📚 详细文档：
- GitHub: https://github.com/open-deveco/deveco-toolbox
- 飞书指导文档: https://my.feishu.cn/wiki/open-deveco/deveco-toolbox

💡 安装完成后，请重新使用本技能。
```

**验证成功后继续执行后续步骤**。

---

### 1. 项目分析

首先分析项目结构和配置：

```bash
# 检查项目类型（ArkTS/ETS）
# 查看 build-profile.json5 配置
# 确定 compileSdkVersion 和 compatibleSdkVersion
# 查看 module.json5 中的配置
```

### 2. 执行静态语法检查

使用 MCP 工具进行 ArkTS 静态语法检查：

**步骤**：

1. **获取项目 ETS 源文件列表**

   - 使用 Glob 工具搜索 `**/*.ets` 文件
   - 排除 `oh_modules` 和 `build` 目录
2. **调用静态检查工具**

   ```
   mcp_codegenie-mcp_check_ets_files
   参数: files - ETS 文件路径列表
   ```
3. **分析检查结果**

   - 解析返回的诊断信息
   - 识别废弃接口（code: 6387, deprecatedSymbol）
   - 统计警告和错误数量

### 3. 生成检查报告

报告包含以下信息：

**报告格式示例**：

```
📊 HarmonyOS 废弃接口检查报告
━━━━━━━━━━━━━━━━━━━━━━━━━━━━

🔴 严重：X 个错误
🟡 警告：X 个警告
ℹ️ 信息：X 个废弃接口提示

━━━━━━━━━━━━━━━━━━━━━━━━━━━━

【信息】使用已废弃的 API
━━━━━━━━━━━━━━━━━━━━━━━━━━━━

📍 文件：entry/src/main/ets/pages/Index.ets:8:12
⚠️  问题：使用了 @Deprecated 的 px2vp 方法
📚 废弃原因：该签名已被标记为废弃
💡 替代方案：使用新的 API 接口
🔗 官方文档：https://developer.huawei.com/consumer/cn/doc/harmonyos-references/
📋 迁移示例：
   // 旧代码:
   px2vp(100)
   
   // 新代码:
   // 使用推荐的替代方法

━━━━━━━━━━━━━━━━━━━━━━━━━━━━

【警告】未使用的变量
━━━━━━━━━━━━━━━━━━━━━━━━━━━━

📍 文件：entry/src/main/ets/pages/Index.ets:8:8
⚠️  问题：变量 'a' 已声明但从未被使用
💡 建议：删除未使用的变量或使用下划线前缀命名
```

### 4. 提供修复方案

针对每个问题提供：

#### 修复优先级分类

- **P0 - 必须修复**：影响应用稳定性或兼容性的错误
- **P1 - 强烈建议**：废弃 API 警告，有明显替代方案
- **P2 - 可选优化**：未使用变量等代码质量问题

#### 迁移指导

每个修复建议包含：

- ✅ 具体的代码替换示例
- ✅ 兼容性说明（最低支持 API 级别）
- ✅ 性能影响评估
- ✅ 测试建议

### 5. 辅助修复（可选）

提供自动化修复指导：

- 使用 DevEco Studio 的快速修复功能（Alt+Enter）
- 手动应用修复建议
- 批量替换废弃 API

## 检查清单

### Critical（必须修复）

- [ ] **验证MCP工具可用性（必需）**
- [ ] 所有废弃 API 已识别并记录
- [ ] P0 级别错误已全部修复
- [ ] 影响应用稳定性的问题已解决
- [ ] 兼容性问题已处理（最低 API 版本）

### Warning（强烈建议）

- [ ] P1 级别废弃 API 已迁移
- [ ] 所有替代方案已验证可用
- [ ] 迁移后功能测试通过
- [ ] 性能无明显下降

### Info（建议优化）

- [ ] P2 级别代码质量问题已处理
- [ ] 未使用的变量/导入已清理
- [ ] 代码风格符合规范
- [ ] 文档已更新

## 决策树

```
开始检查流程
│
├─ MCP工具可用？
│   ├─ 否 → 提示安装MCP工具 → 终止
│   └─ 是 → 继续
│
├─ 发现废弃 API 警告
│   │
│   ├─ 是否有直接替代 API？
│   │   ├─ 是 → 检查最低支持版本
│   │   │       ├─ 满足要求 → 使用替代 API（P1）
│   │   │       └─ 不满足 → 保持现状，添加注释说明（P2）
│   │   │
│   │   └─ 否 → 需要重构代码逻辑
│   │           ├─ 影响核心功能 → 立即处理（P0）
│   │           └─ 非核心功能 → 计划迁移（P1）
│   │
│   └─ 问题严重程度判定
│       ├─ 导致编译失败 → Critical（P0）
│       │   └─ 行动：必须立即修复
│       ├─ 运行时可能出错 → Warning（P1）
│       │   └─ 行动：强烈建议修复
│       └─ 仅警告提示 → Info（P2）
│           └─ 行动：可选优化
```

## 常见废弃 API 及替代方案

详细的废弃 API 列表、迁移示例和错误码参考请查看 [废弃 API 参考](references/deprecated-api-reference.md)。

### 快速参考

| 废弃 API                 | 替代方案          | 说明         |
| ------------------------ | ----------------- | ------------ |
| `px2vp(value: number)` | 使用新的签名      | 参数类型变更 |
| `vp2px(value: number)` | 使用新的签名      | 参数类型变更 |
| `@ohos.fileio`         | `@ohos.file.fs` | 模块迁移     |

## 配置建议

详细的配置示例和说明请查看 [配置参考](references/configuration-reference.md)。

### 快速配置

**code-linter.json5**:

```json5
{
  "files": ["**/*.ets"],
  "ignore": ["**/oh_modules/**", "**/build/**"],
  "rules": {
    "no-unused-vars": "warn"
  }
}
```

## 最佳实践

### ✅ 推荐做法

1. **定期检查**：将废弃接口检查纳入开发流程
2. **渐进式迁移**：优先修复 P0 级别的问题
3. **充分测试**：每次迁移后进行全面测试
4. **文档记录**：记录迁移决策和注意事项
5. **关注版本**：及时关注 HarmonyOS 版本更新日志

### ❌ 避免做法

1. 不要忽略废弃接口警告
2. 不要在关键业务逻辑中使用废弃 API
3. 不要在没有测试的情况下批量替换
4. 不要忽视兼容性要求

## 执行步骤

当用户需要检查废弃接口时：

1. **确认项目信息**

   - 当前 HarmonyOS API 版本
   - 最低支持的 API 版本
   - 项目规模（文件数量）
2. **获取源文件列表**

   - 搜索项目中的 ETS 文件
   - 排除第三方依赖目录
3. **运行静态检查**

   ```
   mcp_codegenie-mcp_check_ets_files(files: [...])
   ```
4. **分析报告**

   - 统计问题数量
   - 按严重程度分类
   - 识别废弃接口
5. **制定迁移计划**

   - 确定修复优先级
   - 评估工作量
   - 提供修复建议
6. **辅助实施**

   - 提供代码示例
   - 解答迁移问题
   - 验证修复结果

## 工具命令参考

### MCP 工具

| 工具名称                                         | 用途                    |
| ------------------------------------------------ | ----------------------- |
| `mcp_codegenie-mcp_check_ets_files`            | ETS 文件静态语法检查    |
| `mcp_codegenie-mcp_build_project`              | 构建项目                |
| `mcp_codegenie-mcp_harmonyos_knowledge_search` | 搜索 HarmonyOS 开发文档 |

### 常见错误码

| 错误码 | 类型        | 说明              |
| ------ | ----------- | ----------------- |
| 6133   | Warning     | 未使用的变量/符号 |
| 6387   | Information | 使用了废弃的 API  |

详细的诊断信息格式和错误码说明请查看 [废弃 API 参考](references/deprecated-api-reference.md)。

## 输出示例

执行检查后，将提供：

1. 📊 **统计摘要**：各类问题数量统计
2. 📋 **问题清单**：按文件和优先级排序
3. 🔧 **修复建议**：每个问题的具体修复方案
4. 📝 **代码示例**：修复前后的代码对比

## 注意事项

- ⚠️ **本技能依赖 CodeGenie MCP Server 工具，使用前请确保已安装并配置 MCP 服务**
  - 安装方式：https://github.com/open-deveco/deveco-toolbox
- ⚠️ 某些废弃 API 可能没有直接替代品，需要重构代码逻辑
- ⚠️ 迁移时注意最低支持版本要求
- ⚠️ 建议在 DevEco Studio 中打开项目以获得更好的 IDE 支持

## 相关资源

### MCP工具

- [CodeGenie MCP Server 安装指南](https://github.com/open-deveco/deveco-toolbox)
- [飞书指导文档](https://my.feishu.cn/wiki/open-deveco/deveco-toolbox)

### HarmonyOS开发

- [HarmonyOS API 参考](https://developer.huawei.com/consumer/cn/doc/harmonyos-references/)
- [HarmonyOS 开发指南](https://developer.huawei.com/consumer/cn/doc/harmonyos-guides/)
- [ArkTS 语法规范](https://developer.huawei.com/consumer/cn/doc/harmonyos-guides/arkts-get-started)
- [HarmonyOS 版本变更说明](https://developer.huawei.com/consumer/cn/doc/harmonyos-releases/)
