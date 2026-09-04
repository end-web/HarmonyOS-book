# 睡眠定时器增强功能

## 概述

本次更新为听书 App 的睡眠定时器增加了智能章节结束功能，提升了睡前听书的体验。

## 新增功能

### 1. 智能章节结束（已实现）

- **功能描述**：定时到后不立即暂停，而是等待当前章节播完再暂停
- **使用场景**：睡前听书时，避免在章节中间被打断，保持故事完整性
- **实现逻辑**：
  - 定时到达时，检查当前章节剩余时长
  - 如果剩余时长 ≤ 10 分钟，等待章节播完后再暂停
  - 如果剩余时长 > 10 分钟，直接暂停（避免等待过久）
  - 如果当前未播放，直接暂停
- **UI 位置**：播放器页面 → 定时关闭 → "章节结束后停止" 开关

### 2. 渐弱淡出（未实现）

- **原计划**：最后 5 分钟逐渐降低音量到 10%
- **未实现原因**：HarmonyOS API 26 的 AVPlayer 不支持 `volume` 属性
- **后续方案**：等待 API 更新后再实现，或使用音频焦点 API 替代

### 3. 预设快捷时间（已有）

- 保持现有的 15/30/45/60 分钟预设选项
- 一键设置，无需手动输入

## 修改文件

### 1. `entry/src/main/ets/model/PlayerState.ets`

添加新的状态字段：

```typescript
@Trace sleepSmartStop: boolean = false;  // 智能章节结束开关
@Trace sleepFadeOut: boolean = false;    // 渐弱淡出开关（预留）
```

### 2. `entry/src/main/ets/service/AudioService.ets`

**新增方法：**

- `pauseForSleepSmart()`：智能章节结束逻辑
  - 监听 AVPlayer 的 `stateChange` 事件
  - 等待 `completed` 状态后再暂停
  - 设置超时兜底（章节剩余时长 + 5 秒）

**修改方法：**

- `setSleepTimer(minutes, smartStop, fadeOut)`：增加智能停止和渐弱淡出参数
  - `smartStop`：是否启用智能章节结束
  - `fadeOut`：是否启用渐弱淡出（当前未使用）

### 3. `entry/src/main/ets/pages/PlayerPage.ets`

**UI 更新：**

- 在睡眠定时器弹窗中添加"章节结束后停止"开关
- 使用 `Toggle` 组件（Switch 样式）
- 添加说明文字："定时到后播完当前章节再暂停"

**新增方法：**

- `toggleSleepSmartStop(isOn)`：处理智能停止开关切换
  - 更新状态
  - 重新设置定时器以应用新配置

### 4. `entry/src/main/ets/pages/MainPage.ets`

**修复：**

- 将书架图标从不存在的 `ic_public_storage_filled` 改为 `folder_badge_plus`

## 使用说明

1. 打开播放器页面
2. 点击"定时"按钮
3. 选择定时时长（15/30/45/60 分钟）
4. 开启"章节结束后停止"开关
5. 定时到达时，如果当前章节剩余时长 ≤ 10 分钟，会等待章节播完再暂停

## 技术细节

### 智能停止实现原理

```typescript
// 1. 计算剩余时长
const remainingMs = this.state.durationMs - this.state.progressMs;

// 2. 判断是否等待
if (remainingMs > 10 * 60 * 1000) {
  // 超过 10 分钟，直接暂停
  await this.pauseForSleep();
  return;
}

// 3. 监听状态变化
this.player.on('stateChange', (newState) => {
  if (newState === 'completed') {
    // 章节播完，执行暂停
    this.pauseForSleep();
  }
});

// 4. 设置超时兜底
setTimeout(() => {
  this.pauseForSleep();
}, remainingMs + 5000);
```

### 状态同步

- 开关状态保存在 `PlayerState` 的 `@Trace` 字段中
- 任何组件都可以访问和修改
- 切换开关时会重新调用 `setSleepTimer()` 应用新配置

## 测试建议

1. **基本功能测试**
   - 设置 15 分钟定时，不开启智能停止 → 15 分钟后立即暂停
   - 设置 15 分钟定时，开启智能停止，当前章节剩余 5 分钟 → 20 分钟后暂停
   - 设置 15 分钟定时，开启智能停止，当前章节剩余 15 分钟 → 15 分钟后直接暂停

2. **边界情况测试**
   - 定时到达时手动暂停 → 不应继续等待
   - 定时到达时切换章节 → 应取消等待并暂停
   - 定时到达时 App 退到后台 → 应正常等待并暂停

3. **UI 测试**
   - 开关状态正确显示
   - 开关切换流畅
   - 取消定时后开关状态重置

## 后续优化方向

1. **渐弱淡出**
   - 等待 HarmonyOS 支持音量控制 API
   - 或使用音频焦点降低音量实现

2. **自定义时长**
   - 添加自定义输入框
   - 支持 1-120 分钟任意设置

3. **记忆用户偏好**
   - 保存上次选择的定时时长
   - 保存智能停止开关状态

4. **多样化停止策略**
   - 按章节数停止（播完 N 个章节）
   - 按总时长停止（播满 N 分钟）
   - 按书籍进度停止（播到 N%）

## 版本信息

- 修改日期：2026-09-03
- 修改人：Claude Code
- 涉及模块：播放器、睡眠定时器
- 编译状态：✅ 成功
