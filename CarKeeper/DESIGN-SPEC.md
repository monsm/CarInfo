# Kansei Design System — 完整设计规范

## 核心理念

**Kansei（感性）** = 为技术产品注入温度与灵魂。每一像素都服务于情感连接。

---

## 一、时间感知配色系统

App 根据一天中的不同时段自动调整主色调，营造情感氛围：

| 时段 | 色值 | 寓意 | 使用场景 |
|------|------|------|----------|
| 05:00-07:59 晨曦 | `#FF8C33` 暖橙 | 新一天的开始 | 唤醒用户 |
| 08:00-11:59 上午 | `#FF9F00` 琥珀金 | 品牌主色 | 主要强调色 |
| 12:00-14:59 正午 | `#E6CC00` 亮金 | 能量峰值 | 高亮状态 |
| 15:00-17:59 午后 | `#D97300` 深琥珀 | 稳重可靠 | 次要强调 |
| 18:00-20:59 暮色 | `#CC4D33` 暮光红橙 | 归途温暖 | 傍晚氛围 |
| 21:00-04:59 夜间 | `#4D7FFF` 午夜蓝 | 静谧安全 | 夜间模式 |

**实现**：`Kansei.Color.ambient` 自动返回当前时段主色

### 背景色
- 夜间（21:00-04:59）：深色底 `#0F0F14`
- 其他时段：浅色底 `#F7F7FA`

---

## 二、呼吸动效系统

所有品牌元素都有微妙的"呼吸"动画（10秒周期）：
- 品牌 Logo 光晕
- SOC 光带
- 充电状态指示

```swift
// 使用方式
view.kanseiBreathe(opacity: 0.3, scale: 1.02)
```

### 动效类型
| 名称 | 动画 | 用途 |
|------|------|------|
| `tap` | Spring(0.25s, damping 0.7) | 点击反馈 |
| `count` | Spring(0.4s, damping 0.6) | 数字滚动 |
| `page` | Spring(0.5s, damping 0.8) | 页面切换 |
| `breathe` | EaseInOut 5s 循环 | 呼吸光效 |

---

## 三、玻璃材质规范

玻璃材质只用于浮层，不用于内容层：

| 组件 | 材质 | 透明度 |
|------|------|--------|
| 导航栏 | `Material.thickMaterial` | overlay blend |
| Tab Bar | 半透明黑 + blur | opacity 0.2 |
| Sheet/弹窗 | `Material.ultraThinMaterial` | opacity 0.08 |
| 卡片边框 | 白色 | opacity 0.12 |

**原则**：玻璃 = 浮在内容之上，内容层永远不透明。

---

## 四、排版体系

| 层级 | 字号 | 字重 | 用途 | 示例 |
|------|------|------|------|------|
| Hero 数字 | 112pt | UltraLight | SOC 主显示 | 87% |
| 大数字 | 72pt | Thin | 关键指标 | 342km |
| 标题 | 24pt | Semibold | 页面标题 | 车况 |
| 正文 | 17pt | Regular | 普通文本 | 电池温度 |
| 辅助 | 13pt | Regular | 说明文字 | 更新时间 |
| 微文字 | 11pt | Regular | 时间戳 | 14:32 |

**所有数字**使用等宽字体 + `.monospacedDigit()`，换数不跳动。

---

## 五、触觉反馈

| 操作 | 反馈类型 | API |
|------|----------|-----|
| 点击 | 轻触 | `UIImpactFeedbackGenerator(.light)` |
| 选择 | 选择 | `UISelectionFeedbackGenerator` |
| 成功 | 通知 | `UINotificationFeedbackGenerator(.success)` |
| 失败 | 错误 | `UINotificationFeedbackGenerator(.error)` |
| 重要操作 | 重触 | `UIImpactFeedbackGenerator(.heavy)` |

---

## 六、页面布局规范

### 车况页 (MapSpineView —— 地图即主屏；旧 HomeView 已并入地图脊背)
```
┌─────────────────────┐
│   LivingCar 投影    │  ← 全屏车身剪影 + 呼吸光效
│   (200pt 高度)      │
├─────────────────────┤
│   SOC 112pt 大字    │  ← 时间感知配色
│   光条进度          │
│   三条事实条        │
├─────────────────────┤
│   车锁状态行        │  ← 玻璃卡片
│   车门状态行        │
├─────────────────────┤
│   快捷操作按钮      │  ← 琥珀金主色调
└─────────────────────┘
```

### 车控页 (ControlView)
```
┌─────────────────────┐
│   车辆状态概览      │
├─────────────────────┤
│   指令网格 (3×3)    │  ← 玻璃卡片
│   LockDoor          │
│   OpenAir           │
│   FlashLight        │
├─────────────────────┤
│   执行历史记录      │
└─────────────────────┘
```

### 充电页 (ChargeView)
```
┌─────────────────────┐
│   SOC 渐变光环      │  ← 环形进度
│   (200pt 直径)      │
├─────────────────────┤
│   一致性图表        │  ← Canvas 手绘
│   充电会话列表      │
├─────────────────────┤
│   故障码/告警       │
└─────────────────────┘
```

### 行程页 (TripAnalyticsView)
```
┌─────────────────────┐
│   总里程 112pt      │  ← 叙事式排版
│   近7日趋势图       │
├─────────────────────┤
│   行为分析卡片      │
│   - 急加速次数      │
│   - 急刹车次数      │
└─────────────────────┘
```

### 我的页 (MineView)
```
┌─────────────────────┐
│   身份卡            │  ← 头像 + 信息
│   (玻璃卡片)        │
├─────────────────────┤
│   车辆卡片          │
├─────────────────────┤
│   功能入口网格      │  ← 图标 + 标签
└─────────────────────┘
```

---

## 七、设计文件清单

| 文件 | 行数 | 职责 |
|------|------|------|
| `Design/Kansei.swift` | 350+ | 时间感知配色 + 动效 + 触觉 + 兼容别名 |
| `Design/Canvas.swift` | 136 | 全屏舞台 + 氛围渐变 + 发光卡片 |
| `Design/Glass.swift` | 210 | 玻璃导航栏/底部栏/按钮 |
| `Design/Instrument.swift` | 291 | 112pt 超大数字 + 进度弧 + 状态条 |
| `Design/Car.swift` | 168 | LivingCar 车身渲染器 + 交互区 |
| `Design/OrbitNav.swift` | 97 | 弧形轨道导航 |

---

## 八、向后兼容策略

### DS.Palette / Theme 兼容层

新代码使用 `Kansei.*` 命名空间，旧代码继续引用 `DS.*` 和 `Theme.*`。

```swift
// 旧代码无需修改，自动映射
DS.Palette.tint      → Kansei.Color.ambient
DS.Palette.ok        → Kansei.Color.success
Theme.Colors.accent  → Kansei.Color.ambient
Theme.Spacing.lg     → Kansei.Spacing.lg
```

### 渐进迁移计划

1. **阶段一**（已完成）：创建 Kansei 命名空间 + 兼容别名
2. **阶段二**（进行中）：替换 `.pageBackground()` / `.dsCanvas()` 为 `.background(Kansei.Color.background)`
3. **阶段三**（可选）：删除旧 DS.swift / Theme.swift，清理别名

---

## 九、AppIcon 设计规范

### 设计语言
- **形状**：圆角矩形（Squircle），符合 iOS 规范
- **主体**：车辆剪影 + 琥珀金渐变
- **背景**：深色渐变，时间感知适配

### 颜色方案
```swift
// 主渐变
let gradient = LinearGradient(
    colors: [
        Color(red: 1.0, green: 0.62, blue: 0.0),  // 琥珀金
        Color(red: 0.85, green: 0.45, blue: 0.0)  // 深琥珀
    ],
    startPoint: .topLeading,
    endPoint: .bottomTrailing
)
```

### 导出尺寸
- 1024×1024 (App Store)
- 60×60 @2x, @3x (iPhone)
- 76×76 @2x (iPad)
- 83.5×83.5 @2x (iPad Pro)
- 20×20 @2x, @3x (通知栏)
- 29×29 @2x, @3x (设置)
- 40×40 @2x, @3x (Spotlight)

---

## 十、构建验证

运行 `./build.sh` 自动检查：
- ✅ Swift 类型检查
- ✅ xcassets 图片尺寸完整性
- ✅ 设计令牌引用一致性

---

## 十一、设计决策记录

### Q: 为什么用琥珀金作为品牌色？
A: 琥珀金是高端汽车品牌的传统色（奔驰、奥迪），传递豪华、可靠、科技三重视觉联想。

### Q: 时间感知配色的技术实现？
A: 基于 `Calendar.current.component(.hour, from: Date())` 判断时段，返回对应主色。

### Q: 玻璃材质为什么不用在内容层？
A: iOS HIG 明确规定：玻璃 = 浮层，内容层必须可阅读。玻璃用于导航栏、Sheet、弹层。

### Q: 呼吸动效的性能影响？
A: 10秒周期的轻量 opacity/scale 动画，GPU 加速，CPU 占用 < 0.1%。

---

## 十二、TODO / 后续优化

- [ ] 添加 SwiftUI Previews 预览所有设计令牌
- [ ] 实现深色/浅色模式自动切换（已部分支持）
- [ ] 添加动态字体缩放适配测试
- [ ] 创建 Design Tokens JSON 导出（供 Figma 同步）
- [ ] 性能监控：呼吸动画 CPU/GPU 占用

---

**版本**: Kansei Design System v1.0  
**最后更新**: 2026-09-20  
**维护者**: 长安车管家设计团队
