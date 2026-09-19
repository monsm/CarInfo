// =============================================================================
// BackgroundTaskManager — #NEW-109 BackgroundTasks 后台刷新
// =============================================================================

import Foundation
import BackgroundTasks

class BackgroundTaskManager {
    static let shared = BackgroundTaskManager()
    private let scheduler = BGTaskScheduler.shared
    
    private init() {}
    
    /// 注册后台任务
    func registerTasks() {
        let refreshRequest = BGAppRefreshTaskRequest(identifier: "com.carkeeper.refresh")
        refreshRequest.earliestBeginDate = Date().addingTimeInterval(15 * 60)
        
        _ = scheduler.register(forTaskWithIdentifier: "com.carkeeper.refresh", using: nil) { [weak self] task in
            self?.handleAppRefresh(task as? BGAppRefreshTask)
        }
        
        let longRequest = BGAppRefreshTaskRequest(identifier: "com.carkeeper.longtask")
        longRequest.earliestBeginDate = Date().addingTimeInterval(5 * 60)
        
        _ = scheduler.register(forTaskWithIdentifier: "com.carkeeper.longtask", using: nil) { [weak self] task in
            self?.handleLongTask(task as? BGAppRefreshTask)
        }
    }
    
    private func handleAppRefresh(_ task: BGAppRefreshTask?) {
        guard let task else { return }
        scheduleNextRefresh()
        Task { @MainActor in
            await AppStore.shared.fetchCore()
        }
        task.setTaskCompleted(success: true)
    }
    
    private func handleLongTask(_ task: BGAppRefreshTask?) {
        guard let task else { return }
        scheduleNextLongTask()
        task.setTaskCompleted(success: true)
    }
    
    private func scheduleNextRefresh() {
        let request = BGAppRefreshTaskRequest(identifier: "com.carkeeper.refresh")
        request.earliestBeginDate = Date().addingTimeInterval(15 * 60)
        try? scheduler.submit(request)
    }
    
    private func scheduleNextLongTask() {
        let request = BGAppRefreshTaskRequest(identifier: "com.carkeeper.longtask")
        request.earliestBeginDate = Date().addingTimeInterval(30 * 60)
        try? scheduler.submit(request)
    }
    
    /// 手动触发后台刷新（测试用）
    func scheduleRefresh() {
        let request = BGAppRefreshTaskRequest(identifier: "com.carkeeper.refresh")
        request.earliestBeginDate = Date()
        try? scheduler.submit(request)
    }
}
