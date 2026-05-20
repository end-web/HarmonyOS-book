# 图形绘制

Canvas提供画布组件用于自定义绘制图形；Shape提供声明式绘制组件。

## 绘制方式选择

| 方式 | 特点 | 适用场景 |
|-----|------|---------|
| CanvasRenderingContext2D | 命令式API，类Web标准 | 动态绘制、图表、游戏 |
| DrawingRenderingContext | 使用Drawing模块，功能丰富 | 高级2D绘制、复杂图形 |
| Shape组件 | 声明式，易于维护 | 静态图形、UI装饰 |

> 高性能渲染请参考 [自定义渲染](../09-custom-nodes/custom-rendering.md)

---

## Canvas组件

### 使用CanvasRenderingContext2D

```typescript
@Entry
@Component
struct CanvasPage {
  private settings: RenderingContextSettings = new RenderingContextSettings(true);
  private context: CanvasRenderingContext2D = new CanvasRenderingContext2D(this.settings);

  build() {
    Canvas(this.context)
      .width('100%')
      .height(300)
      .onReady(() => {
        this.context.fillStyle = '#FF0000';
        this.context.fillRect(10, 10, 100, 50);
      })
  }
}
```

### 使用DrawingRenderingContext

```typescript
import { drawing } from '@kit.ArkGraphics2D';

@Entry
@Component
struct DrawingPage {
  private context: DrawingRenderingContext = new DrawingRenderingContext();

  build() {
    Canvas(this.context)
      .width('100%')
      .height(300)
      .onReady(() => {
        let brush = new drawing.Brush();
        brush.setColor({ alpha: 255, red: 39, green: 135, blue: 217 });
        this.context.canvas.attachBrush(brush);
        this.context.canvas.drawCircle(150, 150, 100);
        this.context.canvas.detachBrush();
        this.context.invalidate(); // 触发重新渲染
      })
  }
}
```

### 单位模式配置

```typescript
import { LengthMetricsUnit } from '@kit.ArkUI'

// 使用px单位
private contextPX: CanvasRenderingContext2D = new CanvasRenderingContext2D(
  new RenderingContextSettings(true), 
  LengthMetricsUnit.PX
);

// 使用vp单位（默认）
private contextVP: CanvasRenderingContext2D = new CanvasRenderingContext2D(
  new RenderingContextSettings(true)
);
```

### onReady生命周期

onReady在Canvas初始化完成或大小变化时触发，此时可获取确定宽高进行绘制。**注意：onReady触发时画布会被清空。**

```typescript
Canvas(this.context)
  .onReady(() => {
    // Canvas宽高确定，可开始绘制
    this.draw();
  })
```

---

## 基础形状绘制

### 矩形

```typescript
// 填充矩形
this.context.fillRect(10, 10, 100, 50);

// 描边矩形
this.context.strokeRect(120, 10, 100, 50);

// 清除区域
this.context.clearRect(50, 20, 50, 30);

// 创建矩形路径
this.context.beginPath();
this.context.rect(10, 10, 100, 50);
this.context.stroke();
```

### 圆形和椭圆

```typescript
// 圆形
this.context.beginPath();
this.context.arc(100, 100, 50, 0, Math.PI * 2);
this.context.fill();

// 椭圆（x, y, radiusX, radiusY, rotation, startAngle, endAngle）
this.context.beginPath();
this.context.ellipse(150, 100, 50, 80, 0, 0, Math.PI * 2);
this.context.stroke();
```

### 圆角矩形

```typescript
// API 20+
this.context.beginPath();
this.context.roundRect(10, 10, 100, 50, 10);
this.context.stroke();
```

### 路径绘制

```typescript
this.context.beginPath();
this.context.moveTo(10, 10);      // 起点
this.context.lineTo(100, 10);     // 直线到
this.context.lineTo(100, 100);    // 直线到
this.context.closePath();         // 闭合路径
this.context.stroke();

// 贝塞尔曲线
this.context.bezierCurveTo(cp1x, cp1y, cp2x, cp2y, x, y);  // 三次贝塞尔
this.context.quadraticCurveTo(cpx, cpy, x, y);             // 二次贝塞尔

// 弧线
this.context.arcTo(x1, y1, x2, y2, radius);
```

### Path2D对象

先定义路径，再绘制。适用于复杂路径复用。

```typescript
let path = new Path2D();
path.moveTo(150, 50);
path.lineTo(50, 150);
path.lineTo(250, 150);
path.closePath();

// Path2D也支持SVG路径字符串
let starPath = new Path2D('M150 0 L180 100 L300 100 L200 160 L230 270 L150 200 L70 270 L100 160 L0 100 L120 100 Z');

this.context.fillStyle = '#0097D4';
this.context.fill(path);
this.context.strokeStyle = '#000000';
this.context.stroke(path);
```

---

## 文本绘制

### 基础文本

```typescript
// 设置字体：font-style font-weight font-size font-family
this.context.font = 'italic bold 24px sans-serif';

// 填充文本
this.context.fillStyle = '#000000';
this.context.fillText('Hello World', 50, 100);

// 描边文本
this.context.strokeStyle = '#FF0000';
this.context.lineWidth = 2;
this.context.strokeText('Hello World', 50, 150);
```

### 文本对齐

```typescript
// 水平对齐：left/right/center/start/end
this.context.textAlign = 'center';

// 垂直对齐：top/bottom/middle/alphabetic/hanging/ideographic
this.context.textBaseline = 'middle';
```

### 文本测量

```typescript
let metrics = this.context.measureText('Hello World');
console.info(`Width: ${metrics.width}`);
console.info(`Height: ${metrics.height}`);
```

### 自定义字体（API 20+）

```typescript
import { text } from '@kit.ArkGraphics2D';

// 加载自定义字体
let fontCollection = text.FontCollection.getGlobalInstance();
fontCollection.loadFontSync('customFont', $rawfile('customFont.ttf'));

// 使用自定义字体
this.context.font = '30vp customFont';
this.context.fillText('Hello World!', 20, 50);
```

---

## 图片绘制

### 绘制图片

```typescript
let image = new ImageBitmap('/common/images/image.png');

// 基础绘制
this.context.drawImage(image, 0, 0);

// 指定尺寸
this.context.drawImage(image, 0, 0, 100, 100);

// 裁剪绘制（源区域 -> 目标区域）
this.context.drawImage(image, 0, 0, 50, 50, 100, 100, 100, 100);
```

### 像素操作

```typescript
// 获取像素数据
let imageData = this.context.getImageData(0, 0, 100, 100);
// imageData.data: Uint8ClampedArray，每个像素4字节（RGBA）

// 创建空像素数据
let newImageData = this.context.createImageData(100, 100);

// 绘制像素数据
this.context.putImageData(imageData, 150, 0);

// 获取PixelMap（用于Image组件）
let pixelMap = this.context.getPixelMap(0, 0, 100, 100);
```

---

## 样式属性

### 填充与描边

```typescript
// 填充颜色
this.context.fillStyle = '#FF0000';
this.context.fillStyle = 'rgb(255, 0, 0)';
this.context.fillStyle = 'rgba(255, 0, 0, 0.5)';

// 描边颜色
this.context.strokeStyle = '#0000FF';

// 线宽
this.context.lineWidth = 5;

// 线端样式：butt（默认）/ round / square
this.context.lineCap = 'round';

// 线段连接样式：miter（默认）/ round / bevel
this.context.lineJoin = 'round';

// 斜接极限（lineJoin为miter时生效）
this.context.miterLimit = 10;

// 虚线
this.context.setLineDash([5, 10, 15]);
this.context.lineDashOffset = 0;
```

### 透明度与合成

```typescript
// 全局透明度 [0.0, 1.0]
this.context.globalAlpha = 0.5;

// 合成操作：source-over（默认）/ source-atop / source-in / source-out / 
// destination-over / destination-atop / destination-in / destination-out / lighter / copy / xor
this.context.globalCompositeOperation = 'source-over';
```

### 阴影

```typescript
this.context.shadowBlur = 10;      // 模糊级别
this.context.shadowColor = '#000000';
this.context.shadowOffsetX = 5;    // 水平偏移
this.context.shadowOffsetY = 5;    // 垂直偏移
```

### 滤镜

```typescript
// 高斯模糊
this.context.filter = 'blur(5px)';

// 亮度
this.context.filter = 'brightness(1.5)';

// 对比度
this.context.filter = 'contrast(1.2)';

// 灰度
this.context.filter = 'grayscale(1)';

// 组合滤镜
this.context.filter = 'blur(2px) brightness(1.1) contrast(1.2)';
```

---

## 变换操作

```typescript
// 保存当前状态
this.context.save();

// 平移
this.context.translate(50, 50);

// 旋转（弧度）
this.context.rotate(Math.PI / 4);

// 缩放
this.context.scale(2, 2);

// 变换矩阵
this.context.transform(a, b, c, d, e, f);
this.context.setTransform(a, b, c, d, e, f);

// 重置变换
this.context.resetTransform();

// 恢复状态
this.context.restore();
```

---

## 渐变与图案

### 线性渐变

```typescript
let gradient = this.context.createLinearGradient(0, 0, 200, 0);
gradient.addColorStop(0, '#FF0000');
gradient.addColorStop(0.5, '#FFFF00');
gradient.addColorStop(1, '#0000FF');
this.context.fillStyle = gradient;
this.context.fillRect(0, 0, 200, 100);
```

### 径向渐变

```typescript
// createRadialGradient(x0, y0, r0, x1, y1, r1)
let gradient = this.context.createRadialGradient(100, 100, 0, 100, 100, 100);
gradient.addColorStop(0, '#FFFFFF');
gradient.addColorStop(1, '#000000');
this.context.fillStyle = gradient;
this.context.beginPath();
this.context.arc(100, 100, 100, 0, Math.PI * 2);
this.context.fill();
```

### 图案填充

```typescript
let image = new ImageBitmap('/common/images/pattern.png');
let pattern = this.context.createPattern(image, 'repeat'); // repeat/repeat-x/repeat-y/no-repeat
this.context.fillStyle = pattern;
this.context.fillRect(0, 0, 200, 200);
```

---

## Shape组件

声明式绘制，支持Circle、Ellipse、Line、Polyline、Polygon、Path、Rect。

### 独立使用

```typescript
// 矩形
Rect({ width: 100, height: 50 }).fill('#FF0000')

// 圆形
Circle({ width: 100, height: 100 }).fill('#00FF00')

// 椭圆
Ellipse({ width: 100, height: 50 }).fill('#0000FF')

// 线条
Line().width(100).height(100).startPoint([0, 0]).endPoint([100, 100]).stroke(Color.Black)

// 折线
Polyline().points([[0, 0], [50, 50], [100, 0]]).stroke(Color.Black)

// 多边形
Polygon().points([[50, 0], [100, 50], [50, 100], [0, 50]]).fill('#FF0000')

// 路径（SVG命令）
Path().commands('M10 10 L90 10 L90 90 Z').fill('#00FF00')
```

### Shape容器

多个图形组合，支持viewPort视口设置。

```typescript
Shape() {
  Rect().width('100%').height('100%').fill('#0097D4')
  Circle({ width: 75, height: 75 }).fill('#E87361')
}
.viewPort({ x: 0, y: 0, width: 300, height: 300 })
.width(150)
.height(150)
.stroke(Color.Black)
.strokeWidth(2)
```

### 样式属性

| 属性 | 说明 | 默认值 |
|-----|------|-------|
| fill | 填充颜色 | - |
| stroke | 边框颜色 | - |
| strokeWidth | 边框宽度 | 1 |
| fillOpacity | 填充透明度 | 1 |
| strokeOpacity | 边框透明度 | 1 |
| strokeDashArray | 虚线样式 | - |
| strokeLineJoin | 拐角样式：Miter/Bevel/Round | Miter |
| strokeMiterLimit | 斜接极限 | 4 |
| antiAlias | 抗锯齿 | true |

---

## 离屏渲染

将内容绘制到缓存区，再一次性绘制到Canvas，提高绘制速度。

```typescript
private offCanvas: OffscreenCanvas = new OffscreenCanvas(600, 600);

build() {
  Canvas(this.context)
    .onReady(() => {
      let offContext = this.offCanvas.getContext('2d', this.settings);
      
      // 在离屏画布绘制
      offContext.fillStyle = '#FF0000';
      offContext.fillRect(0, 0, 100, 100);
      
      // 转换为ImageBitmap
      let image = this.offCanvas.transferToImageBitmap();
      
      // 绘制到主画布
      this.context.drawImage(image, 0, 0);
    })
}
```

---

## 状态变量驱动刷新

通过@Watch监听状态变化，驱动Canvas重绘。

```typescript
@Entry
@Component
struct CanvasRefresh {
  private context: CanvasRenderingContext2D = new CanvasRenderingContext2D();
  @State @Watch('draw') content: string = 'Hello';

  draw() {
    this.context.clearRect(0, 0, 400, 200);
    this.context.font = '30px sans-serif';
    this.context.fillText(this.content, 50, 100);
  }

  build() {
    Column() {
      Canvas(this.context)
        .width('100%')
        .height(200)
        .onReady(() => this.draw())
      TextInput({ text: $$this.content })
    }
  }
}
```

---

## 可见性控制

Canvas不可见时避免无效绘制，防止指令堆积导致内存占用过大。

```typescript
Canvas(this.context)
  .width(300)
  .height(300)
  .onVisibleAreaApproximateChange({ ratios: [0.0] },
    (isVisible: boolean, currentRatio: number) => {
      if (!isVisible && currentRatio <= 0) {
        // 不可见，停止绘制
        clearInterval(this.timerId);
        this.timerId = -1;
      } else if (isVisible && this.timerId < 0) {
        // 可见，开始绘制
        this.timerId = setInterval(() => this.draw(), 500);
      }
    })
```

---

## 约束与限制

1. **尺寸限制** - Canvas宽或高超过8000px时使用CPU渲染，性能明显下降
2. **最大面积** - 创建时最大面积不超过10000px×10000px
3. **绘制时机** - 绘制指令存入队列，仅当Canvas可见时才执行
4. **onReady触发** - 触发时画布会被清空
5. **单位默认值** - 参数如无特别说明，单位均为vp

---

## CanvasRenderingContext2D常用方法

| 方法 | 说明 |
|-----|------|
| beginPath() | 开始新路径 |
| closePath() | 闭合路径 |
| moveTo(x, y) | 移动到指定点 |
| lineTo(x, y) | 直线到指定点 |
| arc(x, y, r, start, end) | 绘制弧线 |
| fill() | 填充路径 |
| stroke() | 描边路径 |
| clip() | 裁剪路径 |
| save() / restore() | 保存/恢复状态 |
| clearRect(x, y, w, h) | 清除矩形区域 |
| reset() | 重置画布（API 13+）