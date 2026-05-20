# 调试与性能

## DevEco Studio预览器

### 实时预览

- 修改代码后自动刷新预览
- 支持多设备尺寸预览
- 支持深色模式预览

### 预览器注解

```typescript
@Preview
@Component
struct PreviewComponent {
  build() {
    Text('Preview')
  }
}
```

---

## 组件检查器

### 使用Inspector

```typescript
Column() {
  Text('Debug')
}
.inspectInspector((info: InspectorInfo) => {
  console.info(`Component: ${info.name}`);
})
```

### 查看组件树

DevEco Studio > View > Tool Windows > Inspector

---

## 性能分析

### Profiler工具

1. CPU Profiler：分析CPU使用
2. Memory Profiler：分析内存使用
3. Frame Profiler：分析帧率

### 性能指标

| 指标 | 目标值 |
|-----|-------|
| 帧率 | ≥60fps |
| 启动时间 | <2s |
| 内存占用 | <100MB |

---

## 性能优化建议

### 1. 减少嵌套层级

```typescript
// 不推荐：多层嵌套
Column() {
  Column() {
    Column() {
      Text('Content')
    }
  }
}

// 推荐：减少嵌套
Column() {
  Text('Content')
}
```

### 2. 条件渲染优化

```typescript
// 不推荐：频繁创建销毁
if (this.show) {
  ComplexComponent()
}

// 推荐：使用visibility控制
ComplexComponent()
  .visibility(this.show ? Visibility.Visible : Visibility.None)
```

### 3. 列表优化

```typescript
// 使用LazyForEach
List() {
  LazyForEach(this.dataSource, (item) => {
    ListItem() { /* ... */ }
  })
}
.cachedCount(5)

// 列表项复用
@Reusable
@Component
struct ListItemComponent {
  // ...
}
```

### 4. 图片优化

```typescript
// 使用合适的图片格式和大小
Image($r('app.media.pic'))
  .objectFit(ImageFit.Cover)
  .interpolation(ImageInterpolation.High)  // 高质量插值
```

### 5. 动画优化

```typescript
// 使用transform代替布局属性
animateTo({ duration: 300 }, () => {
  this.scale = { x: 1.5, y: 1.5 };  // GPU加速
});
```

---

## 日志调试

### hilog

```typescript
import { hilog } from '@kit.PerformanceAnalysisKit';

const DOMAIN = 0xFF00;
const TAG = 'MyApp';

hilog.debug(DOMAIN, TAG, 'Debug message');
hilog.info(DOMAIN, TAG, 'Info message');
hilog.warn(DOMAIN, TAG, 'Warning message');
hilog.error(DOMAIN, TAG, 'Error message');
```

---

## 组件可见性管理

```typescript
@State isVisible: boolean = false;

Column() {
  Text('Content')
}
.visibility(this.isVisible ? Visibility.Visible : Visibility.Hidden)
.onVisibleAreaChange([0.0, 1.0], (isVisible: boolean) => {
  this.isVisible = isVisible;
})
```