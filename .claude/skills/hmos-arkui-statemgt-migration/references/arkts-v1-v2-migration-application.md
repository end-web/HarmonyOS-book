# 应用内状态变量迁移

## 目录

- [LocalStorage → @ObservedV2/@Trace](#localstorage-observedv2trace)
  - [基本场景](#基本场景)
  - [@LocalStorageProp效果实现](#localstorageprop效果实现)
  - [多实例场景](#多实例场景localstorage的迁移)
- [AppStorage → AppStorageV2](#appstorage-appstoragev2)
  - [@StorageLink迁移](#storagelink迁移)
  - [@StorageProp迁移](#storageprop迁移)
- [Environment → UIAbilityContext.config](#environment-uiabilitycontextconfig)
- [PersistentStorage → PersistenceV2](#persistentstorage-persistencev2)

---

## LocalStorage → @ObservedV2/@Trace

### 基本场景

```typescript
// V1 - LocalStorage
export default class EntryAbility extends UIAbility {
  public storage: LocalStorage = new LocalStorage({ 'count': 47 });
  onWindowStageCreate(windowStage: window.WindowStage): void {
    windowStage.loadContent('pages/Page1', this.storage);
  }
}

// Page1.ets
@Entry({ useSharedStorage: true })
@Component
struct Page1 {
  @LocalStorageLink('count') count: number = 0;
  build() { Text(`${this.count}`).onClick(() => { this.count++; }) }
}

// V2 - @ObservedV2单例
@ObservedV2
export class MyStorage {
  public static singleton_: MyStorage;
  static instance() {
    if (!MyStorage.singleton_) {
      MyStorage.singleton_ = new MyStorage();
    }
    return MyStorage.singleton_;
  }
  @Trace public count: number = 47;
}

// Page1.ets
@Entry
@ComponentV2
struct Page1 {
  storage: MyStorage = MyStorage.instance();
  build() { Text(`${this.storage.count}`).onClick(() => { this.storage.count++; }) }
}
```

### @LocalStorageProp效果实现

单向接收，本地修改不同步回LocalStorage：

```typescript
// V1 - @LocalStorageProp
@Entry(storage)
@Component
struct Page1 {
  @LocalStorageProp('count') count: number = 0;
  build() {
    Column() {
      Text(`${this.count}`).onClick(() => { this.count++; })  // 仅本地生效
      Button('change Storage Count').onClick(() => {
        storage.setOrCreate('count', storage.get<number>('count') as number + 100);
      })
    }
  }
}

// V2 - @Local + @Monitor
@Entry
@ComponentV2
struct Page1 {
  storage: MyStorage = MyStorage.instance();
  @Local count: number = this.storage.count;

  @Monitor('storage.count')
  onCountChange(mon: IMonitor) {
    this.count = this.storage.count;  // 监听全局变化
  }

  build() {
    Column() {
      Text(`${this.count}`).onClick(() => { this.count++; })  // 仅本地生效
      Button('change Storage Count').onClick(() => { this.storage.count += 100; })
    }
  }
}
```

### 多实例场景LocalStorage的迁移

```typescript
// V1 - 多Ability共享
let localStorage = new LocalStorage();
localStorage.setOrCreate('key', 'value');

// V2 - @ObservedV2 + Map
@ObservedV2
export default class PDFData {
  private static instance_: PDFData | null = null;
  @Trace private data: Map<string, string> = new Map();
  @Trace private flag: string = '';

  static getInstance(): PDFData {
    if (!PDFData.instance_) {
      PDFData.instance_ = new PDFData();
    }
    return PDFData.instance_;
  }

  setData(key: string, value: string) { this.data.set(key, value); }
  getData() { return this.data; }
  setFlage(value: string) { this.flag = value; }
  getFlag() { return this.flag; }
}

// 在Ability中使用
export default class PDFAbility extends UIAbility {
  onWindowStageCreate(windowStage: window.WindowStage): void {
    const data = this.launchWant.parameters as Record<string, string>;
    PDFData.getInstance().setData(data.key, data.value);
    PDFData.getInstance().setFlage(this.launchWant.uri || '');
    windowStage.loadContent('pages/PDF');
  }
}
```

---

## AppStorage → AppStorageV2

### AppStorage.setorCreate迁移

```typescript
// v1
AppStorage.setOrCreate('enableDarkMode', this.enableDarkMode);

//v2
// 1.先创建一个stoarge类
@ObservedV2
class MyStorage {
  @Trace count: number = 0;
}

// 然后通过connect存储一个storage
AppStorageV2.connect(MyStorage, 'storage', () => new MyStorage())

```

注意：AppstoageV2没有setorCreate方法，需要进行迁移

### @StorageLink迁移

双向同步AppStorage数据：

1、先创建一个storage类，通过storage类保存storagelink装饰的变量，

2、再从Appstorage内取出对应的类，使用storage访问对应的变量如count

```typescript
// V1
@Entry
@Component
struct Page {
  @StorageLink('count') count: number = 0;
  build() { Button(`${this.count}`).onClick(() => this.count++) }
}

// V2
import { AppStorageV2 } from '@kit.ArkUI';

// 先创建一个类，通过类保存对应的变量
@ObservedV2
class MyStorage {
  @Trace count: number = 0;
}

// 再通过Local取出对应的storage类，从storage再取出count
@Entry
@ComponentV2
struct Page {
  @Local storage: MyStorage = AppStorageV2.connect(MyStorage, 'storage', () => new MyStorage())!;
  build() { Button(`${this.storage.count}`).onClick(() => this.storage.count++) }
}
```

### @StorageProp迁移

单向接收，本地修改不同步回AppStorage：

1、先创建一个storage类，通过storage类保存storagelink装饰的变量，

2、创建一个count用local接受，

3、通过monitor把storage.count的变化传递给count

```typescript
// V1
@Entry
@Component
struct Page {
  @StorageProp('count') count: number = 0;
  build() {
    Column() {
      Text(`${this.count}`).onClick(() => this.count++)  // 仅本地生效
      Button('全局+100').onClick(() => AppStorage.setOrCreate('count', AppStorage.get('count') + 100))
    }
  }
}

// V2 - @Local + @Monitor
@ObservedV2
class MyStorage {
  @Trace count: number = 0;
}

@Entry
@ComponentV2
struct Page {
  @Local storage: MyStorage = AppStorageV2.connect(MyStorage, 'storage', () => new MyStorage())!;
  @Local count: number = this.storage.count;

  @Monitor('storage.count')
  onCountChange(mon: IMonitor) {
    this.count = this.storage.count;
  }

  build() {
    Column() {
      Text(`${this.count}`).onClick(() => this.count++)  // 仅本地生效
      Button('全局+100').onClick(() => this.storage.count += 100)
    }
  }
}
```

---

## Environment → UIAbilityContext.config

```typescript
// V1
Environment.envProp('languageCode', 'en');
@Entry
@Component
struct Index {
  @StorageProp('languageCode') languageCode: string = 'en';
  build() { Text(this.languageCode) }
}

// V2 - 直接从config获取
export class Env {
  public language: string | undefined;
  public colorMode: ConfigurationConstant.ColorMode | undefined;
  public fontSizeScale: number | undefined;
  public fontWeightScale: number | undefined;
}

export let env: Env = new Env();

// 在Ability的onCreate中赋值
export default class EntryAbility extends UIAbility {
  onCreate(want: Want, launchParam: AbilityConstant.LaunchParam): void {
    env.language = this.context.config.language;
    env.colorMode = this.context.config.colorMode;
    env.fontSizeScale = this.context.config.fontSizeScale;
    env.fontWeightScale = this.context.config.fontWeightScale;
  }
}

// 在页面中使用
@Entry
@ComponentV2
struct Index {
  build() {
    Column() {
      Text(`languageCode: ${env.language}`)
      Text(`colorMode: ${env.colorMode}`)
    }
  }
}
```

---

## PersistentStorage → PersistenceV2

```typescript
// V1
class Data {
  public name: string = 'ZhangSan';
  public id: number = 0;
}

PersistentStorage.persistProp('numProp', 47);
PersistentStorage.persistProp('dataProp', new Data());

@Entry
@Component
struct Index {
  @StorageLink('numProp') numProp: number = 48;
  @StorageLink('dataProp') dataProp: Data = new Data();
  build() {
    Column() {
      Text(`numProp: ${this.numProp}`).onClick(() => { this.numProp += 1; })
      Text(`dataProp.name: ${this.dataProp.name}`).onClick(() => { this.dataProp.name += 'a'; })
    }
  }
}

// V2
import { PersistenceV2, Type } from '@kit.ArkUI';

@ObservedV2
class V2Data {
  @Trace public name: string = '';
  @Trace public id: number = 1;
}

@ObservedV2
export class Sample {
  @Type(V2Data)
  @Trace public num: number = 1;
  @Trace public V2: V2Data = new V2Data();
}

@Entry
@ComponentV2
struct Page1 {
  @Local p: Sample = PersistenceV2.globalConnect({ type: Sample, key: 'connect2', defaultCreator: () => new Sample() })!;

  build() {
    Column() {
      Text(`numProp: ${this.p.num}`).onClick(() => { this.p.num += 1; })
      Text(`dataProp.name: ${this.p.V2.name}`).onClick(() => { this.p.V2.name += 'a'; })
    }
  }
}
```