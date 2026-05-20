# 自定义节点

## 概述

自定义节点是ArkUI通过接口提供的底层实体节点，具备部分基础能力，能够与系统组件混合显示。自定义节点的挂载与显示依赖于自定义占位节点。

### 基本概念

- **系统组件**：组件是UI的必要元素，形成了在界面中的样式，由ArkUI直接提供的称为系统组件。

- **实体节点**：系统内部维护了一棵组件树，用于处理组件的属性设置、生命周期等逻辑。该组件树上的节点即为实体节点。

- **自定义节点**：使用ArkUI提供的接口，以命令式创建的节点。包括FrameNode、RenderNode、BuilderNode等。

### 自定义节点类型

| 类型 | 说明 | 适用场景 |
|------|------|----------|
| FrameNode | 自定义组件节点 | 需要完整的自定义能力，包括测量、布局、绘制 |
| RenderNode | 自定义渲染节点 | 仅依赖系统渲染与动画能力的自定义场景 |
| BuilderNode | 自定义声明式节点 | 基于系统能力创建特定组件树进行混合显示 |

---

## NodeController

NodeController用于实现自定义节点的创建、显示、更新等操作的管理，并负责将自定义节点挂载到NodeContainer上。

### 导入模块

```typescript
import { NodeController } from '@kit.ArkUI';
```

### 基本使用

```typescript
import { NodeController, BuilderNode, FrameNode, UIContext } from '@kit.ArkUI';

class Params {
  text: string = "this is a text"
}

@Builder
function buttonBuilder(params: Params) {
  Column() {
    Button(params.text)
      .fontSize(12)
      .borderRadius(8)
      .borderWidth(2)
      .backgroundColor(Color.Orange)
  }
}

class MyNodeController extends NodeController {
  private buttonNode: BuilderNode<[Params]> | null = null;
  private wrapBuilder: WrappedBuilder<[Params]> = wrapBuilder(buttonBuilder);

  makeNode(uiContext: UIContext): FrameNode {
    if (this.buttonNode == null) {
      this.buttonNode = new BuilderNode(uiContext);
      this.buttonNode.build(this.wrapBuilder, { text: "This is a Button" })
    }
    return this.buttonNode!.getFrameNode()!;
  }

  aboutToResize(size: Size) {
    console.info("aboutToResize width : " + size.width + " height : " + size.height)
  }

  aboutToAppear() {
    console.info("aboutToAppear")
  }

  aboutToDisappear() {
    console.info("aboutToDisappear");
  }
}

@Entry
@Component
struct Index {
  private myNodeController: MyNodeController = new MyNodeController();

  build() {
    Column() {
      NodeContainer(this.myNodeController)
    }
    .padding({ left: 35, right: 35, top: 35 })
    .width("100%")
    .height("100%")
  }
}
```

### NodeController 方法

| 方法 | 说明 |
|------|------|
| makeNode | 抽象方法，创建并返回FrameNode节点 |
| aboutToAppear | NodeContainer挂载显示后触发 |
| aboutToDisappear | NodeContainer销毁时触发 |
| aboutToResize | NodeContainer布局时触发 |
| onTouchEvent | NodeContainer收到Touch事件时触发 |
| rebuild | 通知NodeContainer重新回调makeNode方法 |
| onAttach | NodeContainer挂载至主节点树时触发 |
| onDetach | NodeContainer从主节点树卸载时触发 |
| onWillBind | 与NodeContainer即将绑定前触发 |
| onWillUnbind | 与NodeContainer即将解绑前触发 |
| onBind | 与NodeContainer绑定后触发 |
| onUnbind | 与NodeContainer解绑后触发 |

### 使用约束

- 一个NodeController只允许与一个NodeContainer进行绑定
- 需要开发者自行保证调用rebuild接口时UI上下文有效

---

## FrameNode

FrameNode表示组件的实体节点，分为两大类能力：完全自定义节点的能力以及系统组件节点代理的能力。

### 导入模块

```typescript
import { FrameNode, LayoutConstraint, ExpandMode, typeNode, NodeAdapter } from "@kit.ArkUI";
```

### FrameNode类型

| 类型 | 说明 |
|------|------|
| 完全自定义节点 | 通过FrameNode构造函数创建，提供完整的自定义能力 |
| 系统组件代理节点 | 通过查询接口返回的FrameNode，提供系统组件的代理能力 |

### 创建FrameNode

```typescript
import { NodeController, FrameNode, UIContext } from '@kit.ArkUI';

class MyNodeController extends NodeController {
  private rootNode: FrameNode | null = null;

  makeNode(uiContext: UIContext): FrameNode | null {
    this.rootNode = new FrameNode(uiContext);

    const renderNode = this.rootNode.getRenderNode();
    if (renderNode !== null) {
      renderNode.size = { width: 100, height: 100 };
      renderNode.backgroundColor = 0XFFFF0000;
    }

    return this.rootNode;
  }
}
```

### 节点操作

#### 添加子节点

```typescript
appendChild(node: FrameNode): void
```

在FrameNode最后一个子节点后添加新的子节点。

#### 插入子节点

```typescript
insertChildAfter(child: FrameNode, sibling: FrameNode | null): void
```

在FrameNode指定子节点之后添加新的子节点。

#### 删除子节点

```typescript
removeChild(node: FrameNode): void
```

从FrameNode中删除指定的子节点。

#### 清除所有子节点

```typescript
clearChildren(): void
```

清除当前FrameNode的所有子节点。

#### 获取子节点

```typescript
getChild(index: number): FrameNode | null
```

获取当前节点指定位置的子节点。

#### 获取父节点

```typescript
getParent(): FrameNode | null
```

获取当前节点的父节点。

#### 获取RenderNode

```typescript
getRenderNode(): RenderNode | null
```

获取FrameNode中持有的RenderNode。

### 节点操作示例

```typescript
import { NodeController, FrameNode, UIContext } from '@kit.ArkUI';

class MyNodeController extends NodeController {
  private rootNode: FrameNode | null = null;

  makeNode(uiContext: UIContext): FrameNode | null {
    this.rootNode = new FrameNode(uiContext);

    // 创建子节点
    const child1 = new FrameNode(uiContext);
    const child2 = new FrameNode(uiContext);

    // 添加子节点
    this.rootNode.appendChild(child1);
    this.rootNode.appendChild(child2);

    // 获取第一个子节点
    const firstChild = this.rootNode.getChild(0);

    return this.rootNode;
  }
}
```

### isModifiable

```typescript
isModifiable(): boolean
```

判断当前节点是否可修改。返回true表示当前节点可修改，false表示当前节点不可修改。

### LayoutConstraint

描述组件的布局约束。

| 名称 | 类型 | 说明 |
|------|------|------|
| maxSize | Size | 最大尺寸 |
| minSize | Size | 最小尺寸 |
| percentReference | Size | 子节点计算百分比时的尺寸基准 |

---

## RenderNode

RenderNode作为轻量级的渲染节点，仅提供了设置渲染相关属性、自定义绘制内容以及节点操作的能力。

### 导入模块

```typescript
import { RenderNode } from '@kit.ArkUI';
```

### 创建RenderNode

```typescript
import { RenderNode, FrameNode, NodeController, UIContext } from '@kit.ArkUI';

const renderNode = new RenderNode();
renderNode.frame = { x: 0, y: 0, width: 100, height: 100 };
renderNode.backgroundColor = 0xffff0000;

class MyNodeController extends NodeController {
  private rootNode: FrameNode | null = null;

  makeNode(uiContext: UIContext): FrameNode | null {
    this.rootNode = new FrameNode(uiContext);

    const rootRenderNode = this.rootNode.getRenderNode();
    if (rootRenderNode !== null) {
      rootRenderNode.appendChild(renderNode);
    }

    return this.rootNode;
  }
}
```

### 节点操作

#### 添加子节点

```typescript
appendChild(node: RenderNode): void
```

#### 插入子节点

```typescript
insertChildAfter(child: RenderNode, sibling: RenderNode | null): void
```

#### 删除子节点

```typescript
removeChild(node: RenderNode): void
```

#### 清除所有子节点

```typescript
clearChildren(): void
```

#### 获取子节点

```typescript
getChild(index: number): RenderNode | null
```

### 设置属性

```typescript
const renderNode = new RenderNode();
renderNode.frame = { x: 0, y: 0, width: 200, height: 200 };
renderNode.position = { x: 10, y: 10 };
renderNode.size = { width: 100, height: 100 };
renderNode.backgroundColor = 0xffff0000;
renderNode.opacity = 0.8;
renderNode.scale = { x: 1.5, y: 1.5 };
renderNode.rotation = 45;
renderNode.translation = { x: 10, y: 10 };
```

### RenderNode示例

```typescript
import { RenderNode, FrameNode, NodeController, UIContext } from '@kit.ArkUI';

const renderNode = new RenderNode();
renderNode.frame = { x: 0, y: 0, width: 200, height: 350 };
renderNode.backgroundColor = 0xffff0000;

for (let i = 0; i < 5; i++) {
  const node = new RenderNode();
  node.frame = { x: 10, y: 10 + 60 * i, width: 50, height: 50 };
  node.backgroundColor = 0xff00ff00;
  renderNode.appendChild(node);
}

class MyNodeController extends NodeController {
  private rootNode: FrameNode | null = null;

  makeNode(uiContext: UIContext): FrameNode | null {
    this.rootNode = new FrameNode(uiContext);

    const rootRenderNode = this.rootNode.getRenderNode();
    if (rootRenderNode !== null) {
      rootRenderNode.appendChild(renderNode);
    }

    return this.rootNode;
  }
}
```

---

## BuilderNode

BuilderNode通过无状态的UI方法@Builder生成组件树，组件树内的节点为系统组件。

### 导入模块

```typescript
import { BuilderNode, RenderOptions, NodeRenderType } from "@kit.ArkUI";
```

### 创建BuilderNode

```typescript
import { NodeController, BuilderNode, FrameNode, UIContext } from "@kit.ArkUI";

class Params {
  text: string = "";
  constructor(text: string) {
    this.text = text;
  }
}

@Builder
function buildText(params: Params) {
  Column() {
    Text(params.text)
      .fontSize(50)
      .fontWeight(FontWeight.Bold)
      .margin({ bottom: 36 })
  }
}

class TextNodeController extends NodeController {
  private textNode: BuilderNode<[Params]> | null = null;

  makeNode(uiContext: UIContext): FrameNode | null {
    this.textNode = new BuilderNode(uiContext);
    this.textNode.build(wrapBuilder<[Params]>(buildText), new Params("Hello"));
    return this.textNode.getFrameNode();
  }
}
```

### BuilderNode 方法

| 方法 | 说明 |
|------|------|
| constructor | 构造函数，需要传入UIContext |
| build | 依照传入的对象创建组件树 |
| getFrameNode | 获取BuilderNode中的FrameNode |
| update | 更新BuilderNode的参数 |
| dispose | 解绑前后端对象 |

### RenderOptions

创建BuilderNode时的可选参数。

| 名称 | 类型 | 说明 |
|------|------|------|
| selfIdealSize | Size | 节点的理想大小 |
| type | NodeRenderType | 节点的渲染类型 |
| surfaceId | string | 纹理接收方的surfaceId |

### BuildOptions

build的可选参数。

| 名称 | 类型 | 说明 |
|------|------|------|
| nestingBuilderSupported | boolean | 是否支持Builder嵌套Builder |
| localStorage | LocalStorage | 给当前BuilderNode设置LocalStorage |
| enableProvideConsumeCrossing | boolean | @Consume是否与外部@Provide互通 |

### NodeRenderType

节点渲染类型枚举。

| 值 | 说明 |
|------|------|
| RENDER_TYPE_DISPLAY | 表示该节点将被显示到屏幕上 |
| RENDER_TYPE_TEXTURE | 表示该节点将被导出为纹理 |

---

## NodeContainer

NodeContainer是用于挂载NodeController的系统组件。

### 基本使用

```typescript
@Entry
@Component
struct Index {
  private myNodeController: MyNodeController = new MyNodeController();

  build() {
    Column() {
      NodeContainer(this.myNodeController)
    }
    .width("100%")
    .height("100%")
  }
}
```

---

## typeNode

typeNode提供了创建特定类型节点的方法。

### 创建Text节点

```typescript
FrameNode.createNode('Text')
```

### 创建Column节点

```typescript
FrameNode.createNode('Column')
```

### 创建Row节点

```typescript
FrameNode.createNode('Row')
```

---

## 跨语言属性设置

ArkUI支持在前端使用ArkTS语言创建命令式节点，也可以在Native侧使用C语言创建命令式节点，并且可以混合使用两类节点构建页面。

### CrossLanguageOptions

配置FrameNode的跨语言访问权限。

| 名称 | 类型 | 说明 |
|------|------|------|
| attributeSetting | boolean | 是否支持跨ArkTS语言进行属性设置 |

---

## 注意事项

1. **NavPathStack对象和Navigation需要一一对应，不可复用**

2. **FrameNode节点暂不支持拖拽**

3. **不建议对BuilderNode中的RenderNode进行修改操作**

4. **BuilderNode仅可作为叶子节点使用**

5. **当前不支持在预览器中使用自定义节点**

---

## 相关链接

- [自定义能力](custom-capabilities.md)
- [UIContext](../10-uicontext/uicontext.md)