# ohos_quickjs

QuickJS 引擎的 ArkTS/JS 绑定封装，用于在 HarmonyOS (鸿蒙) 应用中嵌入和执行 JavaScript。

## 安装

```shell
ohpm i @devzeng/quickjs
```

OpenHarmony ohpm 环境配置等更多内容，请参考[如何安装 OpenHarmony ohpm 包](https://ohpm.openharmony.cn/#/cn/help/downloadandinstall)

## 使用

### 基本用法

```typescript
import { JSContext, JSValue } from '@devzeng/quickjs';

// 创建执行上下文
const context = new JSContext();

// 执行脚本
const result = context.evaluateScript("'Hello World'");
console.log(result.toString()); // 'Hello World'

// 创建值并进行类型检查
const num = JSValue.valueWithNumber(42, context);
console.log(num.isNumber); // true

// 对象操作
const obj = JSValue.valueWithNewObject(context);
obj.setValue(JSValue.valueWithString('test', context), 'name');
console.log(obj.getProperty('name').toString()); // 'test'

// 函数调用
const addFn = context.evaluateScript('(function(a, b) { return a + b; })');
const ret = addFn.callWithArguments([
  JSValue.valueWithNumber(10, context),
  JSValue.valueWithNumber(20, context)
]);
console.log(ret.toString()); // '30'

// 释放资源
context.release();
```