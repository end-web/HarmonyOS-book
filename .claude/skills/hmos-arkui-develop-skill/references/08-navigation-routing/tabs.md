## Tabs 选项卡

### 基本使用

```typescript
Tabs() {
  TabContent() {
    Text('首页内容')
  }
  .tabBar('首页')

  TabContent() {
    Text('发现内容')
  }
  .tabBar('发现')

  TabContent() {
    Text('我的内容')
  }
  .tabBar('我的')
}
.barPosition(BarPosition.End)  // 底部导航
.scrollable(true)              // 可滑动切换
.onChange((index: number) => {
  console.info(`切换到: ${index}`);
})
```

### 导航栏位置

| barPosition       | 说明     |
| ----------------- | -------- |
| BarPosition.Start | 顶部导航 |
| BarPosition.End   | 底部导航 |

```typescript
// 顶部导航
Tabs({ barPosition: BarPosition.Start })

// 底部导航
Tabs({ barPosition: BarPosition.End })

// 侧边导航
Tabs()
.vertical(true)
.barWidth(100)
```

### 导航栏模式

| barMode            | 说明                 |
| ------------------ | -------------------- |
| BarMode.Fixed      | 固定导航栏，均分宽度 |
| BarMode.Scrollable | 可滚动导航栏         |

```typescript
Tabs()
.barMode(BarMode.Scrollable)  // 可滚动
```

### 自定义页签

```typescript
@State currentIndex: number = 0;

@Builder
tabBuilder(title: string, index: number) {
  Column() {
    Image(this.currentIndex === index ? $r('app.media.icon_sel') : $r('app.media.icon'))
    Text(title)
      .fontColor(this.currentIndex === index ? '#007DFF' : '#666666')
  }
}

Tabs() {
  TabContent() { Text('首页') }
    .tabBar(this.tabBuilder('首页', 0))
  
  TabContent() { Text('我的') }
    .tabBuilder(this.tabBuilder('我的', 1))
}
.onSelected((index: number) => {
  this.currentIndex = index;
})
```

### 底部页签样式

```typescript
TabContent() { }
.tabBar(new BottomTabBarStyle($r('app.media.icon'), '首页'))
```

### 切换指定页签

```typescript
private controller: TabsController = new TabsController();

Tabs({ controller: this.controller }) { }

// 切换到指定索引
this.controller.changeIndex(2);
```

---