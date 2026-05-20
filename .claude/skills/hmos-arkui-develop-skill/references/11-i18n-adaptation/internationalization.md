# 国际化

## 资源文件结构

```
resources/
├── base/
│   └── element/
│       └── string.json
├── en_US/
│   └── element/
│       └── string.json
├── zh_CN/
│   └── element/
│       └── string.json
└── zh_Hant/
    └── element/
        └── string.json
```

---

## 字符串资源

### string.json格式

```json
{
  "string": [
    {
      "name": "app_name",
      "value": "My App"
    },
    {
      "name": "welcome",
      "value": "Welcome, %s!"
    }
  ]
}
```

### 使用字符串资源

```typescript
Text($r('app.string.app_name'))

// 带参数
Text($r('app.string.welcome', 'User'))
```

---

## 图片资源

```
resources/
├── base/
│   └── media/
│       └── icon.png
├── en_US/
│   └── media/
│       └── icon.png      # 英文版本图标
└── zh_CN/
    └── media/
        └── icon.png      # 中文版本图标
```

```typescript
Image($r('app.media.icon'))
```

---

## 系统语言获取

```typescript
import { i18n } from '@kit.LocalizationKit';

// 获取系统语言
let systemLanguage = i18n.System.getSystemLanguage();  // 'zh-CN'

// 获取应用语言
let appLanguage = i18n.System.getAppPreferredLanguage();
```

---

## 日期时间格式化

```typescript
import { i18n } from '@kit.LocalizationKit';

// 日期格式化
let dateFormat = new i18n.DateTimeFormat('zh-CN', {
  dateStyle: 'long'
});
let formattedDate = dateFormat.format(new Date());  // '2024年1月1日'

// 时间格式化
let timeFormat = new i18n.DateTimeFormat('zh-CN', {
  timeStyle: 'medium'
});
let formattedTime = timeFormat.format(new Date());  // '12:30:00'
```

---

## 数字格式化

```typescript
import { i18n } from '@kit.LocalizationKit';

// 数字格式化
let numberFormat = new i18n.NumberFormat('zh-CN', {
  style: 'currency',
  currency: 'CNY'
});
let formattedNumber = numberFormat.format(1234.56);  // '¥1,234.56'
```

---

## RTL布局

### 镜像布局

```typescript
Column() {
  // 内容
}
.direction(this.isRTL ? Direction.Rtl : Direction.Ltr)
```

### 镜像图片

```
resources/
├── base/
│   └── media/
│       └── arrow.png
└── rtl/
    └── media/
        └── arrow.png      # RTL布局使用的镜像图片
```

---

## 复数处理

### plural.json

```json
{
  "plural": [
    {
      "name": "item_count",
      "value": {
        "one": "1 item",
        "other": "%d items"
      }
    }
  ]
}
```

### 使用复数资源

```typescript
Text($r('app.plural.item_count', this.count))
```

---

## 时区处理

```typescript
import { i18n } from '@kit.LocalizationKit';

// 获取时区
let timezone = i18n.TimeZone.getTimeZone();

// 设置时区
i18n.TimeZone.setTimeZone('Asia/Shanghai');
```

---

## 区域设置

```typescript
import { i18n } from '@kit.LocalizationKit';

// 获取区域设置
let locale = i18n.getDisplayLanguage('zh-Hans', 'en');

// 设置应用语言
i18n.System.setPreferredLanguage('zh-Hans');
```