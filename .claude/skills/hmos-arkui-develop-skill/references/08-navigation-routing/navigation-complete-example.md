# Navigation页面跳转完整示例

## 一、开发步骤

### 步骤1：创建导航根容器
创建Navigation组件作为根容器，并创建NavPathStack对象绑定到Navigation。

### 步骤2：创建子页面
使用NavDestination组件创建子页面，并导出Builder函数用于路由注册。

### 步骤3：配置系统路由表
创建router_map.json文件，注册页面名称与Builder函数的映射关系。

### 步骤4：注册路由表
在module.json5中注册路由表配置文件。

### 步骤5：实现页面跳转
通过NavPathStack的方法实现页面跳转、返回等操作。

---

## 二、完整工程示例

### 2.1 工程目录结构

```
entry/
├── src/
│   └── main/
│       ├── ets/
│       │   ├── entryability/
│       │   │   └── EntryAbility.ets          # 应用入口
│       │   └── pages/
│       │       ├── Index.ets                  # 导航首页
│       │       ├── PageOne.ets                # 子页面1
│       │       └── PageTwo.ets                # 子页面2
│       ├── resources/
│       │   └── base/
│       │       ├── element/
│       │       │   └── string.json            # 字符串资源
│       │       └── profile/
│       │           └── router_map.json        # 路由表配置
│       └── module.json5                        # 模块配置文件
```

---

### 2.2 完整代码文件

#### (1) 导航首页 - Index.ets

```typescript
import { hilog } from '@kit.PerformanceAnalysisKit';

const DOMAIN = 0x0000;
const TAG = 'NavigationDemo';

@Entry
@Component
struct Index {
  pageStack: NavPathStack = new NavPathStack();

  build() {
    Navigation(this.pageStack) {
      Column() {
        Text('首页')
          .fontSize(24)
          .fontWeight(FontWeight.Bold)
          .margin({ bottom: 30 })

        Button('跳转到页面One（普通跳转）')
          .width('80%')
          .margin({ bottom: 15 })
          .onClick(() => {
            this.pageStack.pushPathByName('PageOne', { id: 1, name: '来自首页的参数' });
          })

        Button('跳转到页面Two（带返回回调）')
          .width('80%')
          .margin({ bottom: 15 })
          .onClick(() => {
            this.pageStack.pushPathByName('PageTwo', '参数数据', (popInfo) => {
              hilog.info(DOMAIN, TAG, `收到返回数据: ${JSON.stringify(popInfo.result)}`);
            });
          })

        Button('跳转到页面One（带错误处理）')
          .width('80%')
          .margin({ bottom: 15 })
          .onClick(() => {
            this.pageStack.pushDestinationByName('PageOne', { id: 2, name: '异步跳转参数' })
              .then(() => {
                hilog.info(DOMAIN, TAG, '跳转成功');
              })
              .catch((err: Error) => {
                hilog.error(DOMAIN, TAG, `跳转失败: ${err.message}`);
              });
          })

        Button('清空页面栈返回首页')
          .width('80%')
          .onClick(() => {
            this.pageStack.clear();
          })
      }
      .width('100%')
      .height('100%')
      .justifyContent(FlexAlign.Center)
    }
    .mode(NavigationMode.Stack)
    .title('Navigation示例')
    .titleMode(NavigationTitleMode.Mini)
  }
}
```

---

#### (2) 子页面1 - PageOne.ets

```typescript
import { hilog } from '@kit.PerformanceAnalysisKit';

const DOMAIN = 0x0000;
const TAG = 'PageOne';

interface PageParams {
  id?: number;
  name?: string;
}

@Builder
export function PageOneBuilder(name: string, param: Object) {
  PageOne({ name: name, param: param as PageParams });
}

@Component
export struct PageOne {
  pathStack: NavPathStack = new NavPathStack();
  name: string = '';
  param: PageParams = {};
  @State message: string = '';

  build() {
    NavDestination() {
      Column() {
        Text(`页面名称: ${this.name}`)
          .fontSize(22)
          .fontWeight(FontWeight.Bold)
          .margin({ bottom: 20 })

        Text(`接收参数: ${JSON.stringify(this.param)}`)
          .fontSize(16)
          .margin({ bottom: 20 })

        Text(`${this.message}`)
          .fontSize(16)
          .fontColor('#666666')
          .margin({ bottom: 20 })

        Button('跳转到PageTwo')
          .width('70%')
          .margin({ bottom: 15 })
          .onClick(() => {
            this.pathStack.pushPathByName('PageTwo', { from: 'PageOne' });
          })

        Button('返回上一页')
          .width('70%')
          .margin({ bottom: 15 })
          .onClick(() => {
            this.pathStack.pop({ result: '来自PageOne的返回数据' });
          })

        Button('返回到首页')
          .width('70%')
          .onClick(() => {
            this.pathStack.clear();
          })
      }
      .width('100%')
      .height('100%')
      .justifyContent(FlexAlign.Center)
    }
    .title('页面One')
    .onReady((ctx: NavDestinationContext) => {
      this.pathStack = ctx.pathStack;
      this.param = ctx.pathInfo.param as PageParams;
      this.message = `参数ID: ${this.param?.id}, 名称: ${this.param?.name}`;
      hilog.info(DOMAIN, TAG, `onReady, param: ${JSON.stringify(this.param)}`);
    })
    .onResult((param: Object) => {
      hilog.info(DOMAIN, TAG, `收到返回参数: ${JSON.stringify(param)}`);
    })
    .onShown(() => {
      hilog.info(DOMAIN, TAG, '页面显示');
    })
    .onHidden(() => {
      hilog.info(DOMAIN, TAG, '页面隐藏');
    })
  }
}
```

---

#### (3) 子页面2 - PageTwo.ets

```typescript
import { hilog } from '@kit.PerformanceAnalysisKit';

const DOMAIN = 0x0000;
const TAG = 'PageTwo';

interface PageParams {
  from?: string;
}

@Builder
export function PageTwoBuilder(name: string, param: Object) {
  PageTwo({ name: name, param: param as PageParams });
}

@Component
export struct PageTwo {
  pathStack: NavPathStack = new NavPathStack();
  name: string = '';
  param: PageParams = {};

  build() {
    NavDestination() {
      Column() {
        Text(`页面名称: ${this.name}`)
          .fontSize(22)
          .fontWeight(FontWeight.Bold)
          .margin({ bottom: 20 })

        Text(`接收参数: ${JSON.stringify(this.param)}`)
          .fontSize(16)
          .margin({ bottom: 30 })

        Button('返回并传递数据')
          .width('70%')
          .margin({ bottom: 15 })
          .onClick(() => {
            this.pathStack.pop({ result: '来自PageTwo的返回数据', code: 200 });
          })

        Button('返回到PageOne')
          .width('70%')
          .margin({ bottom: 15 })
          .onClick(() => {
            this.pathStack.popToName('PageOne');
          })

        Button('返回到首页（清空栈）')
          .width('70%')
          .onClick(() => {
            this.pathStack.popToIndex(0);
          })
      }
      .width('100%')
      .height('100%')
      .justifyContent(FlexAlign.Center)
    }
    .title('页面Two')
    .backgroundColor('#f5f5f5')
    .onReady((ctx: NavDestinationContext) => {
      this.pathStack = ctx.pathStack;
      this.param = ctx.pathInfo.param as PageParams;
      hilog.info(DOMAIN, TAG, `onReady, param: ${JSON.stringify(this.param)}`);
    })
    .onShown(() => {
      hilog.info(DOMAIN, TAG, '页面显示');
    })
  }
}
```

---

### 2.3 配置文件（重要）

#### (1) 路由表配置 - router_map.json

**文件路径**: `entry/src/main/resources/base/profile/router_map.json`

```json
{
  "routerMap": [
    {
      "name": "PageOne",
      "pageSourceFile": "src/main/ets/pages/PageOne.ets",
      "buildFunction": "PageOneBuilder"
    },
    {
      "name": "PageTwo",
      "pageSourceFile": "src/main/ets/pages/PageTwo.ets",
      "buildFunction": "PageTwoBuilder"
    }
  ]
}
```

**配置说明**：
- `name`: 页面名称，用于路由跳转时的唯一标识
- `pageSourceFile`: 页面源文件的相对路径（相对于模块根目录）
- `buildFunction`: 页面的Builder函数名称，必须与页面中导出的@Builder函数名一致

---

#### (2) 模块配置文件 - module.json5

**文件路径**: `entry/src/main/module.json5`

```json
{
  "module": {
    "name": "entry",
    "type": "entry",
    "description": "$string:module_desc",
    "mainElement": "EntryAbility",
    "deviceTypes": [
      "phone",
      "tablet",
      "2in1"
    ],
    "deliveryWithInstall": true,
    "installationFree": false,
    "pages": "$profile:main_pages",
    "abilities": [
      {
        "name": "EntryAbility",
        "srcEntry": "./ets/entryability/EntryAbility.ets",
        "description": "$string:EntryAbility_desc",
        "icon": "$media:layered_image",
        "label": "$string:EntryAbility_label",
        "startWindowIcon": "$media:startIcon",
        "startWindowBackground": "$color:start_window_background",
        "exported": true,
        "skills": [
          {
            "entities": [
              "entity.system.home"
            ],
            "actions": [
              "action.system.home"
            ]
          }
        ]
      }
    ],
    "routerMap": "$profile:router_map"
  }
}
```

**关键配置说明**：
- **`"routerMap": "$profile:router_map"`**: 此行必须添加在`module`字段中，用于注册路由表配置文件
- `$profile:router_map` 表示引用 `resources/base/profile/` 目录下的 `router_map.json` 文件

---

#### (3) 字符串资源文件 - string.json

**文件路径**: `entry/src/main/resources/base/element/string.json`

```json
{
  "string": [
    {
      "name": "module_desc",
      "value": "Navigation示例模块"
    },
    {
      "name": "EntryAbility_desc",
      "value": "Navigation示例入口"
    },
    {
      "name": "EntryAbility_label",
      "value": "NavigationDemo"
    }
  ]
}
```

---

#### (4) 页面路由配置 - main_pages.json

**文件路径**: `entry/src/main/resources/base/profile/main_pages.json`

```json
{
  "src": [
    "pages/Index"
  ]
}
```

---

## 三、路由操作详解

### 3.1 页面跳转方式

```typescript
// 方式1: pushPath - 通过路径对象跳转
this.pageStack.pushPath({ name: 'PageOne', param: { id: 1 } });

// 方式2: pushPathByName - 通过页面名称跳转（推荐）
this.pageStack.pushPathByName('PageOne', { id: 1, name: '参数' });

// 方式3: pushDestinationByName - 带错误处理的异步跳转
this.pageStack.pushDestinationByName('PageOne', '参数')
  .then(() => console.log('成功'))
  .catch(err => console.error(err));

// 方式4: 带返回回调的跳转
this.pageStack.pushPathByName('PageTwo', '参数', (popInfo) => {
  console.log('返回数据:', popInfo.result);
});
```

### 3.2 页面返回方式

```typescript
// 返回上一页（不传参）
this.pathStack.pop();

// 返回上一页（传递参数）
this.pathStack.pop({ result: '返回数据', code: 200 });

// 返回到指定名称的页面
this.pathStack.popToName('PageOne');

// 返回到指定索引的页面
this.pathStack.popToIndex(0);

// 清空页面栈，返回首页
this.pathStack.clear();
```

### 3.3 页面替换

```typescript
// 替换栈顶页面
this.pageStack.replacePathByName('PageTwo', '新参数');
```

### 3.4 获取路由信息

```typescript
// 获取所有页面名称
let names = this.pageStack.getAllPathName();

// 获取指定索引的参数
let param = this.pageStack.getParamByIndex(1);

// 获取指定名称的参数
let param = this.pageStack.getParamByName('PageOne');

// 获取指定名称的索引
let index = this.pageStack.getIndexByName('PageOne');
```

---

## 四、常见问题

### Q1: 跳转失败，页面不显示？
检查以下几点：
1. `router_map.json` 文件是否创建在正确路径 `resources/base/profile/`
2. `module.json5` 中是否添加了 `"routerMap": "$profile:router_map"`
3. 页面中的 `@Builder` 函数是否正确导出
4. `buildFunction` 名称是否与 `@Builder` 函数名一致

### Q2: 参数传递后获取不到？
确保在 `onReady` 回调中获取参数：
```typescript
.onReady((ctx: NavDestinationContext) => {
  this.param = ctx.pathInfo.param;
})
```

### Q3: 返回参数如何接收？
方式1：在跳转时设置回调
```typescript
this.pageStack.pushPathByName('PageTwo', null, (popInfo) => {
  console.log(popInfo.result);
});
```

方式2：在 NavDestination 中设置 onResult
```typescript
NavDestination() { }
.onResult((param) => {
  console.log(param);
})
```

---

## 五、生命周期

| 生命周期 | 触发时机 | 用途 |
|---------|---------|------|
| onReady | 页面创建时 | 获取路由参数和NavPathStack |
| onWillAppear | 页面即将显示 | 准备数据 |
| onShown | 页面显示完成 | 执行动画、刷新数据 |
| onHidden | 页面隐藏 | 暂停操作 |
| onResult | 收到返回参数 | 处理返回数据 |