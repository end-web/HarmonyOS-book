# 书源时长解析修复说明

## 问题根因

1. `TocRule` 接口没有定义 `duration` 字段（规则层缺失）
2. `TocItem` 接口没有 `duration` 字段（数据层缺失）
3. `BookSourceService.getBookToc()` 没有解析时长规则
4. 所有 `TocItem → Chapter` 转换代码硬编码 `duration: 0`

## 修复内容

### 1. 模型层（model/BookSource.ets）

#### TocRule 接口
```typescript
export interface TocRule {
  // ... 原有字段
  duration?: string; // 新增：时长规则（如 "$.duration" 或 ".time::text"），单位秒
}
```

#### TocItem 接口
```typescript
export interface TocItem {
  // ... 原有字段
  duration?: number; // 新增：时长（秒）
}
```

### 2. 服务层（service/BookSourceService.ets）

#### 新增时长解析工具函数
```typescript
private static parseDuration(durationStr: string): number
```

支持格式：
- 纯数字秒数：`"1234"` → 1234
- 时分秒：`"01:23:45"` → 5025（1*3600 + 23*60 + 45）
- 分秒：`"23:45"` → 1425（23*60 + 45）
- 中文格式：`"1小时23分45秒"` → 5025

#### getBookToc() 中新增时长解析逻辑
位置：`BookSourceService.ets:799-815`

```typescript
if (rule.duration) {
  try {
    const durationStr = await a.getString(rule.duration) || '';
    if (durationStr) {
      const parsed = BookSourceService.parseDuration(durationStr);
      if (parsed > 0) {
        tocItem.duration = parsed;
        hilog.info(0, TAG, 'getBookToc: chapter=%{public}s, durationStr=%{public}s, parsed=%{public}d',
          name.substring(0, 30), durationStr, parsed);
      }
    }
  } catch (e) {
    hilog.warn(0, TAG, 'getBookToc: parse duration failed for chapter=%{public}s, error=%{public}s',
      name.substring(0, 30), String(e));
  }
}
```

### 3. 页面层转换修复

#### BookDetailPage.ets:149
```typescript
// 修改前
duration: 0,

// 修改后
duration: item.duration || 0,
```

#### FavoritePage.ets:177 和 330
```typescript
// 修改前
duration: 0,

// 修改后
duration: item.duration || 0,
```

## 日志输出

### 成功解析
```
[BookSourceService] getBookToc: chapter=第1章 开端, durationStr=1234, parsed=1234
[BookSourceService] getBookToc: chapter=第2章 转折, durationStr=01:23:45, parsed=5025
```

### 解析失败
```
[BookSourceService] getBookToc: parse duration failed for chapter=第3章 高潮, error=...
```

## 测试书源示例

导入以下书源进行测试（JSON 格式）：

```json
{
  "bookSourceUrl": "https://example.com",
  "bookSourceName": "测试时长解析",
  "bookSourceType": 1,
  "bookSourceGroup": "测试",
  "enabled": true,
  "searchUrl": "...",
  "ruleToc": {
    "chapterList": "$.data.chapters[*]",
    "chapterName": "$.title",
    "chapterUrl": "$.url",
    "duration": "$.duration"
  }
}
```

书源的 API 返回示例：
```json
{
  "data": {
    "chapters": [
      {"title": "第1章", "url": "http://...", "duration": "1234"},
      {"title": "第2章", "url": "http://...", "duration": "01:23:45"},
      {"title": "第3章", "url": "http://...", "duration": "23:45"}
    ]
  }
}
```

## 验证步骤

1. 导入包含 `duration` 字段的书源
2. 搜索并打开书籍详情页
3. 查看 hilog 日志，确认解析成功：
   ```bash
   hdc shell hilog | grep "getBookToc.*duration"
   ```
4. 进入播放器页，确认章节时长显示正确（非 0:00）

## 注意事项

1. **向后兼容**：`duration` 字段为可选（`?:`），旧书源不受影响
2. **容错处理**：解析失败时自动回退到 `duration: 0`，不会阻断章节列表加载
3. **日志级别**：成功用 `info`，失败用 `warn`，不影响用户体验
4. **性能影响**：仅当书源规则定义了 `duration` 字段时才执行解析，无额外开销
