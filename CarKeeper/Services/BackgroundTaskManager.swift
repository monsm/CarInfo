// =============================================================================
// BackgroundTaskManager — #NEW-109 BackgroundTasks 后台刷新
// =============================================================================
//
// ⚠️ 两个硬约束（此前都没有满足，导致这段代码既从未生效、又埋着启动崩溃）：
// 1. BGTaskScheduler 要求标识符必须在 Info.plist 的 BGTaskSchedulerPermittedIdentifiers
//    里声明，否则 register / submit 会抛出 ObjC 异常（Swift 的 try? 抓不住）→ 进程直接被杀。
//    这里注册前先校验一次，没声明就安静跳过。
// 2. 同一个标识符不能注册两次，否则同样抛异常。用 didRegister 兜住。

import Foundation
import BackgroundTasks

class BackgroundTaskManager {
    static let shared = BackgroundTaskManager()

    /// 必须与 project.yml / Info.plist 的 BGTaskSchedulerPermittedIdentifiers 完全一致
    private static let refreshIdentifier = "com.carkeeper.refresh"
    private static let longTaskIdentifier = "com.carkeeper.longtask"

    private let scheduler = BGTaskScheduler.shared
    private var didRegister = false

    private init() {}

    /// Info.plist 中已声明的后台任务标识符
    private var declaredIdentifiers: [String] {
        (Bundle.main.object(forInfoDictionaryKey: "BGTaskSchedulerPermittedIdentifiers") as? [String]) ?? []
    }

    /// 注册后台任务（在 App 启动完成前调用一次即可，重复调用会被忽略）
    func registerTasks() {
        guard !didRegister else { return }
        let declared = declaredIdentifiers
        guard declared.contains(Self.refreshIdentifier), declared.contains(Self.longTaskIdentifier) else {
            NSLog("[CarKeeper] 未在 Info.plist 声明 BGTaskSchedulerPermittedIdentifiers，跳过后台刷新注册")
            return
        }
        didRegister = true

        scheduler.register(forTaskWithIdentifier: Self.refreshIdentifier, using: nil) { [weak self] task in
            self?.handleAppRefresh(task as? BGAppRefreshTask)
        }
        scheduler.register(forTaskWithIdentifier: Self.longTaskIdentifier, using: nil) { [weak self] task in
            self?.handleLongTask(task as? BGAppRefreshTask)
        }

        scheduleNextRefresh()
        scheduleNextLongTask()
    }

    private func handleAppRefresh(_ task: BGAppRefreshTask?) {
        guard let task else { return }
        scheduleNextRefresh()
        let work = Task { @MainActor in
            await AppStore.shared.fetchCore()
        }
        // 系统要收回后台时间：取消任务即可，完成上报统一放在下面，避免二次完成导致崩溃
        task.expirationHandler = { work.cancel() }
        Task {
            await work.value
            task.setTaskCompleted(success: !work.isCancelled)
        }
    }

    private func handleLongTask(_ task: BGAppRefreshTask?) {
        guard let task else { return }
        scheduleNextLongTask()
        task.setTaskCompleted(success: true)
    }

    private func scheduleNextRefresh() {
        let request = BGAppRefreshTaskRequest(identifier: Self.refreshIdentifier)
        request.earliestBeginDate = Date().addingTimeInterval(15 * 60)
        try? scheduler.submit(request)
    }

    private func scheduleNextLongTask() {
        let request = BGAppRefreshTaskRequest(identifier: Self.longTaskIdentifier)
        request.earliestBeginDate = Date().addingTimeInterval(30 * 60)
        try? scheduler.submit(request)
    }

    /// 手动触发后台刷新（测试用）
    func scheduleRefresh() {
        guard didRegister else { return }
        let request = BGAppRefreshTaskRequest(identifier: Self.refreshIdentifier)
        request.earliestBeginDate = Date()
        try? scheduler.submit(request)
    }
}
