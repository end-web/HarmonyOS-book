# 资源使用

## 资源目录结构

```
resources/
├── base/                  # 默认资源目录
│   ├── element/           # 基础元素资源
│   │   ├── string.json    # 字符串资源
│   │   ├── color.json     # 颜色资源
│   │   └── float.json     # 浮点数资源
│   ├── media/             # 媒体资源（图片、音频等）
│   └── profile/           # 配置文件
├── rawfile/               # 原始文件目录
└── en_US/                 # 限定词目录（英语环境）
    └── element/
        └── string.json
```

## 资源访问方式

### $r 语法

用于访问 resources 目录下的资源文件。

```typescript
$r('app.type.name')
```

- `app`：应用资源（使用 `sys` 表示系统资源）
- `type`：资源类型
- `name`：资源名称

### $rawfile 语法

用于访问 rawfile 目录下的原始文件。

```typescript
$rawfile('filename')
```

## 常用资源类型

| 类型 | 文件位置 | 说明 |
|-----|---------|------|
| string | element/string.json | 字符串资源 |
| color | element/color.json | 颜色资源 |
| float | element/float.json | 浮点数资源 |
| integer | element/integer.json | 整数资源 |
| boolean | element/boolean.json | 布尔资源 |
| strarray | element/strarray.json | 字符串数组 |
| intarray | element/intarray.json | 整数数组 |
| media | media/ | 媒体资源（图片、图标等） |
| plural | element/plural.json | 复数形式资源 |
| pattern | element/pattern.json | 样式资源 |

## 使用示例

### 字符串资源

string.json：
```json
{
  "string": [
    {
      "name": "app_name",
      "value": "我的应用"
    },
    {
      "name": "welcome",
      "value": "欢迎使用"
    }
  ]
}
```

代码引用：
```typescript
Text($r('app.string.app_name'))
  .fontSize(20)

Button($r('app.string.welcome'))
```

### 颜色资源

color.json：
```json
{
  "color": [
    {
      "name": "primary_color",
      "value": "#007DFF"
    },
    {
      "name": "text_color",
      "value": "#333333"
    }
  ]
}
```

代码引用：
```typescript
Text('标题')
  .fontColor($r('app.color.text_color'))

Button('确定')
  .backgroundColor($r('app.color.primary_color'))
```

### 图片资源

图片放置在 resources/base/media/ 目录下。

```typescript
Image($r('app.media.icon'))
  .width(50)
  .height(50)

Image($r('app.media.background'))
  .width('100%')
  .height(200)
```

### 数值资源

float.json：
```json
{
  "float": [
    {
      "name": "font_size_title",
      "value": "24vp"
    },
    {
      "name": "padding_large",
      "value": "16vp"
    }
  ]
}
```

代码引用：
```typescript
Text('标题')
  .fontSize($r('app.float.font_size_title'))

Column() {
  // ...
}
.padding($r('app.float.padding_large'))
```

### rawfile 原始文件

用于访问 rawfile 目录下的任意文件，如视频、字体等。

```typescript
Video({
  src: $rawfile('video/intro.mp4')
})

Image($rawfile('images/custom.png'))
```

## 系统资源

使用 `sys` 前缀访问系统预置资源。

```typescript
Text('使用系统颜色')
  .fontColor($r('sys.color.ohos_id_color_text_primary'))

Text('使用系统字体大小')
  .fontSize($r('sys.float.ohos_id_text_size_headline'))
```

常用系统资源：
- `sys.color.ohos_id_color_text_primary`：主要文本颜色
- `sys.color.ohos_id_color_text_secondary`：次要文本颜色
- `sys.float.ohos_id_text_size_headline`：标题字体大小
- `sys.float.ohos_id_text_size_body`：正文字体大小

## 多语言支持

通过限定词目录实现多语言：

```
resources/
├── base/
│   └── element/
│       └── string.json      # 默认语言
├── en_US/                   # 英语（美国）
│   └── element/
│       └── string.json
└── zh_CN/                   # 中文（中国）
    └── element/
        └── string.json
```

系统会根据设备语言环境自动选择对应资源。

## 深浅色适配

```
resources/
├── base/
│   └── element/
│       └── color.json       # 浅色模式颜色
└── dark/
    └── element/
        └── color.json       # 深色模式颜色
```

base/element/color.json：
```json
{
  "color": [
    {
      "name": "page_background",
      "value": "#FFFFFF"
    }
  ]
}
```

dark/element/color.json：
```json
{
  "color": [
    {
      "name": "page_background",
      "value": "#1A1A1A"
    }
  ]
}
```

代码中使用相同引用，系统自动切换：
```typescript
Column() {
  // ...
}
.backgroundColor($r('app.color.page_background'))
```

## Resource 类型

在 TypeScript 中，资源引用返回 Resource 类型：

```typescript
@State title: ResourceStr = $r('app.string.app_name')
@State icon: Resource = $r('app.media.icon')
@State color: ResourceColor = $r('app.color.primary_color')
```

常用类型别名：
- `Resource`：资源类型
- `ResourceStr`：string | Resource
- `ResourceColor`：Color | string | Resource
- `Length`：number | string | Resource