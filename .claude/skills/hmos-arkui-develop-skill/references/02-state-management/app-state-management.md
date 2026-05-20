# 应用级状态管理

跨页面、跨组件的全局状态管理方案。

## 概述

| 方案 | 作用范围 | V1 | V2 |
|-----|---------|----|----|
| AppStorage | 应用全局 | ✓ | ✓ |
| LocalStorage | 页面级 | ✓ | - |
| PersistentStorage | 持久化 | ✓ | - |
| AppStorageV2 | 应用全局 | - | ✓ |
| PersistenceV2 | 持久化 | - | ✓ |

---

## 一、AppStorage（应用全局状态）

应用启动时创建的单例，与应用进程绑定，支持跨UIAbility共享。

### @StorageProp：单向同步

AppStorage → 组件单向同步。本地修改不同步回AppStorage。

```typescript
AppStorage.setOrCreate('userName', 'Tom');

@Entry
@Component
struct Page {
  @StorageProp('userName') userName: string = '';
  
  build() {
    Column() {
      Text(this.userName)
      Button('修改')
        .onClick(() => {
          this.userName = 'Jerry';  // 仅本地修改
        })
    }
  }
}
```

### @StorageLink：双向同步

AppStorage ↔ 组件双向同步。修改同步到所有绑定组件。

```typescript
AppStorage.setOrCreate('count', 0);

@Entry
@Component
struct Page {
  @StorageLink('count') count: number = 0;
  
  build() {
    Column() {
      Text(`${this.count}`)
      Button('+1')
        .onClick(() => this.count++)  // 全局同步
    }
  }
}
```

### 多页面共享

```typescript
// 页面A
@StorageLink('token') token: string = '';

// 页面B（共享同一数据）
@StorageLink('token') token: string = '';
```

### API使用

```typescript
// 设置/创建
AppStorage.setOrCreate('key', 'value');

// 获取
const value = AppStorage.get<string>('key');

// 创建链接
const link = AppStorage.link<number>('count');
link.set(10);

// 删除
AppStorage.delete('key');

// 清空
AppStorage.clear();
```

---

## 二、LocalStorage（页面级状态）

页面级的状态共享，可创建多个实例，通常用于页面级数据共享。

### 基本用法

```typescript
let storage = new LocalStorage();
storage.setOrCreate('pageTitle', 'Home');

@Entry(storage)
@Component
struct Page {
  @LocalStorageLink('pageTitle') title: string = '';
  @LocalStorageProp('readOnly') readOnly: boolean = false;
  
  build() {
    Column() {
      Text(this.title)
    }
  }
}
```

### 页面间隔离

每个LocalStorage实例独立，不同页面可使用不同实例。

---

## 三、PersistentStorage（持久化存储）

将数据持久化到磁盘，应用重启后仍可读取。

### 基本用法

```typescript
// 持久化属性
PersistentStorage.persistProp('theme', 'light');
PersistentStorage.persistProps([
  { key: 'fontSize', defaultValue: 14 }
]);

// 使用（通过AppStorage）
@StorageLink('theme') theme: string = 'light';
```

### 注意事项

1. **调用顺序**：先PersistentStorage，再AppStorage
2. **类型限制**：简单类型建议持久化，复杂类型慎重
3. **存储限制**：不宜存储大量数据

---

## 四、Environment（环境变量）

获取系统环境信息，写入AppStorage，只读。

### 基本用法

```typescript
Environment.envProp('languageCode', 'en');
Environment.envProp('colorMode', 'light');

@StorageProp('languageCode') language: string = 'en';
@StorageProp('colorMode') colorMode: string = 'light';
```

### 预置环境变量

| 变量名 | 说明 |
|-------|------|
| languageCode | 系统语言 |
| colorMode | 深浅色模式 |

---

## 五、AppStorageV2（V2全局状态）

V2版本的应用全局状态，类型安全，配合@ObservedV2使用。

### 基本用法

```typescript
import { AppStorageV2 } from '@kit.ArkUI';

@ObservedV2
class AppConfig {
  @Trace theme: string = 'light';
  @Trace fontSize: number = 14;
}

@Entry
@ComponentV2
struct App {
  @Local config: AppConfig = AppStorageV2.connect(
    AppConfig, 
    () => new AppConfig()
  )!;
  
  build() {
    Column() {
      Text(`Theme: ${this.config.theme}`)
        .onClick(() => {
          this.config.theme = 'dark';  // 全局同步
        })
    }
  }
}
```

---

## 六、PersistenceV2（V2持久化）

独立的持久化能力，不依赖AppStorage。

### 基本用法

```typescript
import { PersistenceV2 } from '@kit.ArkUI';

let persistence = new PersistenceV2('myApp');

// 存取数据
persistence.set('key', 'value');
let value = persistence.get('key');
persistence.delete('key');
```

---

## 使用建议

### 场景选择

| 场景 | 推荐方案 |
|-----|---------|
| 跨页面共享状态 | AppStorage / AppStorageV2 |
| 页面内组件共享 | LocalStorage |
| 需要持久化 | PersistentStorage / PersistenceV2 |
| 获取系统环境 | Environment |
| 不涉及UI的数据 | 用户首选项 |

### 最佳实践

1. **事件通知**：用emitter而非@StorageLink
2. **数据分离**：不涉及UI的数据用用户首选项
3. **类型一致**：变量类型应与存储中类型一致
4. **调用顺序**：PersistentStorage → AppStorage → Environment