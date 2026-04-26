# 共振 · Resonance

一个把 Apple 健康数据转成 Lo-Fi 节律的 iPhone 实验应用。

## 这是什么

`共振` 会读取当天的身体状态，并把它映射到一段可播放的低保真节律里：

- 心率：影响 BPM 和鼓点推进
- 步数：影响切分密度和 hi-hat 活跃度
- 睡眠：影响铺底长度与稳定度
- HRV：影响颗粒感与整体张力

如果当前设备、权限或健康样本不可用，App 会自动回退到演示数据，保证界面和声音依然可用。

## 当前能力

- 本地实时生成可播放的节律，不依赖外部音频文件
- 通过 `HealthKit` 读取心率、步数、睡眠和 HRV
- 对缺失的健康字段做局部降级，而不是整页报废
- 使用中文界面展示数据来源、节律摘要和读取状态

## 技术栈

- `SwiftUI`
- `AVAudioEngine`
- `HealthKit`
- Xcode 16.2
- iOS 18.2+

## 运行方式

1. 用 Xcode 打开 `iPhone Vibe Tool.xcodeproj`
2. 选择真机运行
3. 首次启动时允许读取健康数据
4. 点击“播放”试听节律，点击“刷新”重新同步健康数据

## HealthKit 说明

- 模拟器通常无法提供真实健康数据，建议直接在 iPhone 上测试
- 心率、HRV、睡眠很多时候依赖 Apple Watch 或其他健康来源
- 如果 App 没拿到真实数据：
  - 先确认手机已解锁
  - 到 健康 App -> 资料 -> App 与服务 中检查权限
  - 确认健康 App 自己已经有步数、心率或睡眠样本

## 项目结构

- `iPhone Vibe Tool/ContentView.swift`
  主界面与交互
- `iPhone Vibe Tool/BiometricDataStore.swift`
  HealthKit 读取、降级策略、数据映射
- `iPhone Vibe Tool/BiometricSynthEngine.swift`
  本地声音合成与节奏生成
- `iPhone Vibe Tool/Assets.xcassets`
  图标与颜色资源

## 现阶段方向

- 继续把节奏做得更像完整音乐段落，而不是短循环
- 为健康权限失败补更直接的引导
- 继续打磨成更接近 Apple 一方应用的视觉和交互质感
