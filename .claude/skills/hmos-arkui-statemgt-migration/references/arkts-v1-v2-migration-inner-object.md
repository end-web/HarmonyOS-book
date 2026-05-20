# 内置对象的迁移

## 目录

- [List组件 - ChildrenMainSize](#list组件---childrenmainsize)
- [WaterFlow组件 - WaterFlowSections](#waterflow组件---waterflowsections)
- [attributeModifier](#attributemodifier)
- [CommonModifier](#commonmodifier)
- [组件Modifier](#组件modifier)
- [AttributeUpdater](#attributeupdater)

---

## List组件 - ChildrenMainSize

V2需使用`UIUtils.makeObserved()`包装：

```typescript
// V1
@Entry
@Component
struct ListExample {
  private arr: Array<number> = new Array(10).fill(0);
  @State listChildrenSize: ChildrenMainSize = new ChildrenMainSize(100);

  build() {
    Column() {
      Button('change Default').onClick(() => {
        this.listChildrenSize.childDefaultSize += 10;
      })
      List({ space: 10 }) {
        ForEach(this.arr, (item: number) => {
          ListItem() { Text(`item-${item}`) }
        })
      }.childrenMainSize(this.listChildrenSize)
    }
  }
}

// V2
import { UIUtils } from '@kit.ArkUI';

@Entry
@ComponentV2
struct ListExample {
  private arr: Array<number> = new Array(10).fill(0);
  listChildrenSize: ChildrenMainSize = UIUtils.makeObserved(new ChildrenMainSize(100));

  build() {
    Column() {
      Button('change Default').onClick(() => {
        this.listChildrenSize.childDefaultSize += 10;
      })
      List({ space: 10 }) {
        ForEach(this.arr, (item: number) => {
          ListItem() { Text(`item-${item}`) }
        })
      }.childrenMainSize(this.listChildrenSize)
    }
  }
}
```

---

## WaterFlow组件 - WaterFlowSections

V2需使用`UIUtils.makeObserved()`包装：

```typescript
// V1
@Entry
@Component
struct WaterFlowSample {
  @State sections: WaterFlowSections = new WaterFlowSections();
  @State private arr: Array<number> = new Array(9).fill(0);

  build() {
    Column() {
      WaterFlow({ sections: this.sections }) {
        ForEach(this.arr, (item: number) => {
          FlowItem() { Text(`${item}`) }
        })
      }
    }
  }
}

// V2
import { UIUtils } from '@kit.ArkUI';

@Entry
@ComponentV2
struct WaterFlowSample {
  sections: WaterFlowSections = UIUtils.makeObserved(new WaterFlowSections());
  @Local private arr: Array<number> = new Array(9).fill(0);

  build() {
    Column() {
      WaterFlow({ sections: this.sections }) {
        ForEach(this.arr, (item: number) => {
          FlowItem() { Text(`${item}`) }
        })
      }
    }
  }
}
```

---

## attributeModifier

V2需使用`UIUtils.makeObserved()`包装：

```typescript
// V1
class MyButtonModifier implements AttributeModifier<ButtonAttribute> {
  public isDark: boolean = false;
  applyNormalAttribute(instance: ButtonAttribute): void {
    instance.backgroundColor(this.isDark ? Color.Black : Color.Red);
  }
}

@Entry
@Component
struct AttributeDemo {
  @State modifier: MyButtonModifier = new MyButtonModifier();
  build() {
    Button('Button')
      .attributeModifier(this.modifier)
      .onClick(() => { this.modifier.isDark = !this.modifier.isDark; })
  }
}

// V2
import { UIUtils } from '@kit.ArkUI';

@Entry
@ComponentV2
struct AttributeDemo {
  modifier: MyButtonModifier = UIUtils.makeObserved(new MyButtonModifier());
  build() {
    Button('Button')
      .attributeModifier(this.modifier)
      .onClick(() => { this.modifier.isDark = !this.modifier.isDark; })
  }
}
```

---

## CommonModifier

V2需使用`UIUtils.makeObserved()`包装：

```typescript
// V1
import { CommonModifier } from '@kit.ArkUI';

class MyModifier extends CommonModifier {
  public setGroup1(): void {
    this.borderStyle(BorderStyle.Dotted).borderWidth(8);
  }
  public setGroup2(): void {
    this.borderStyle(BorderStyle.Dashed).borderWidth(8);
  }
}

@Entry
@Component
struct Index {
  @State myModifier: CommonModifier = new MyModifier().width(100).height(100);
  build() { /* ... */ }
}

// V2
import { UIUtils, CommonModifier } from '@kit.ArkUI';

@Entry
@ComponentV2
struct Index {
  @Local myModifier: CommonModifier = UIUtils.makeObserved(new MyModifier().width(100).height(100));
  build() { /* ... */ }
}
```

---

## 组件Modifier

V2需使用`UIUtils.makeObserved()`包装：

```typescript
// V1
import { TextModifier } from '@kit.ArkUI';

class MyModifier extends TextModifier {
  public setGroup1(): void { this.fontSize(50).fontColor(Color.Pink); }
  public setGroup2(): void { this.fontSize(50).fontColor(Color.Gray); }
}

@Entry
@Component
struct Index {
  @State myModifier: TextModifier = new MyModifier().width(100).height(100);
  build() { /* ... */ }
}

// V2
import { UIUtils, TextModifier } from '@kit.ArkUI';

@Entry
@ComponentV2
struct Index {
  @Local myModifier: TextModifier = UIUtils.makeObserved(new MyModifier().width(100).height(100));
  build() { /* ... */ }
}
```

---

## AttributeUpdater

V2需使用`@ObservedV2` + `@Trace`并在`initializeModifier`中读取属性建立关联：

```typescript
// V1
import { AttributeUpdater } from '@kit.ArkUI';

class MyButtonModifier extends AttributeUpdater<ButtonAttribute> {
  public flag: boolean = false;

  initializeModifier(instance: ButtonAttribute): void {
    instance.backgroundColor('#ff2787d9').width('50%').height(30);
  }

  applyNormalAttribute(instance: ButtonAttribute): void {
    instance.borderWidth(this.flag ? 2 : 10);
  }
}

@Entry
@Component
struct Index {
  @State modifier: MyButtonModifier = new MyButtonModifier();
  build() {
    Column() {
      Button('Button').attributeModifier(this.modifier)
      Button('Update').onClick(() => { this.modifier.flag = !this.modifier.flag; })
    }
  }
}

// V2
import { AttributeUpdater } from '@kit.ArkUI';

@ObservedV2
class MyButtonModifier extends AttributeUpdater<ButtonAttribute> {
  @Trace public flag: boolean = false;

  initializeModifier(instance: ButtonAttribute): void {
    this.flag;  // 必须读取flag建立关联
    instance.backgroundColor('#ff2787d9').width('50%').height(30);
  }

  applyNormalAttribute(instance: ButtonAttribute): void {
    instance.borderWidth(this.flag ? 2 : 10);
  }
}

@Entry
@ComponentV2
struct Index {
  @Local modifier: MyButtonModifier = new MyButtonModifier();
  build() {
    Column() {
      Button('Button').attributeModifier(this.modifier)
      Button('Update').onClick(() => { this.modifier.flag = !this.modifier.flag; })
    }
  }
}
```