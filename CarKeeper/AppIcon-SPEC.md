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

### 必需导出尺寸

| 文件名 | 尺寸 | 用途 |
|--------|------|------|
| AppIcon-1024x1024.png | 1024×1024 | App Store 提交 |
| AppIcon-60x60@2x.png | 120×120 | iPhone 主屏幕 |
| AppIcon-60x60@3x.png | 180×180 | iPhone 主屏幕 (Retina) |
| AppIcon-76x76.png | 76×76 | iPad 主屏幕 |
| AppIcon-76x76@2x.png | 152×152 | iPad 主屏幕 (Retina) |
| AppIcon-83.5x83.5@2x.png | 167×167 | iPad Pro 主屏幕 |
| AppIcon-29x29.png | 29×29 | 设置/Spotlight |
| AppIcon-29x29@2x.png | 58×58 | 设置/Spotlight (Retina) |
| AppIcon-29x29@3x.png | 87×87 | 设置/Spotlight (Retina HD) |
| AppIcon-40x40.png | 40×40 | Spotlight |
| AppIcon-40x40@2x.png | 80×80 | Spotlight (Retina) |
| AppIcon-40x40@3x.png | 120×120 | Spotlight (Retina HD) |

---

## 生成方法

### 方法一：使用 Python 脚本 (推荐)

```bash
# 安装依赖
pip3 install cairosvg

# 生成所有尺寸
python3 generate_appicon.py AppIcon.svg ./AppIcon
```

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
