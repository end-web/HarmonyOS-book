# UI组件

## 基础组件

### 按钮 (Button)

```typescript
// 文字按钮
Button('Click Me')
  .type(ButtonType.Capsule)
  .width(100)
  .height(40)
  .onClick(() => {})

// 自定义按钮
Button({ type: ButtonType.Normal }) {
  Row() {
    LoadingProgress().width(20)
    Text('Loading')
  }
}
```

### 文本显示 (Text)

详细的文本开发参考:

```typescript
Text('Hello World')
  .fontSize(16)
  .fontColor('#333333')
  .fontWeight(FontWeight.Bold)
  .maxLines(2)
  .textOverflow({ overflow: TextOverflow.Ellipsis })

// 富文本
Text() {
  Span('Normal ').fontSize(14)
  Span('Bold').fontWeight(FontWeight.Bold)
  Span(' Red').fontColor(Color.Red)
}
```

### 进度条 (Progress)

```typescript
// 线性
Progress({ value: 50, total: 100, type: ProgressType.Linear })
// 环形
Progress({ value: 50, type: ProgressType.Ring })
```

---

## 输入组件

### 文本输入 (TextInput)

```typescript
TextInput({ placeholder: 'Enter text' })
  .type(InputType.Normal)
  .maxLength(100)
  .onChange((value) => {})

// 类型
.type(InputType.Password)  // 密码
.type(InputType.Email)     // 邮箱
.type(InputType.Number)    // 数字
```

### 多行文本 (TextArea)

```typescript
TextArea({ placeholder: 'Enter description' })
  .height(100)
  .maxLength(500)
  .onChange((value) => {})
```

### 选择器 (Select)

```typescript
Select([
  { value: 'Option 1' },
  { value: 'Option 2' }
])
  .selected(0)
  .onSelect((index: number) => {})
```

---

## 表单组件

### 开关 (Toggle)

```typescript
Toggle({ type: ToggleType.Switch, isOn: false })
  .onChange((isOn) => {})
```

### 复选框 (Checkbox)

```typescript
Checkbox({ name: 'checkbox', group: 'group' })
  .select(this.checked)
  .onChange((checked) => { this.checked = checked; })
```

### 单选框 (Radio)

```typescript
Radio({ value: 'option1', group: 'radioGroup' })
  .checked(this.selected === 'option1')
  .onChange((checked) => {
    if (checked) this.selected = 'option1';
  })
```

### 滑块 (Slider)

```typescript
Slider({ value: this.value, min: 0, max: 100 })
  .blockColor('#007DFF')
  .onChange((value) => { this.value = value; })
```

### 评分 (Rating)

```typescript
Rating({ rating: this.rating, indicator: false })
  .stars(5)
  .onChange((rating) => { this.rating = rating; })
```

---

## 日期时间选择器

### 日期选择 (DatePicker)

```typescript
DatePicker({
  start: new Date('1970-1-1'),
  end: new Date('2100-12-31'),
  selected: new Date()
})
  .onDateChange((value: Date) => {})
```

### 时间选择 (TimePicker)

```typescript
TimePicker({ selected: new Date() })
  .useMilitaryTime(true)
  .onChange((value: TimePickerResult) => {})
```

### 文本选择 (TextPicker)

```typescript
TextPicker({ range: ['Option 1', 'Option 2'], selected: 0 })
  .onChange((value: string, index: number) => {})
```

---

## 媒体组件

### 图片 (Image)

```typescript
Image('https://example.com/image.jpg')
  .width(100)
  .height(100)
  .objectFit(ImageFit.Cover)
  .onComplete(() => {})
  .onError(() => {})
```

| ImageFit  | 说明                   |
| --------- | ---------------------- |
| Cover     | 保持比例填充，可能裁剪 |
| Contain   | 保持比例完整显示       |
| Fill      | 拉伸填充               |
| ScaleDown | 等比缩小               |

### 视频播放 (Video)

```typescript
Video({ src: this.videoUrl, controller: this.controller })
  .width('100%')
  .height(200)
  .autoPlay(true)
  .controls(true)
```

### 符号图标 (SymbolGlyph)

显示系统预置图标，支持多色渲染和动效。

```typescript
SymbolGlyph($r('sys.symbol.checkmark'))
  .fontSize(24)
  .fontColor([Color.BLUE])
```

#### 渲染策略

| 策略 | 说明 |
|-----|------|
| SINGLE | 单色模式（默认） |
| MULTIPLE_COLOR | 多色模式，最多三个颜色 |
| MULTIPLE_OPACITY | 分层模式，不同层透明度不同 |

```typescript
SymbolGlyph($r('sys.symbol.ohos_folder_badge_plus'))
  .fontSize(96)
  .renderingStrategy(SymbolRenderingStrategy.MULTIPLE_COLOR)
  .fontColor([Color.Black, Color.Green, Color.White])
```

#### 动效策略

```typescript
// 自动播放
SymbolGlyph($r('sys.symbol.ohos_wifi'))
  .effectStrategy(SymbolEffectStrategy.SCALE)

// 可控播放
@State isActive: boolean = true;
SymbolGlyph($r('sys.symbol.ohos_wifi'))
  .symbolEffect(new HierarchicalSymbolEffect(), this.isActive)
```

| 动效类型 | 说明 |
|-----|------|
| ScaleSymbolEffect | 缩放动效 |
| HierarchicalSymbolEffect | 层级动效 |
| BounceSymbolEffect | 弹跳动效 |
| ReplaceSymbolEffect | 替换动效 |

### 轮播图（Swiper）

待补充