# MAPKIT-FEASIBILITY.md — 三种艺术方向 × 真实 MapKit

> 这份文档回答一个问题：**设计稿上的那张地图，在真机上到底有多少能画出来？**
> 三种艺术方向（夜光 / 纸上 / 巨字）各自的判词都以这里为准；
> App 里的「艺术主题」样张页（`Features/ThemeGalleryView.swift`）会把这套判词显示给用户看。

---

## 0. 一句话结论

**MapKit 给你的旋钮一共只有 5 个**（地图族 ×3、海拔、强调度、POI 过滤、路况），
**没有任何公开 API 能改道路 / 街区 / 水面的颜色**。

所以：

| 方向 | 判词 |
|---|---|
| **夜光** | **能落地**。压暗 + 去 POI + 关路况 = 系统地图自己退到背景，我们再叠光层 |
| **纸上** | **不能靠 MapKit**。系统瓦片永远是"现代地图"的样子，长不出纸与墨 —— 要么自建地图样式，要么整个地理层自己画 |
| **巨字** | **最省**。地图退成极淡网格，几乎不依赖地理层 —— 代价是它离"以地图为核心"最远 |

---

## 1. MapKit 的全部旋钮（这是全集，不是节选）

下面每一项都**逐个核过 Apple 官方文档 JSON**（不是凭记忆，见 §7 核实记录）。

### 1.1 SwiftUI（`Map` + `MapStyle`，iOS 17+）

```swift
Map(position: $camera) {
    Annotation("车", coordinate: carCoord) { CarPin() }        // 屏幕空间标注
    MapPolyline(coordinates: tripCoords)                       // 地理空间折线
        .stroke(accent, style: StrokeStyle(lineWidth: 4, lineCap: .round))
    MapCircle(center: station, radius: 250)                    // 地理空间圆
        .foregroundStyle(accent.opacity(0.25))
    MapPolygon(coordinates: heatRing)                          // 地理空间多边形
        .foregroundStyle(accent.opacity(0.20))
}
.mapStyle(.standard(elevation: .flat,
                    emphasis: .muted,
                    pointsOfInterest: .excludingAll,
                    showsTraffic: false))
```

| 旋钮 | 取值 | iOS | 能改变什么 |
|---|---|---|---|
| `MapStyle` 族 | `.standard` / `.imagery` / `.hybrid` | 17.0 | 地图的整体"种类"，**只有这三种** |
| `MapStyle.Elevation` | `.flat` / `.realistic` / `.automatic` | 17.0 | 平地 2D 还是带起伏的 3D |
| `MapStyle.StandardEmphasis` | `.muted` / `.automatic` | 17.0 | **把地图"压暗、去强调"** —— 夜光方向的唯一抓手 |
| `PointOfInterestCategories` | `.all` / `.excludingAll` / `.including(…)` / `.excluding(…)` | 17.0 | 关掉系统 POI 图标，让地图安静下来 |
| `showsTraffic` | `Bool` | 17.0 | 实时路况着色（它会给路上色 → 与自定义配色冲突） |

### 1.2 UIKit（`MKMapView`，项目现有代码走这条）

```swift
let cfg = MKStandardMapConfiguration(elevationStyle: .flat, emphasisStyle: .muted)
cfg.pointOfInterestFilter = .excludingAll
cfg.showsTraffic = false
mapView.preferredConfiguration = cfg        // iOS 16+
mapView.overrideUserInterfaceStyle = .dark  // 暗色瓦片（iOS 13+，UIKit 侧）
```

| 旋钮 | iOS | 备注 |
|---|---|---|
| `MKStandardMapConfiguration(elevationStyle:emphasisStyle:)` | 16.0 | `MKMapConfiguration.ElevationStyle` + `MKStandardMapConfiguration.EmphasisStyle` |
| `MKMapConfiguration.pointOfInterestFilter` | 16.0 | 类型是 `MKPointOfInterestFilter`（iOS 13+） |
| `MKStandardMapConfiguration.showsTraffic` | 16.0 | — |
| `MKMapView.preferredConfiguration` | 16.0 | — |
| `MKMapView.overrideUserInterfaceStyle` | 13.0 | 只切明暗，不改配色 |

### 1.3 法律/政策边界（这条会被忽略但很硬）

- **不能**下载瓦片自绘（Apple 地图数据的许可不允许）。
- **不能**用 `MKTileOverlay` 覆盖一整层自定义底图 —— 那等于拿自绘底图冒充 Apple 地图数据。
- `MKTileOverlay` 的合法用途是**叠加**（例如你自己产的数据热力层），不是替换底图。
- 结论：**要"纸与墨"的地图，就必须脱离 MapKit 走 MapLibre / 自建瓦片**，没有第三条路。

---

## 2. 可行性矩阵（三种方向 × 图上每一种元素）

图例：**✅ 系统直接画** ｜ **🟡 叠层能画**（系统底层 + 我们自己的 Shape/Overlay） ｜ **🔴 必须自建地图** ｜ **❌ 做不了**

| 图上元素 | 夜光 | 纸上 | 巨字 | 怎么实现 |
|---|---|---|---|---|
| 路网 / 街区 / 水面基础色 | 🟡 | 🔴 | 🟡 | 夜光：`.muted` + 暗色 + 压暗叠层；纸上：**MapKit 无解**；巨字：压到接近不可见即可 |
| 地名 | 🟡 | 🟡 | 🟡 | 系统地名用 `.muted` 弱化；我们要的大字地名**用 `Annotation` 自己画**（不随缩放变大） |
| 实时路况 | ❌ | ❌ | ❌ | 关掉。它会给路上色，与我们唯一的强调色冲突 |
| 路线（今天这条路） | ✅ | ✅ | ✅ | `MapPolyline` 分段一条一条画；颜色/线宽自由 |
| 路线上的光晕 | 🟡 | ❌ | ❌ | 夜光：叠一层更粗更透明的 polyline 当光晕；纸上**没有发光**（物理上纸不会发光） |
| 车钉（电量环） | 🟡 | 🟡 | 🟡 | 真实 `Shape`：圆 + `trim(to: 0.78)` + 旋转 −90°，任何缩放下都锐利、可动画 |
| 车钉的外发光 / 接地阴影 | 🟡 | ❌ | ❌ | 夜光：`Annotation` 内容里加 `.shadow`；纸上用墨线圈代替 |
| 充电站价签（贴着钉） | 🟡 | 🟡 | 🟡 | `Annotation` + `Text`，屏幕空间，不随缩放变形 |
| 热区（钱花在哪个位置） | 🟡 | 🟡 | 🟡 | `MapCircle` / `MapPolygon` + 半透明填充 |
| 多站叠加成"热图" | ✅ | 🟡 | 🟡 | 系统画多边形，我们只给不透明度 —— **注意透明度会相乘**（见 §5） |
| 行程回放（时间轴拖动） | 🟡 | 🟡 | 🟡 | 我们自己控制数据切片，系统只负责画 |
| 比例尺 / 图廓刻度 / 图版号 | 🟡 | 🟡 | 🟡 | 屏幕空间浮层，我们画 |
| 纸纹 / 颗粒 / 印刷网点 | 🟡 | 🟡 | 🟡 | 屏幕空间叠层（**这一层是屏幕空间的，不是地理空间的** —— 缩放时纸纹不该跟着放大） |
| 地图整体旋转 7°（让路网斜走） | ✅ | ✅ | 🟡 | `MapCameraPosition` 的 heading 参数 |
| 路名的字体与字距 | ❌ | ❌ | ❌ | 系统路名不可定制。要定制只能关掉系统地名、自己画全部地名 |
| 道路的描边 / 虚线中心线 | ✅（系统自带） | 🔴 | ✅ | 真实瓦片本来就这样；**纸上要的"细线 + 淡地块"系统给不了** |

**读这张表的方法**：三个方向里 **纸上（B）是唯一有 🔴 的** —— 它的美术语言（纸面、墨线、淡彩地块）恰恰落在 MapKit 权限为零的那一格。夜光只有一处 ❌（路名），巨字几乎全绿。

---

## 3. 逐方向落地配置

### 3.1 夜光（推荐先做）

```swift
// 系统瓦片压到背景
.mapStyle(.standard(elevation: .flat, emphasis: .muted,
                    pointsOfInterest: .excludingAll, showsTraffic: false))
// 再叠：光池（屏幕空间）+ 路线光晕（地理空间两层 polyline）+ 车钉（Shape）
```

- **缺口**：地图整体偏"平"（`.muted` 之后仍然比我们的设计图亮、比设计图密）。**必须实测一次对比度**：把暗色浮层叠在真瓦片上，看文字与地图是否还分得开。
- **成本**：低。不需要新依赖，不需要新数据源。
- **风险**：暗色浮层会**盖掉一部分真实地理信息**（用户可能找不到路）。要留一个"看真实地图"的开关。

### 3.2 纸上（最贵，但要先知道贵在哪）

- **MapKit 端**：`.muted` + `.flat` + 去 POI 是**能做到的全部**。结果仍然是一张现代地图，只是安静了一点 —— **它永远不会是纸**。
- **要真做成**：走自建地图（MapLibre + 自己的样式）。代价：
  1. 一份地图样式要长期维护；
  2. 瓦片/数据源要么自付流量，要么接受限速；
  3. 原生 MapKit 的**搜索、路况、导航、Look Around 全部失去**，这些要另找方案；
  4. 审核上仍要能证明地图数据来源合规。
- **我的判断**：如果你的目标是"车 App 一眼认出来"，纸上是最有力的；**但那是产品决策，不是设计决策** —— 它的成本在瓦片，不在界面。

### 3.3 巨字（最省，也最偏离地图）

- 地图几乎不可见（极淡网格），**系统给什么色都不重要** → 连 `.muted` 都可以不用。
- 优点：零依赖、零数据风险、性能最好。
- 缺点：它已经不是一个"以地图为核心"的界面了；地图沦为纹理。

---

## 4. 现状：项目里已经有三张各写各的地图

| 位置 | 现在怎么写 | 迁移建议 |
|---|---|---|
| `Features/TripDetailView.swift:371` | `MapView: UIViewRepresentable` 包 `MKMapView`；`MKPointAnnotation` + `MKPolyline` + `MKMarkerAnnotationView` 画车与行程 | **保留**（它是唯一有真实涂层的），接受 `preferredConfiguration` 换风格 |
| `Features/ParkingMapView.swift:10` | SwiftUI `Map` + `MKCoordinateRegion` | 合并进主屏（停车位置 = 车钉的历史点） |
| `Features/Home/HomeView.swift:1296` | SwiftUI `Map` + `MKCoordinateRegion` | 合并进主屏 |
| `Design/Theme.swift:813` | `MKLocalSearch` 搜充电站 | **保留**，它才是"充电站从哪来"的答案 |
| `Features/Home/HomeView.swift:906` | `MKMapItem(location:address:).openInMaps()` | 保留（系统导航） |

**结论**：不是"要不要引入地图"，而是**把三条各写各的路径收成一条脊椎**。收敛后 App 里只应该有一个地图组件，风格由一个 `MapStyleSpec` 决定 —— 与 `ArtTheme` 一一对应。

```swift
// 建议的形状（尚未实现）
struct MapStyleSpec {
    let style: MapStyle
    let dimsSystemTiles: Bool     // 是否再叠一层压暗
    let cameraHeading: Double     // 夜光 = 7°，其余 = 0
    let showsPlaceLabels: Bool
}
extension ArtTheme { var mapSpec: MapStyleSpec { … } }
```

---

## 5. 三个技术风险（都必须先验证，不能猜）

1. **大量标注的聚合**：几百个充电站钉必须聚合。SwiftUI `Map` 的聚合支持情况**我没有核实到确定的 API** —— 写之前先查实（写错名字 = 直接编译失败，本项目已经栽过 `letterSpacing` 和 `Kansei.Color` 两次）。
2. **半透明面叠加**：多个 `MapCircle` / `MapPolygon` 叠在一起时，不透明度是**相乘**而不是相加 —— 热区会看起来"比设计的深/浅"。要在真机上复现一次再定值。
3. **真瓦片上的对比度**：这是最大的未知。设计稿是手绘的暗底，真瓦片更亮更密。**纸上方向在真机上甚至可能根本读不清** —— 必须实测。

**验证方法（顺序不能颠倒）**：先做一个单屏真工程（1 个地图 + 1 个车钉 + 1 条路线 + 1 个风格开关），在模拟器里把三种 `MapStyleSpec` 各截一张；**用真截图定值，不用设计稿定值**。

---

## 6. 落地状态（已实现 / 未实现）

### 6.1 已实现（就在这个仓库里，可编译前请先看 6.3）

| 文件 | 它负责什么 |
|---|---|
| `CarKeeper/Design/MapStyleSpec.swift` | 艺术方向 → **真实 MapKit 配置**（本文件就是上面那张对应表的代码形态） |
| `CarKeeper/Features/Map/MapSpineData.swift` | 把 AppStore 的真实字段翻译成地图画得出来的东西（每个字段注明来自哪个接口；没有数据就是 nil，不用默认值填空） |
| `CarKeeper/Features/Map/MapCarPin.swift` | 车钉（外面那圈弧就是电量、缺口就是真实 Heading）+ 停车/充电/异常三类小钉 |
| `CarKeeper/Features/Map/MapSpineView.swift` | 地图主屏：四个图层（现在/行程/停车/充电）+ 底部「为什么」面板 + 全部功能索引页 |
| `CarKeeper/CarKeeperApp.swift` | 首页 tab 指向 `MapSpineView`（想回到列表版：那一行换回 `HomeView()`） |
| `Features/Dev/DevView.swift` | 多了一个「旧版首页（对照）」入口 —— 任何新方向都该有一个可信的对照 |

**落地时守住的四条规则**（都在代码注释里写明了理由）：
1. **钉 = 屏幕空间**（`Annotation`），轨迹/面积 = 地理空间（`MapPolyline`）。
2. 地图样式只有一个来源：`ArtTheme.mapSpec`。换艺术主题 = 换真实 MapKit 配置。
3. **不做假数据**：行程没有轨迹点就写"起终点连线"，异常没有地点就写"发现时车在这儿"，充电站是实时搜索结果。
4. 控制长在对象上（面板里的四个入口直接进已有的车控/电池页），**不新写第二套车控**。

### 6.2 未实现（说清楚，别以为已经做了）

- **Annotation 的聚合**：几百个充电站钉需要聚合，SwiftUI `Map` 的聚合 API 我没核实到确定形状 → 现在只取最近 12 个（`prefix(12)`），这是权宜之计。
- **热区（面积类）**：`MapCircle` / `MapPolygon` 一个都还没接（花费、碳减排这些数据还没汇总到坐标上）。
- **行程回放（时间轴拖动）**：没有实现。
- **路网颜色**：仍然改不了（这是 Apple 的限制，不是没做）。
- **真机对比度定值**：下面 6.3 说的那一步还没做。

### 6.3 下一步（顺序不能颠倒）

1. **构建一次**，把 `MapSpineView` 跑起来 —— 静态检查过不代表能编译（这个项目已经栽过两次）。
2. 用**真截图**（不是设计稿）把三套 `MapStyleSpec` 各存一张，比较在真瓦片上的对比度。
3. 拿真截图定方向 —— 设计稿只能决定"看不看得懂结构"，决定不了"在真瓦片上还成不成立"。

---

## 7. 核实记录（本轮逐个核过的名字）

| 名字 | 结论 | 出处 |
|---|---|---|
| `MapStyle` | struct，iOS 17.0 | `/documentation/mapkit/mapstyle` |
| `MapStyle.standard(elevation:emphasis:pointsOfInterest:showsTraffic:)` | 签名一致 | mapstyle.json 的 topicSections |
| `MapStyle.Elevation.flat` | ✓ 存在 | `/mapkit/mapstyle/elevation/flat` |
| `MapStyle.StandardEmphasis.muted` | ✓ 存在 | `/mapkit/mapstyle/standardemphasis/muted` |
| `PointOfInterestCategories.excludingAll` | ✓ 存在，iOS 17.0 | `/mapkit/pointofinterestcategories/excludingall` |
| `MapPolygon` | struct，iOS 17.0 | `/documentation/mapkit/mappolygon` |
| `Annotation` | struct，iOS 17.0 | `/documentation/mapkit/annotation` |
| `MKStandardMapConfiguration` | class，iOS 16.0 | `/documentation/mapkit/mkstandardmapconfiguration` |
| `MKStandardMapConfiguration(elevationStyle:emphasisStyle:)` | 签名一致（`MKMapConfiguration.ElevationStyle` + `MKStandardMapConfiguration.EmphasisStyle`） | 该类的 init 页 |
| `MKPointOfInterestFilter` | class，iOS 13.0 | `/documentation/mapkit/mkpointofinterestfilter` |
| `MKPointOfInterestFilter.excludingAll` | ✓ 存在 | `/mapkit/mkpointofinterestfilter/excludingall` |
| `MKStandardMapConfiguration.EmphasisStyle.muted` | ✓ 存在（UIKit 侧） | `/mapkit/mkstandardmapconfiguration/emphasisstyle-swift.enum/muted` |
| `MapCamera` | struct，iOS 17.0 | `/documentation/mapkit/mapcamera` |
| `MapCamera.init(centerCoordinate:distance:heading:pitch:)` | 签名一致 | 该 init 页 |
| `MapCameraPosition` | struct，iOS 17.0；含 `.automatic` / `.camera` | `/documentation/mapkit/mapcameraposition` |
| `MapPolyline` 的创建器 | **只有四个**：`init(_ MKPolyline)` / `init(_ MKRoute)` / `init(coordinates:contourStyle:)` / `init(points:contourStyle:)`。文档里**没有** `init(coordinates:)` 这个符号 → 代码里改用已核实的 `init(_ MKPolyline)` | MapPolyline 的 topicSections |
| `MapContent.stroke(_:style:)` | ✓ 存在 | `/mapkit/mapcontent/stroke(_:style:)` |
| `Annotation` | struct，iOS 17.0 | `/documentation/mapkit/annotation` |
| `UnevenRoundedRectangle` | struct，iOS 16.0 | `/documentation/swiftui/unevenroundedrectangle` |

**一处由核实避免的踩坑**：`MapPolyline(coordinates: [...])` 是社区里最常见的写法，但 Apple 文档里
**没有这个符号**（只有带 `contourStyle` 的版本）。所以落地代码用的是 `MapPolyline(MKPolyline(coordinates:count:))` ——
那条路每个环节都核实过（`MKPolyline(coordinates:count:)` 项目里本来就在用）。

**未核实（所以本文档与代码里都没有写成结论）**：
SwiftUI `Map` 的标注聚合 API、`MKTileOverlay` 的许可细节条款、
`MapPolyline.ContourStyle` 的具体成员名。
凡未核实的一律标为"先查实再写"，不写成"我记得是"。

**登记动作**：以上新引入的 SDK 名字已经写进 `scan/scan.py` 的 `VERIFIED_SDK_ADDITIONS`
（那个文件的规矩是"登记前必须核实"），所以静态检查不会把它们报成未声明符号 ——
登记时每一条都带了核实依据。
