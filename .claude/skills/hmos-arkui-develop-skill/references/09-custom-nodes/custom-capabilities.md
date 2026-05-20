# 自定义能力

## 概述

ArkUI提供了多种自定义能力，包括自定义组合、@Builder复用、属性扩展、样式扩展等，帮助开发者创建可复用、可维护的UI组件。

---

## 自定义组合

通过组合现有组件创建新组件，是最基本的自定义方式。

### 基本使用

```typescript
@Component
export struct CustomButton {
  @Prop text: string = '';
  onClick?: () => void;

  build() {
    Button(this.text)
      .width(100)
      .height(40)
      .borderRadius(20)
      .onClick(() => this.onClick?.())
  }
}
```

### 带状态的自定义组件

```typescript
@Component
export struct Counter {
  @State count: number = 0;

  build() {
    Row() {
      Button('-')
        .onClick(() => this.count--)
      Text(`${this.count}`)
        .margin({ left: 10, right: 10 })
      Button('+')
        .onClick(() => this.count++)
    }
  }
}
```

---

## @Builder 复用

@Builder装饰的函数用于描述UI结构，可以在多处复用。

### 全局@Builder

```typescript
@Builder
function commonCard(title: string, content: string) {
  Column() {
    Text(title)
      .fontSize(18)
      .fontWeight(FontWeight.Bold)
    Text(content)
      .fontSize(14)
      .fontColor('#666666')
  }
  .padding(16)
  .borderRadius(8)
  .backgroundColor(Color.White)
}

// 使用
build() {
  Column() {
    commonCard('标题', '内容描述')
  }
}
```

### 组件内@Builder

```typescript
@Component
struct CardList {
  @Builder
  itemBuilder(title: string) {
    Text(title)
      .fontSize(16)
  }

  build() {
    Column() {
      this.itemBuilder('Item 1')
      this.itemBuilder('Item 2')
    }
  }
}
```

### @BuilderParam

@BuilderParam用于接收@Builder函数作为参数。

```typescript
@Component
struct Wrapper {
  @BuilderParam content: () => void;

  build() {
    Column() {
      this.content()
    }
    .padding(20)
    .backgroundColor('#f5f5f5')
  }
}

// 使用
@Builder
function myContent() {
  Text('自定义内容')
}

Wrapper({ content: myContent })
```

---

## 属性扩展 (@Extend)

@Extend装饰器用于扩展原生组件的属性设置。

### 基本使用

```typescript
@Extend(Text)
function commonTextStyle() {
  .fontSize(14)
  .fontColor('#333333')
  .maxLines(2)
  .textOverflow({ overflow: TextOverflow.Ellipsis })
}

// 使用
Text('Hello World')
  .commonTextStyle()
```

### 带参数的@Extend

```typescript
@Extend(Text)
function titleStyle(size: number, color: ResourceColor) {
  .fontSize(size)
  .fontColor(color)
  .fontWeight(FontWeight.Bold)
}

Text('Title')
  .titleStyle(24, Color.Blue)
```

---

## 样式扩展 (@Styles)

@Styles装饰器用于提取通用样式设置。

### 基本使用

```typescript
@Styles
function commonButtonStyle() {
  .width(100)
  .height(40)
  .borderRadius(20)
  .backgroundColor('#007DFF')
}

// 使用
Button('Click')
  .commonButtonStyle()
```

### 组件内@Styles

```typescript
@Component
struct MyComponent {
  @Styles
  cardStyle() {
    .padding(16)
    .borderRadius(8)
    .backgroundColor(Color.White)
    .shadow({ radius: 4, color: '#1a000000' })
  }

  build() {
    Column() {
      Text('Content')
    }
    .cardStyle()
  }
}
```

---

## @Extend 与 @Styles 区别

| 特性 | @Extend | @Styles |
|------|---------|---------|
| 支持参数 | 支持 | 不支持 |
| 支持事件 | 支持 | 不支持 |
| 支持组件指定 | 支持 | 不支持 |
| 使用范围 | 全局 | 全局/组件内 |

---

## 自定义Modifier

通过实现ContentModifier接口自定义修改内容。

### 基本使用

```typescript
class MyModifier implements ContentModifier<string> {
  apply(value: string): void {
    console.info(`Content: ${value}`);
  }
}

Text('Content')
  .contentModifier(new MyModifier())
```

---

## AttributeModifier

AttributeModifier接口用于动态修改组件属性。

### 基本使用

```typescript
class MyAttributeModifier implements AttributeModifier<TextAttribute> {
  applyNormalAttribute(instance: TextAttribute): void {
    instance.fontSize(16)
      .fontColor('#333333');
  }

  applyPressedAttribute(instance: TextAttribute): void {
    instance.fontColor('#FF0000');
  }

  applyFocusedAttribute(instance: TextAttribute): void {
    instance.fontColor('#007DFF');
  }

  applyDisabledAttribute(instance: TextAttribute): void {
    instance.fontColor('#999999');
  }

  applySelectedAttribute(instance: TextAttribute): void {
    instance.fontColor('#00FF00');
  }
}

Text('Hello')
  .attributeModifier(new MyAttributeModifier())
```

### AttributeModifier 方法

| 方法 | 说明 |
|------|------|
| applyNormalAttribute | 正常状态属性 |
| applyPressedAttribute | 按下状态属性 |
| applyFocusedAttribute | 获焦状态属性 |
| applyDisabledAttribute | 禁用状态属性 |
| applySelectedAttribute | 选中状态属性 |

## wrapBuilder

wrapBuilder用于包装@Builder函数，使其可以在命令式代码中使用。

### 基本使用

```typescript
@Builder
function myBuilder(text: string) {
  Text(text)
    .fontSize(16)
}

const wrappedBuilder = wrapBuilder<[string]>(myBuilder);
```

---

## 注意事项

1. **@Builder函数必须遵守UI描述规范**：只能包含UI组件，不能包含业务逻辑
2. **@Extend只能用于全局**：不支持在组件内定义
3. **@Styles不支持事件**：如果需要事件处理，使用@Extend
4. **自定义组件命名**：使用有意义的名称，便于理解和维护
5. **合理拆分**：将复杂组件拆分成多个小组件，提高可维护性

---

## 相关链接

- [自定义节点](custom-node.md)
- [状态管理](../02-state-management/component-state-decorators.md)