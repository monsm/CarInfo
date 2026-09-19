// =============================================================================
// BackgroundTaskManager — #NEW-109 BackgroundTasks 后台刷新
// 使用 BGTaskScheduler 在后台自动刷新车况数据
// =============================================================================

import Foundation
import BackgroundTasks

class BackgroundTaskManager {
    static let shared = BackgroundTaskManager()
    private let scheduler = BGTaskScheduler.shared
    
    private init() {
        registerTasks()
    }
    
    /// 注册后台任务
    func registerTasks() {
        // 注册车况刷新任务
        let refreshTask = BGAppRefreshTaskRequest(identifier: "com.carkeeper.refresh")
        refreshTask.earliestBeginDate = Date().addingTimeInterval(15 * 60) // 15分钟后首次执行
        refreshTask.periodic = true
        
        do {
            try scheduler.register(refreshTask) { [weak self] task in
                self?.handleAppRefresh(task)
            }
        } catch {
            print("Failed to register background task: \(error)")
        }
        
        // 注册长时间运行任务（用于充电状态监控）
        let longTask = BGAppRefreshTaskRequest(identifier: "com.carkeeper.longtask")
        longTask.earliestBeginDate = Date().addingTimeInterval(5 * 60)
        
        do {
            try scheduler.register(longTask) { [weak self] task in
                self?.handleLongTask(task)
            }
        } catch {
            print("Failed to register long task: \(error)")
        }
    }
    
    /// 处理应用刷新任务
    private func handleAppRefresh(_ task: BGTask) {
        // 请求下次执行时间
        task.taskCompleted()
        
        let refreshTask = BGAppRefreshTaskRequest(identifier: "com.carkeeper.refresh")
        refreshTask.earliestBeginDate = Date().addingTimeInterval(15 * 60)
        try? scheduler.register(refreshTask)
        
        // 执行实际的数据刷新逻辑
        Task { @MainActor in
            await AppStore.shared.fetchCore()
        }
    }
    
    /// 处理长时间运行任务
    private func handleLongTask(_ task: BGTask) {
        task.taskCompleted()
        
        let longTask = BGAppRefreshTaskRequest(identifier: "com.carkeeper.longtask")
        longTask.earliestBeginDate = Date().addingTimeInterval(30 * 60)
        try? scheduler.register(longTask)
    }
    
    /// 手动触发后台刷新（测试用）
    func scheduleRefresh() {
        let request = BGAppRefreshTaskRequest(identifier: "com.carkeeper.refresh")
        request.earliestBeginDate = Date().addingTimeInterval(60) // 1分钟后
        do {
            try scheduler.submit(request)
        } catch {
            print("Failed to submit background task: \(error)")
        }
    }
}
