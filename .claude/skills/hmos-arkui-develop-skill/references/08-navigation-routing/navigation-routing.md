## 概述

ArkUI提供两种页面路由方案：

| 方案 | 说明 | 推荐程度 |
|-----|------|---------|
| Navigation | 组件导航，功能强大，支持灵活页面栈操作 | **推荐** |
| Router | 页面路由，传统路由方案 | 不推荐 |

**Navigation优势**：
- 一次开发多端部署（自动适配单栏/双栏）
- 灵活的页面栈操作
- 丰富的转场动画和生命周期
- 支持路由拦截
- 支持模态嵌套路由

---

## Navigation组件

### 基本使用

```typescript
@Entry
@Component
struct MainPage {
  pageStack: NavPathStack = new NavPathStack();

  build() {
    Navigation(this.pageStack) {
      Column() {
        Button('跳转详情')
          .onClick(() => {
            this.pageStack.pushPathByName('DetailPage', { id: 1 });
          })
      }
    }
    .mode(NavigationMode.Stack)
    .title('主页')
  }
}
```

### NavigationMode

| 模式 | 说明 |
|-----|------|
| Stack | 单页面模式，页面堆叠 |
| Split | 分栏模式，左侧导航+右侧内容 |
| Auto | 自动模式，根据设备宽度自适应 |

---

## NavPathStack 路由操作

### 页面跳转

```typescript
// 普通跳转
this.pageStack.pushPath({ name: 'pageOne', param: { id: 1 } });
this.pageStack.pushPathByName('pageTwo', '参数');

// 带返回回调
this.pageStack.pushPathByName('pageTwo', 'param', (popInfo) => {
  console.info(`返回: ${popInfo.result}`);
});

// 带错误处理
this.pageStack.pushDestination({ name: 'pageTwo' })
  .then(() => console.info('跳转成功'))
  .catch((err) => console.error(`跳转失败: ${err.code}`));
```

### 页面返回

```typescript
// 返回上一页
this.pageStack.pop();

// 返回指定页面
this.pageStack.popToName('pageOne');

// 返回指定索引
this.pageStack.popToIndex(0);

// 清空页面栈，返回首页
this.pageStack.clear();
```

### 页面替换

```typescript
// 替换栈顶页面
this.pageStack.replacePath({ name: 'pageTwo', param: 'param' });
this.pageStack.replacePathByName('pageTwo', 'param');
```

### 页面删除

```typescript
// 删除指定名称的所有页面
this.pageStack.removeByName('pageTwo');

// 删除指定索引的页面
this.pageStack.removeByIndexes([1, 2]);

// 删除指定ID的页面
this.pageStack.removeByNavDestinationId('id');
```

### 页面移动

```typescript
// 移动指定页面到栈顶
this.pageStack.moveToTop('pageTwo');

// 移动指定索引页面到栈顶
this.pageStack.moveIndexToTop(1);
```

### 参数获取

```typescript
// 获取所有页面名称
this.pageStack.getAllPathName();

// 获取指定索引的参数
this.pageStack.getParamByIndex(1);

// 获取指定名称的参数
this.pageStack.getParamByName('pageOne');

// 获取指定名称的索引
this.pageStack.getIndexByName('pageOne');

// 获取完整路由栈
this.pageStack.getPathStack();
```

### 单例跳转

```typescript
// 移动到栈顶（已存在则移动，不存在则新建）
this.pageStack.pushPathByName('pageOne', null, false, LaunchMode.MOVE_TO_TOP_SINGLETON);

// 弹出到该页面（移除上方所有页面）
this.pageStack.pushPathByName('pageOne', null, false, LaunchMode.POP_TO_SINGLETON);
```

### 路由拦截

```typescript
this.pageStack.setInterception({
  willShow: (from, to, operation, animated) => {
    if (typeof to !== 'string' && to.pathInfo.name === 'pageTwo') {
      // 拦截跳转到pageTwo，重定向到pageOne
      to.pathStack.pop();
      to.pathStack.pushPathByName('pageOne', null);
    }
  },
  didShow: (from, to, operation, animated) => {
    // 页面显示后回调
  }
});
```

---

## NavDestination 子页面

### 基本使用

```typescript
@Builder
export function PageOneBuilder(name: string, param: Object) {
  PageOne({ name: name, param: param });
}

@Component
export struct PageOne {
  pathStack: NavPathStack = new NavPathStack();
  name: string = '';
  param: Object = {};

  build() {
    NavDestination() {
      Column() {
        Text(`页面: ${this.name}`)
        Text(`参数: ${JSON.stringify(this.param)}`)
        Button('返回')
          .onClick(() => this.pathStack.pop())
      }
    }
    .title(this.name)
    .onReady((ctx: NavDestinationContext) => {
      this.pathStack = ctx.pathStack;
      this.param = ctx.pathInfo.param;
    })
  }
}
```

### 页面显示类型

```typescript
// 标准类型（默认）
NavDestination() { }
.mode(NavDestinationMode.STANDARD)

// 弹窗类型（透明显示）
NavDestination() { }
.mode(NavDestinationMode.DIALOG)
.hideTitleBar(true)
.backgroundColor('rgba(0,0,0,0.5)')
```

### 页面生命周期

| 生命周期 | 触发时机 |
|---------|---------|
| aboutToAppear | 组件创建后，build之前 |
| onWillAppear | 页面挂载到组件树之前 |
| onAppear | 页面挂载到组件树时 |
| onWillShow | 页面即将显示时 |
| onShown | 页面显示完成时 |
| onActive | 页面激活（栈顶可操作）时 |
| onWillHide | 页面即将隐藏时 |
| onInactive | 页面非激活时 |
| onHidden | 页面隐藏后 |
| onWillDisappear | 页面即将销毁时 |
| onDisAppear | 页面从组件树卸载时 |
| aboutToDisappear | 组件销毁前 |

```typescript
NavDestination() { }
.onWillAppear(() => console.info('即将显示'))
.onShown(() => console.info('显示完成'))
.onHidden(() => console.info('已隐藏'))
```

### 返回参数处理

```typescript
NavDestination() { }
.onResult((param: Object) => {
  console.info(`收到返回参数: ${JSON.stringify(param)}`);
})

// 返回时传递参数
this.pathStack.pop({ result: '返回数据' });
```

### 页面信息查询

```typescript
@Component
struct MyComponent {
  aboutToAppear() {
    let info = this.queryNavDestinationInfo();
    console.info(`页面名称: ${info?.name}`);
  }
}
```

---

## 路由表配置

### 系统路由表

在 `entry/src/main/resources/base/profile/router_map.json` 中配置：

```json
{
  "routerMap": [
    {
      "name": "pageOne",
      "pageSourceFile": "src/main/ets/pages/PageOne.ets",
      "buildFunction": "PageOneBuilder"
    },
    {
      "name": "pageTwo",
      "pageSourceFile": "src/main/ets/pages/PageTwo.ets",
      "buildFunction": "PageTwoBuilder"
    }
  ]
}
```

在 `module.json5` 中注册：

```json
{
  "module": {
    "routerMap": "$profile:router_map"
  }
}
```

## 分栏导航

```typescript
Navigation(this.pageStack) {
  // 右侧内容区
}
.mode(NavigationMode.Split)
.navContentWidth(240)  // 左侧导航栏宽度
.title('设置')
```

---

## 跨包导航

### 跳转HAR/HSP页面

```typescript
// Navigation方式
this.pageStack.pushPathByName('ExternalPage', null);

// Router方式
router.pushUrl({
  url: '@bundle/com.example.library/ets/pages/Page'
});
```

### 命名路由

```typescript
// 共享包中定义
@Entry({ routeName: 'myPage' })
@Component
struct MyPage { }

// 跳转
router.pushNamedRoute({ name: 'myPage' });
```

---

## 导航栏配置

### 标题栏

```typescript
Navigation(this.pageStack) { }
.title('页面标题')
.titleMode(NavigationTitleMode.Mini)
.hideTitleBar(false)
```

### 菜单项

```typescript
Navigation(this.pageStack) { }
.menuItems([
  { value: $r('app.media.icon'), action: () => {} }
])
```

### 工具栏

```typescript
Navigation(this.pageStack) { }
.toolbarConfiguration([
  { value: '首页', action: () => {} },
  { value: '我的', action: () => {} }
])
.hideToolBar(false)
```

### 隐藏导航栏

```typescript
Navigation(this.pageStack) { }
.hideNavBar(true)
.hideTitleBar(true)
.hideToolBar(true)
```

---

## 页面转场动画

### 自定义转场

```typescript
NavDestination() { }
.transition(TransitionEffect.OPACITY)
```

### 共享元素转场

```typescript
// 页面A
Image($r('app.media.pic'))
  .geometryTransition('shared_image')

// 页面B
Image($r('app.media.pic'))
  .geometryTransition('shared_image')
```

---

## 最佳实践

1. **优先使用Navigation**：功能更强大，支持灵活路由操作
2. **使用系统路由表**：统一管理页面路由
3. **合理设置页面栈**：避免页面栈过深，及时清理
4. **使用路由拦截**：实现权限控制、页面重定向