# 声明式UI描述

## 创建组件

### 无参数组件
```typescript
Column() {
  Divider()  // 无需配置参数
}
```

### 有参数组件
```typescript
// 必选参数
Image('https://xyz/test.jpg')

// 可选参数
Text('test')
Text($r('app.string.title_value'))  // 资源引用
Text()  // 无参数

// 变量或表达式
Image(this.imagePath)
Text(`count: ${this.count}`)
```

## 配置属性

属性方法以`.`链式调用，建议每个属性单独一行。

```typescript
Text('test')
  .fontSize(12)

Image('test.jpg')
  .alt('error.jpg')
  .width(100)
  .height(100)

// 使用枚举类型
Text('hello')
  .fontSize(20)
  .fontColor(Color.Red)
  .fontWeight(FontWeight.Bold)
```

## 配置事件

事件方法以`.`链式调用。

```typescript
// 箭头函数
Button('Click me')
  .onClick(() => {
    this.myText = 'ArkUI';
  })

// 声明的箭头函数（无需bind this）
fn = () => {
  this.counter++;
};
Button('add counter')
  .onClick(this.fn)
```

> 注意：箭头函数内部的`this`是词法作用域，匿名函数可能指向不明确，ArkTS中不允许使用。

## 配置子组件

容器组件支持在尾随闭包`{...}`中配置子组件。

```typescript
Column() {
  Text('Hello')
    .fontSize(100)
  Divider()
  Text(this.myText)
    .fontSize(100)
    .fontColor(Color.Red)
}

// 多级嵌套
Column() {
  Row() {
    Image('test1.jpg')
      .width(100)
    Button('click +1')
      .onClick(() => { })
  }
}
```

## 常用容器组件

| 组件 | 说明 |
|-----|------|
| Column | 纵向布局容器 |
| Row | 横向布局容器 |
| Stack | 栈布局容器 |
| Grid | 网格容器 |
| List | 列表容器 |
| Flex | 弹性布局容器 |