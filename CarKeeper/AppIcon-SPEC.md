# AppIcon 设计规范

## 设计理念

**琥珀金 + 车辆剪影** — 传递高端、科技、可靠的品牌感知

| 元素 | 设计 |
|------|------|
| **背景** | 深色渐变 (#1A1A2E → #0D0D1A)，营造沉浸感 |
| **主色** | 琥珀金渐变 (#FFB347 → #FF9F00 → #D97300) |
| **主体** | 现代电动轿车剪影，流线型车身 |
| **细节** | 金色轮圈 + 车头灯发光效果 |
| **文字** | 长安车管家 + CHANGAN CONNECT |

---

## 颜色规范

### 琥珀金渐变
```
起点: #FFB347 (亮金)
中间: #FF9F00 (琥珀金) ← 品牌主色
终点: #D97300 (深琥珀)
```

### 背景渐变
```
顶部: #1A1A2E (深蓝黑)
底部: #0D0D1A (更深蓝黑)
```

### 灯光效果
- 车头灯: #FFD700 (金色发光)
- 尾灯: #FF4444 (红色发光)

---

## 尺寸规格

### 导出尺寸（与 `Contents.json` 一一对应，共 7 个）

| 文件名 | 尺寸 | 用途 |
|--------|------|------|
| AppIcon-1024x1024.png | 1024×1024 | 单尺寸主图：App Store 提交；其余机型尺寸由 Xcode 从它生成 |
| AppIcon-60x60@2x.png | 120×120 | iPhone 主屏幕 |
| AppIcon-60x60@3x.png | 180×180 | iPhone 主屏幕 (Retina HD) |
| AppIcon-29x29@2x.png | 58×58 | 设置 / Spotlight |
| AppIcon-29x29@3x.png | 87×87 | 设置 / Spotlight (Retina HD) |
| AppIcon-40x40@2x.png | 80×80 | Spotlight |
| AppIcon-40x40@3x.png | 120×120 | Spotlight (Retina HD) |

**没有 `1x` 槽位，也没有 iPad 专属槽位 —— 这两条都不是遗漏。**

- 目标系统是 iOS 26（`TARGETED_DEVICE_FAMILY: 1,2`），能装它的机型**全是 @2x / @3x**，
  `1x` 槽位没有任何消费者。
- 一张 1024 就够。Apple《Configuring your app icon using an asset catalog》原文：
  「iOS, iPadOS, tvOS, and watchOS apps can auto-generate all icon variations from a
  single 1024×1024 pixel image」，同一页还写「if you have an existing project that
  provides multiple variants, consider providing a single size when that is all your
  icon requires」。
- iPad 图标现在就是这么来的：构建日志里的
  `assetcatalog_output/thinned/AppIcon76x76@2x~ipad.png` 是 Xcode 自己从 1024 生成的。

### 为什么不能写 `idiom: "ipad"`

`Contents.json` 里其它条目是 `idiom: "universal"` + `platform: "ios"`；凡是写成
`idiom: "ipad"` 的，actool 会记进 **「AppIcon has N unassigned children」**，N 正好等于
这类条目的个数 —— 也就是说它们**被忽略**。四个提交里的对应关系：

| 提交 | 条目 | 其中 `idiom: "ipad"` | 1x 槽位 | CI 实测 N |
|------|-----|----------------------|---------|-----------|
| `63decaa` | 12 | 3 | 3 | 3 |
| `ad02a88` | 9 | 2 | 0 | **2** |
| `fe4e36f` | 9 | 2 | 0 | 2 |
| `28b9e1b` | 10 | 3 | 1 | 3 |

`ad02a88` 那一步是判决点：那一轮把**三个 `1x` 槽位全部删掉**，若成因是 1x，N 应归 0；
它却只是 3 → 2，正好剩两条 `ipad` —— 所以成因是 `idiom`，不是 1x。`63decaa` 时两种
解释都恰好等于 3，这正是当初误判成「1x 槽位」的原因（见 `REDESIGN-STATUS.md` §10.6）。

---

## 生成方法

### 方法一：使用 Python 脚本 (推荐)

```bash
# 安装依赖
pip3 install cairosvg

# 生成所有尺寸 —— **直接写进出包的那份 appiconset**
bash generate_appicon.sh
```

> 上一版这里写的是 `python3 generate_appicon.py AppIcon.svg ./AppIcon`，
> 它会在仓库根目录另建一份 `AppIcon/`（13 个 PNG）—— 而 Xcode 实际打的包
> 只认 `CarKeeper/CarKeeper/Resources/Assets.xcassets/AppIcon.appiconset/`。
> 两份图标并存时，改了 A 却在真机上看到 B，是最难查的一类“图标没换”。
> 那份根目录副本已删；`generate_appicon.sh` 是唯一的生成入口。

### 方法二：使用 Figma/Sketch

1. 打开 `AppIcon.svg` 源文件
2. 导出所有尺寸变体
3. 放入 Xcode 的 AppIcon.appiconset 文件夹

### 方法三：在线工具

1. 用浏览器打开 `AppIcon.svg`
2. 使用在线 SVG 转 PNG 工具导出各尺寸

---

## 放置位置

将所有 PNG 文件放入：
```
CarKeeper/CarKeeper/Resources/Assets.xcassets/AppIcon.appiconset/
```

---

## 圆角规范

iOS AppIcon 使用 Squircle（超级椭圆）圆角：
- 圆角半径：约 22% 的宽度
- Xcode 会自动添加圆角遮罩

---

## 视觉检查清单

- [ ] 1024×1024 主图标清晰无模糊
- [ ] 车辆剪影居中对称
- [ ] 琥珀金渐变流畅自然
- [ ] 文字可读性良好
- [ ] 所有尺寸变体无失真

---

## 版本历史

| 版本 | 日期 | 变更 |
|------|------|------|
| v1.0 | 2026-09-20 | 初始设计：琥珀金 + 车辆剪影 |
