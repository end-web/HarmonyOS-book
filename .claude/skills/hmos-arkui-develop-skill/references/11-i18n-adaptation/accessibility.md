# 可访问性

## 无障碍属性

### accessibilityText

```typescript
Image($r('app.media.icon'))
  .accessibilityText('应用图标')
  .accessibilityDescription('点击打开应用')
```

### accessibilityGroup

```typescript
Column() {
  Text('Title')
  Text('Description')
}
.accessibilityGroup(true)
.accessibilityText('卡片：标题和描述')
```

---

## 无障碍重要性

```typescript
Text('Important')
  .accessibilityLevel('important')  // 强制可访问

Text('No')
  .accessibilityLevel('no')         // 不对无障碍服务可见

Text('Auto')
  .accessibilityLevel('auto')       // 自动判断
```

---

## 无障碍操作

### 自定义操作

```typescript
Text('Custom Action')
  .accessibilityActions([
    { name: 'Action1', action: () => {} },
    { name: 'Action2', action: () => {} }
  ])
```

### 预置操作

```typescript
Text('Click Me')
  .accessibilityAction({
    name: 'click',
    action: () => {
      console.info('Accessibility action triggered');
    }
  })
```

---

## 焦点导航

### 焦点顺序

```typescript
Column() {
  TextInput()
    .accessibilityOrder(1)

  Button('Submit')
    .accessibilityOrder(2)

  Button('Cancel')
    .accessibilityOrder(3)
}
```

### 焦点组

```typescript
Column() {
  TextInput()
  TextInput()
}
.accessibilityGroup(true)
```

---

## 屏幕朗读

### 朗读文本

```typescript
Text('Hello World')
  .accessibilityText('你好世界')
```

### 隐藏元素

```typescript
Text('Internal State')
  .accessibilityLevel('no')  // 不被朗读
```

---

## 高对比度

### 高对比度检测

```typescript
@StorageProp('highContrast') highContrast: boolean = false;

build() {
  Text('Content')
    .fontColor(this.highContrast ? '#000000' : '#333333')
}
```

---

## 适老化支持

### 字体缩放

```typescript
@StorageProp('fontSizeScale') fontSizeScale: number = 1.0;

Text('Content')
  .fontSize(16 * this.fontSizeScale)
```

### 大按钮

```typescript
Button('Click')
  .width(Math.max(48, 48 * this.fontSizeScale))
  .height(Math.max(48, 48 * this.fontSizeScale))
```

---

## 颜色盲支持

```typescript
// 避免仅使用颜色传达信息
Column() {
  Image($r('app.media.success'))
  Text('Success')  // 同时使用图标和文字
}
```

---

## 无障碍测试

### 使用DevEco Studio

1. 打开无障碍检查器
2. 运行应用
3. 查看无障碍问题

### 检查清单

- [ ] 所有可交互元素有无障碍文本
- [ ] 图片有描述性文本
- [ ] 焦点顺序合理
- [ ] 颜色对比度足够
- [ ] 支持键盘导航