# 主题与适配

## 深色/浅色模式适配

### 系统主题监听

```typescript
@StorageProp('colorMode') colorMode: number = 0;  // 0:浅色, 1:深色

build() {
  Column() {
    Text('Content')
      .fontColor(this.colorMode === 1 ? '#FFFFFF' : '#000000')
  }
  .backgroundColor(this.colorMode === 1 ? '#1A1A1A' : '#FFFFFF')
}
```

### 资源限定词

```
resources/
├── base/           # 默认资源
├── dark/           # 深色模式资源
└── light/          # 浅色模式资源
```

---

## 主题换肤

### 主题定义

```typescript
interface Theme {
  primaryColor: ResourceColor;
  backgroundColor: ResourceColor;
  textColor: ResourceColor;
}

const LightTheme: Theme = {
  primaryColor: '#007DFF',
  backgroundColor: '#FFFFFF',
  textColor: '#000000'
};

const DarkTheme: Theme = {
  primaryColor: '#4DA3FF',
  backgroundColor: '#1A1A1A',
  textColor: '#FFFFFF'
};
```

### 主题应用

```typescript
@Provide('theme') theme: Theme = LightTheme;

build() {
  Column() {
    Text('Content')
      .fontColor(this.theme.textColor)
  }
  .backgroundColor(this.theme.backgroundColor)
}
```

### 动态切换

```typescript
toggleTheme() {
  this.theme = this.theme === LightTheme ? DarkTheme : LightTheme;
}
```

---

## 多设备适配

### 断点响应

```typescript
@State currentBreakpoint: string = 'sm';

aboutToAppear() {
  media.matchMediaSync('(width >= 840vp)').on('change', (result) => {
    this.currentBreakpoint = result.matches ? 'lg' : 'sm';
  });
}

build() {
  if (this.currentBreakpoint === 'lg') {
    // 大屏布局
  } else {
    // 小屏布局
  }
}
```

### 栅格布局

```typescript
GridRow({ columns: { sm: 4, md: 8, lg: 12 } }) {
  GridCol({ span: { sm: 4, md: 4, lg: 6 } }) {
    Text('Content')
  }
}
```

---

## 国际化

### 资源文件

```
resources/
├── en_US/          # 英文资源
│   └── element/string.json
├── zh_CN/          # 中文资源
│   └── element/string.json
└── base/           # 默认资源
    └── element/string.json
```

### 使用资源

```typescript
Text($r('app.string.title'))
```

### 获取系统语言

```typescript
@StorageProp('languageCode') languageCode: string = 'en';

aboutToAppear() {
  Environment.envProp('languageCode', 'en');
}
```

---

## 屏幕适配

### vp单位

ArkUI默认使用vp作为单位，自动适配不同屏幕密度。

```typescript
Text('Content')
  .width(100)  // 100vp
  .height(50)  // 50vp
```

### 安全区域

```typescript
Column() {
  // 内容
}
.expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.ALL])
```

---

## 适老化

### 字体缩放

```typescript
@StorageProp('fontSizeScale') fontSizeScale: number = 1.0;

Text('Content')
  .fontSize(16 * this.fontSizeScale)
```

### 高对比度

```typescript
@StorageProp('highContrast') highContrast: boolean = false;

Text('Content')
  .fontColor(this.highContrast ? '#000000' : '#333333')
```