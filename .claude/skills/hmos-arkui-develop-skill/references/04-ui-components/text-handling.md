# 文本处理

## 文本显示 (Text)

### 基本属性

```typescript
Text('Hello World')
  .fontSize(16)
  .fontColor('#333333')
  .fontWeight(FontWeight.Normal)
  .fontFamily('HarmonyOS Sans')
  .fontStyle(FontStyle.Normal)
  .letterSpacing(1)
  .lineHeight(24)
```

### 文本对齐

```typescript
Text('Content')
  .textAlign(TextAlign.Start)      // 左对齐
  .textAlign(TextAlign.Center)     // 居中
  .textAlign(TextAlign.End)        // 右对齐
```

### 文本截断

```typescript
Text('Very long text...')
  .maxLines(2)
  .textOverflow({ overflow: TextOverflow.Ellipsis })
```

### 基线偏移

```typescript
Text('Text with baseline')
  .baselineOffset(5)
```

---

### 装饰线

```typescript
Text('Text with baseline')
  .decoration({ type: TextDecorationType.LineThrough })
```

## 富文本 (Span)

```typescript
Text() {
  Span('Normal text ')
    .fontSize(14)
  Span('Bold text')
    .fontWeight(FontWeight.Bold)
    .fontColor(Color.Red)
  Span(' Underline')
    .decoration({ type: TextDecorationType.Underline, color: Color.Blue })
}
```

### ImageSpan

```typescript
Text() {
  ImageSpan($r('app.media.icon'))
    .width(20)
    .height(20)
    .verticalAlign(ImageSpanAlignment.CENTER)
  Span('Text with icon')
}
```

---

## 样式字符串 (StyledString)

```typescript
import { StyledString } from '@kit.ArkUI';

@State styledString: StyledString = new StyledString(
  'Hello World',
  [{ start: 0, length: 5, styledKey: StyledStringKey.FONT, styledValue: this.fontStyle }]
);

Text(this.styledString)
```

---

## 文本输入 (TextInput)

```typescript
TextInput({ placeholder: 'Enter text' })
  .type(InputType.Normal)
  .maxLength(100)
  .enterKeyType(EnterKeyType.Search)
  .caretColor('#007DFF')
  .placeholderColor('#999999')
  .placeholderFont({ size: 14 })
  .onChange((value) => {
    this.inputValue = value;
  })
  .onSubmit(() => {
    // 提交处理
  })
```

### 输入类型

| 类型 | 说明 |
|-----|------|
| Normal | 普通文本 |
| Password | 密码 |
| Email | 邮箱 |
| Number | 数字 |
| PhoneNumber | 电话号码 |

---

## 多行文本 (TextArea)

```typescript
TextArea({ placeholder: 'Enter description' })
  .height(100)
  .maxLength(500)
  .placeholderColor('#999999')
  .caretColor('#007DFF')
  .onChange((value) => {
    this.textAreaValue = value;
  })
```

---

## 富文本编辑器 (RichEditor)

```typescript
RichEditor({ controller: this.controller })
  .width('100%')
  .height(200)
  .onReady(() => {
    this.controller.addText('Initial content');
  })

// 插入文本
this.controller.addText('New text', { fontSize: 16, fontColor: Color.Red });

// 插入图片
this.controller.addImage($r('app.media.pic'), {
  size: { width: 100, height: 100 }
});

// 获取内容
let spans = this.controller.getSpans();

// 删除内容
this.controller.deleteSpans({ start: 0, end: 10 });
```

---

## 文本选择

### TextSelection

```typescript
TextInput()
  .selection({ start: 0, end: 5 })
```

### 获取选中文本

```typescript
TextInput()
  .onSelect((selectionStart: number, selectionEnd: number) => {
    console.info(`Selected: ${selectionStart} - ${selectionEnd}`);
  })
```

---

## 文本内嵌图标 (SymbolSpan)

作为Text子组件，在文本中穿插显示图标。

```typescript
Text() {
  SymbolSpan($r('sys.symbol.ohos_trash'))
    .fontWeight(FontWeight.Normal)
    .fontSize(48)
    .fontColor([Color.Red])
}
```

### 常用属性

| 属性 | 说明 |
|-----|------|
| fontSize | 设置大小 |
| fontColor | 设置颜色（数组形式） |
| fontWeight | 设置粗细 |
| renderingStrategy | 渲染策略：SINGLE/MULTIPLE_COLOR/MULTIPLE_OPACITY |
| effectStrategy | 动效策略：NONE/SCALE/HIERARCHICAL |

### 示例

```typescript
Text() {
  Span('点击')
  SymbolSpan($r('sys.symbol.ohos_wifi'))
    .fontSize(20)
    .fontColor([Color.Blue])
  Span('连接WiFi')
}
```

---

## 文本测量

```typescript
import { measure } from '@kit.ArkUI';

let textSize = measure.measureText({
  textContent: 'Hello',
  fontSize: 16,
  fontWeight: FontWeight.Normal
});

console.info(`Width: ${textText.width}`);
```

---

## 常见问题

### 文本换行

```typescript
Text('Long text with word break')
  .wordBreak(WordBreak.BREAK_ALL)  // 允许在任意字符换行
```

### 文本复制

```typescript
Text('Copyable text')
  .copyOption(CopyOption.InApp)  // 应用内可复制
```

### 行高设置

```typescript
Text('Multiple lines')
  .lineHeight(24)
  .lineSpacing(5)  // 行间距
```