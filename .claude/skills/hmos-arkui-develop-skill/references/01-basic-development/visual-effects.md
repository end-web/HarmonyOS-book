# 视觉效果

## 模糊效果 (blur)

```typescript
Image($r('app.media.pic'))
  .width(200)
  .height(200)
  .blur(10)  // 模糊半径

// 背景模糊
Column() {
  Text('Content')
}
.width(200)
.height(200)
.backgroundBlurStyle(BlurStyle.COMPONENT_ULTRA_THICK)
```

---

## 阴影效果 (shadow)

```typescript
Column() {
  Text('Content')
}
.width(100)
.height(100)
.shadow({
  radius: 10,
  color: Color.Black,
  offsetX: 5,
  offsetY: 5
})
```

### shadow属性

| 参数 | 说明 |
|-----|------|
| radius | 模糊半径 |
| color | 阴影颜色 |
| offsetX | X偏移 |
| offsetY | Y偏移 |

---

## 颜色滤镜 (colorFilter)

```typescript
Image($r('app.media.pic'))
  .width(200)
  .colorFilter(new ColorFilter([
    1, 0, 0, 0, 0,
    0, 1, 0, 0, 0,
    0, 0, 1, 0, 0,
    0, 0, 0, 1, 0
  ]))
```

---

## 亮度 (brightness)

```typescript
Image($r('app.media.pic'))
  .brightness(0.5)  // -1到1，0为原图
```

---

## 对比度 (contrast)

```typescript
Image($r('app.media.pic'))
  .contrast(1.5)  // >1增强，<1减弱
```

---

## 饱和度 (saturate)

```typescript
Image($r('app.media.pic'))
  .saturate(1.5)  // >1增强，<1减弱
```

---

## 灰度 (grayscale)

```typescript
Image($r('app.media.pic'))
  .grayscale(1.0)  // 0到1，1为完全灰度
```

---

## 色调旋转 (hueRotate)

```typescript
Image($r('app.media.pic'))
  .hueRotate(90)  // 角度
```

---

## 颜色反转 (invert)

```typescript
Image($r('app.media.pic'))
  .invert(1.0)  // 0到1，1为完全反转
```

---

## 透明度 (opacity)

```typescript
Column() {
  Text('Semi-transparent')
}
.opacity(0.5)  // 0到1
```

---

## 裁剪 (clip)

```typescript
// 圆形裁剪
Image($r('app.media.pic'))
  .width(100)
  .height(100)
  .clip(new Circle({ width: 100, height: 100 }))

// 圆角裁剪
Column() {
  Text('Content')
}
.clip(new Rect({ width: 100, height: 100, radius: 10 }))
```

---

## 遮罩 (mask)

```typescript
Image($r('app.media.pic'))
  .width(200)
  .height(200)
  .mask(new Circle({ width: 200, height: 200 }))
```

---

## 渐变色

### 线性渐变

```typescript
Column() {
  Text('Gradient')
}
.width(200)
.height(100)
.linearGradient({
  angle: 45,
  colors: [
    ['#FF0000', 0.0],
    ['#00FF00', 0.5],
    ['#0000FF', 1.0]
  ]
})
```

### 径向渐变

```typescript
Column() {
  Text('Radial')
}
.width(200)
.height(200)
.radialGradient({
  center: [100, 100],
  radius: 100,
  colors: [
    ['#FFFFFF', 0.0],
    ['#000000', 1.0]
  ]
})
```

---

## 背景图片

```typescript
Column() {
  Text('Background')
}
.width(200)
.height(200)
.backgroundImage($r('app.media.bg'))
.backgroundImageSize({ width: '100%', height: '100%' })
.backgroundImagePosition({ x: 0, y: 0 })
```