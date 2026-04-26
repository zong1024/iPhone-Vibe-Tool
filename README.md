# Sympathetic Vibration

Sympathetic Vibration 是一款把 Apple 健康数据转成柔和声场的 iPhone 应用。

它会读取当天的身体状态，并把这些信号映射到一段可播放的节律里：

- 心率影响节拍推进
- 步数影响高频律动和切分密度
- 睡眠影响铺底长度与稳定度
- HRV 影响纹理张力与空气感

## Product

- 品牌名称：`Sympathetic Vibration`
- 品牌图标：`musiccat`
- 设计方向：通透、克制、以纯色与毛玻璃为主
- 平台：iPhone，iOS 18.2 及以上

## Features

- 本地实时合成可播放的声场
- 接入 `HealthKit` 读取心率、步数、睡眠和 HRV
- 当部分健康数据缺失时，仍可基于已有信号生成声场
- 支持从系统设置与健康权限状态中恢复同步

## Experience

首页围绕 4 个层级组织：

- 品牌与同步状态
- 当天身体信号
- 实时声场播放
- Apple 健康连接说明

视觉上参考 Apple 的 iOS / iPadOS UI kit，尽量使用系统字体、纯色层次与毛玻璃卡片，减少装饰性噪音。

## Stack

- `SwiftUI`
- `AVAudioEngine`
- `HealthKit`
- Xcode 16.2

## Run

1. 打开仓库里的 Xcode 工程
2. 选择 iPhone 真机运行
3. 首次启动时允许读取 Apple 健康数据
4. 在首页点击“同步健康”和“播放声场”

## Health Access

- 心率、HRV 和睡眠通常依赖 Apple Watch 或其他健康来源
- 如果设备里还没有样本，App 会先保持默认声场
- 设备锁定时，HealthKit 可能暂时不可访问
- 如果权限被关闭，可以在系统设置或健康 App 中重新开启

## Structure

- `iPhone Vibe Tool/ContentView.swift`
  主界面与视觉层
- `iPhone Vibe Tool/BiometricDataStore.swift`
  健康数据读取、降级策略、信号映射
- `iPhone Vibe Tool/BiometricSynthEngine.swift`
  声音合成与节拍生成
- `iPhone Vibe Tool/Assets.xcassets`
  `musiccat` 图标、品牌资源与主题色

## Notes

这个仓库当前已经具备可运行的主流程、真实健康数据同步和完整品牌落地，可作为 App Store 上线前的产品基线继续迭代。
