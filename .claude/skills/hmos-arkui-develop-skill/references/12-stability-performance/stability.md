# 稳定性

## 常见崩溃问题

### 状态变量问题

```typescript
// 错误：@State未初始化
@State count: number;  // 编译报错

// 正确
@State count: number = 0;
```

### 类型不匹配

```typescript
// 错误：类型不匹配
@State info: Info = new Info();
@Link test: Cousin;  // 类型与数据源不一致

// 正确
@Link test: Info;
```

### 空指针访问

```typescript
// 错误：可能空指针
Text(this.obj?.name)

// 正确：添加空判断
if (this.obj) {
  Text(this.obj.name)
}
```

---

## 冻结问题

### 避免在build中执行耗时操作

```typescript
// 错误：build中执行耗时操作
build() {
  let result = this.heavyCalculation();  // 阻塞UI
  return Text(`${result}`);
}

// 正确：异步处理
async aboutToAppear() {
  this.result = await this.heavyCalculation();
}
```

### 避免无限循环

```typescript
// 错误：@Watch中修改变量导致循环
@State @Watch('onChange') count: number = 0;

onChange() {
  this.count++;  // 再次触发onChange
}

// 正确：添加判断
onChange() {
  if (this.count < 100) {
    this.count++;
  }
}
```

---

## 内存泄漏

### 及时释放资源

```typescript
aboutToDisappear() {
  // 释放定时器
  clearTimeout(this.timer);
  
  // 取消监听
  this.uiContext.getOverlayManager().removeAllOverlays();
}
```

### 避免循环引用

```typescript
// 错误：循环引用
class Handler {
  component: MyComponent;  // 引用组件
}

@Component
struct MyComponent {
  handler: Handler = new Handler(this);  // 引用Handler
}

// 正确：使用弱引用或解耦
```

---

## 性能优化

### 减少不必要的渲染

```typescript
// 使用@ObjectLink精确更新
@Observed
class Item {
  @Track name: string;  // 仅name变化时更新
  @Track value: number;
}
```

### 懒加载

```typescript
List() {
  LazyForEach(this.dataSource, (item) => {
    ListItem() { /* ... */ }
  })
}
.cachedCount(5)  // 合理设置缓存
```

---

## 错误处理

### try-catch

```typescript
Button('Load')
  .onClick(() => {
    try {
      this.loadData();
    } catch (error) {
      console.error(`Error: ${error.message}`);
      this.uiContext.getPromptAction().showToast({ message: '加载失败' });
    }
  })
```

### 空值检查

```typescript
// 使用可选链
let value = this.obj?.nested?.value;

// 使用空值合并
let name = this.name ?? 'Default';
```