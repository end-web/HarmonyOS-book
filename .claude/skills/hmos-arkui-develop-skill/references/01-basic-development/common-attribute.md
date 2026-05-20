# 属性修饰

## 通用属性

### 尺寸

```typescript
Text('Content')
  .width(100)
  .height(50)
  .minWidth(50)
  .maxWidth(200)
  .minHeight(20)
  .maxHeight(100)
  .aspectRatio(1.5)
```

### 位置

```typescript
Text('Position')
  .position({ x: 10, y: 10 })
  .offset({ x: 5, y: 5 })
  .markAnchor({ x: 0, y: 0 })
  .align(Alignment.Center)
```

### 边距

```typescript
Text('Padding & Margin')
  .padding({ left: 10, right: 10, top: 5, bottom: 5 })
  .margin({ left: 10, right: 10, top: 5, bottom: 5 })
  // 或简写
  .padding(10)
  .margin(10)
```

### 边框

```typescript
Text('Border')
  .border({
    width: { left: 1, right: 2, top: 1, bottom: 2 },
    color: Color.Black,
    radius: 10,
    style: BorderStyle.Solid
  })
```

### 背景

```typescript
Text('Background')
  .backgroundColor('#F5F5F5')
  .backgroundImage($r('app.media.bg'))
  .backgroundBlurStyle(BlurStyle.COMPONENT_THIN)
```

---

## 变换属性

### 平移

```typescript
Text('Translate')
  .translate({ x: 10, y: 10, z: 0 })
```

### 缩放

```typescript
Text('Scale')
  .scale({ x: 1.5, y: 1.5, centerX: 0.5, centerY: 0.5 })
```

### 旋转

```typescript
Text('Rotate')
  .rotate({ 
    angle: 45,
    centerX: 0.5,
    centerY: 0.5
  })
```

---

## 交互属性

### 点击区域

```typescript
Text('Click Area')
  .width(50)
  .height(50)
  .responseRegion({ x: -10, y: -10, width: 70, height: 70 })
```

### 触摸热区

```typescript
Text('Touch')
  .hitTestBehavior(HitTestMode.Block)
```

---

## 焦点属性

```typescript
TextInput()
  .focusable(true)
  .defaultFocus(true)
  .groupDefaultFocus(true)
  .focusOnTouch(true)
```

---

## 可见性

```typescript
Text('Visibility')
  .visibility(Visibility.Visible)    // 可见
  .visibility(Visibility.Hidden)     // 隐藏但占位
  .visibility(Visibility.None)       // 隐藏不占位
```

---

## 启用/禁用

```typescript
Button('Disabled')
  .enabled(false)

TextInput()
  .enableKeyboardOnFocus(true)
```

---

## 动画属性

```typescript
Text('Animation')
  .animation({
    duration: 1000,
    curve: Curve.EaseInOut,
    delay: 0,
    iterations: 1,
    playMode: PlayMode.Normal
  })
```

---

## 样式修饰器

### @Styles

```typescript
@Styles
function commonCardStyle() {
  .width('100%')
  .padding(16)
  .borderRadius(8)
  .backgroundColor(Color.White)
  .shadow({ radius: 4, color: '#1A000000' })
}

Column() {
  Text('Card Content')
}
.commonCardStyle()
```

### @Extend

```typescript
@Extend(Text)
function titleText() {
  .fontSize(20)
  .fontWeight(FontWeight.Bold)
  .fontColor('#333333')
  .maxLines(1)
  .textOverflow({ overflow: TextOverflow.Ellipsis })
}

Text('Title')
  .titleText()
```

---

## AttributeModifier

动态修改属性。

```typescript
class ButtonModifier implements AttributeModifier<ButtonAttribute> {
  private isPressed: boolean = false;

  applyNormalAttribute(instance: ButtonAttribute): void {
    instance.backgroundColor('#007DFF');
  }

  applyPressedAttribute(instance: ButtonAttribute): void {
    instance.backgroundColor('#0057D9');
  }
}

Button('Dynamic')
  .attributeModifier(new ButtonModifier())
```

---

## ContentModifier

修改组件内容。

```typescript
class MyContentModifier implements ContentModifier<string> {
  apply(value: string): void {
    // 修改内容
  }
}

Text('Content')
  .contentModifier(new MyContentModifier())
```