# AnimateTo使用迁移

## 目录

- [问题描述](#问题描述)
- [API version 22之前方案](#api-version-22之前的迁移方案)
- [API version 22及以后方案](#api-version-22及以后的迁移方案)

---

## 问题描述

V2中animateTo执行前的状态修改未生效：

```typescript
// V1 - 预期效果：100 → 200
@Entry
@Component
struct Index {
  @State w: number = 50;
  @State h: number = 50;
  @State message: string = 'Hello';

  build() {
    Column() {
      Button('change size').onClick(() => {
        this.w = 100;      // 先设为100
        this.h = 100;
        this.message = 'Hello World';
        this.getUIContext().animateTo({ duration: 1000 }, () => {
          this.w = 200;    // 再动画到200
          this.h = 200;
          this.message = 'Hello ArkUI';
        })
      })
      Column() { Text(`${this.message}`) }
        .width(this.w)
        .height(this.h)
    }
  }
}

// V2 - 问题：50 → 200（前面的100未生效）
@Entry
@ComponentV2
struct Index {
  @Local w: number = 50;
  @Local h: number = 50;
  @Local message: string = 'Hello';

  build() {
    Column() {
      Button('change size').onClick(() => {
        this.w = 100;      // 未生效
        this.h = 100;
        this.message = 'Hello World';
        this.getUIContext().animateTo({ duration: 1000 }, () => {
          this.w = 200;
          this.h = 200;
          this.message = 'Hello ArkUI';
        })
      })
    }
  }
}
```

---

## API version 22之前的迁移方案

使用`animateToImmediately`：

```typescript
@Entry
@ComponentV2
struct Index {
  @Local w: number = 50;
  @Local h: number = 50;
  @Local message: string = 'Hello';

  build() {
    Column() {
      Button('change size').onClick(() => {
        this.w = 100;
        this.h = 100;
        this.message = 'Hello World';
        animateToImmediately({ duration: 0 }, () => {})  // 先刷新
        this.getUIContext().animateTo({ duration: 1000 }, () => {
          this.w = 200;
          this.h = 200;
          this.message = 'Hello ArkUI';
        })
      })
    }
  }
}
```

---

## API version 22及以后的迁移方案

使用`UIUtils.applySync()`：

```typescript
import { UIUtils } from '@kit.ArkUI';

@Entry
@ComponentV2
struct Index {
  @Local w: number = 50;
  @Local h: number = 50;
  @Local message: string = 'Hello';

  build() {
    Column() {
      Button('change size').onClick(() => {
        UIUtils.applySync(() => {
          this.w = 100;
          this.h = 100;
          this.message = 'Hello World';
        })
        this.getUIContext().animateTo({ duration: 1000 }, () => {
          this.w = 200;
          this.h = 200;
          this.message = 'Hello ArkUI';
        })
      })
    }
  }
}
```