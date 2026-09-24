import SwiftUI

// =============================================================================
//  MapSpineView · 底条的跟手拖（整条底条上按哪儿都能拖模式条）
// =============================================================================
//
//  与 `MapSpineReadouts.swift` / `MapSpineLayers.swift` 同一个理由 —— 拆给
//  `scan/lintcfg.py` 的 `file_length` 把守：骨架（`MapSpineView.swift`）一度涨到
//  1219 行（阈值 1200），差 19 行就红。这一轮拆完骨架约 1130 行。
//
//  这里只回答一件事：「手指按在整条底条上横向拖，模式条怎么跟手」——
//  是 `MapSpineView.bottomBar` 上挂的那条 `simultaneousGesture`。
//
//  注：下面用到的 `store` / `barRowWidth` / `barOpen` / `modePosition` 等
//  因此**不是 `private`**（或在本文件里重取 `AppStore.shared`）——
//  `private` 的作用域是文件，跨文件看不见。
// =============================================================================

extension MapSpineView {
    /// 底条整行的横向拖（用户 2026-09-24：「不跟手」→ 手指按在条子**任意位置**
    /// 都能拖，不只是胶囊上）。它不直接改条子的状态 —— 而是把「拖动的横向增量」
    /// 换算成条子内部的连续档位（`modePosition`），让条子自己跟手展开。
    ///
    /// 几何：按下时记下条子当时的档位（`modePosition`，哨兵 -1 时按记住的那一档画），
    /// 拖动中 = 档位起点 ± 增量 / 节距。节距 = 条宽 / 档数（5 个间隔分 `barRowWidth`，
    /// 两端各一档 —— 与 `DSSwipeStrip` 展开后的全行程同一物理量）。
    /// 手指往左拖 = 看左边的档（出行/车辆），往右拖 = 看右边的档（充电/车控/我的）。
    ///
    /// 为什么用 `simultaneousGesture` 而不是 `highPriorityGesture`：两侧圆钮是 `Button`，
    /// 用 `highPriority` 会把圆钮的 tap 也吃掉（点不动了）。`simultaneous` 让两件事并存：
    /// 轻点（位移 < 8pt）= 圆钮的 tap / 条子的点选；横拖（位移 > 8pt）= 条子展开跟手。
    /// 圆钮的 tap 由 `Button` 自己消费，横拖由这条手势消费 —— 互不冲突。
    @State private var barDragBase: Double?

    /// 不是 `private`：`MapSpineView.bottomBar`（骨架文件）挂在整条上要用它。
    var bottomBarDrag: some Gesture {
        DragGesture(minimumDistance: 0, coordinateSpace: .local)
            .onChanged { v in
                guard barRowWidth > 0 else { return }
                // 只有横拖才算（竖向 / 斜向让给地图）。
                guard abs(v.translation.width) > abs(v.translation.height) else { return }
                if barDragBase == nil {
                    // 按下时的档位：哨兵 -1（还没被条子回调过）就按记住的那一档画。
                    barDragBase = modePosition >= 0 ? modePosition : Double(modeIndex)
                }
                guard let base = barDragBase else { return }
                // 节距 = 条宽 / 5 个间隔（6 档）。拖 1 个节距 = 移动一档。
                let n = max(1, HomeMode.allCases.count - 1)
                let pitch = barRowWidth / CGFloat(n)
                let pos = (base - Double(v.translation.width / pitch))
                    .clamped(to: 0...Double(n))
                modePosition = pos
                // 拖过 8pt 才算「拖」：同时把条子展开（圆钮让位），与 DSSwipeStrip
                // 自己的「按下就展开」是同一件事的两种触发（它管按在胶囊上，
                // 这条管按在整条上）。
                if abs(v.translation.width) > 8, !barOpen {
                    withAnimation(TokensMotion.fade) { barOpen = true }
                }
            }
            .onEnded { _ in
                // 松手：档位停在手指停的地方（`modePosition` 已经跟手到位），
                // 档位的**写回**（`homeModeRaw`）交给 `DSSwipeStrip` 自己的吸附
                //（它每帧都在用 `pvValue` 读 `c`，而 `c` 由 `onPosition` 驱动 ——
                //  两条手势改的是同一个连续量，不会打架）。
                barDragBase = nil
            }
    }

    /// 双向夹：Swift 标准库没有 `Double.clamped(to:)`，就地补一个。
    /// `private`（文件级）：只本文件这条手势用，不与别处撞名。
    private extension Double {
        func clamped(to range: ClosedRange<Double>) -> Double {
            Swift.min(Swift.max(self, range.lowerBound), range.upperBound)
        }
    }
}
