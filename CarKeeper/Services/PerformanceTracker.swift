// =============================================================================
// #NEW-137 性能埋点增强 — 页面停留时长、API调用统计
// =============================================================================

import Foundation

struct PerformanceMetric: Codable {
    let page: String
    let duration: TimeInterval  // 停留时长（秒）
    let timestamp: Date
}

struct APIStatistic: Codable {
    let endpoint: String
    let duration: TimeInterval
    let success: Bool
    let timestamp: Date
}

class PerformanceTracker : ObservableObject {
    static let shared = PerformanceTracker()
    
    private var pageStartTimes: [String: Date] = [:]
    private var pageMetrics: [PerformanceMetric] = []
    private var apiStats: [APIStatistic] = []
    
    private init() {}

    /// 首页最近一次加载耗时（秒），供性能报告展示
    var homeLoadTime: Double {
        pageMetrics.last(where: { $0.page == "Home" || $0.page == "首页" })?.duration ?? 0
    }

    /// 开始页面计时
    func startPageTimer(_ page: String) {
        pageStartTimes[page] = Date()
    }
    
    /// 结束页面计时并记录
    func endPageTimer(_ page: String) {
        guard let startTime = pageStartTimes.removeValue(forKey: page) else { return }
        let duration = Date().timeIntervalSince(startTime)
        let metric = PerformanceMetric(page: page, duration: duration, timestamp: Date())
        pageMetrics.append(metric)
        
        // 只保留最近100条
        if pageMetrics.count > 100 {
            pageMetrics = Array(pageMetrics.suffix(100))
        }
        
        // 保存到 UserDefaults
        saveMetrics()
    }
    
    /// 记录 API 调用
    func recordAPI(_ endpoint: String, duration: TimeInterval, success: Bool) {
        let stat = APIStatistic(endpoint: endpoint, duration: duration, success: success, timestamp: Date())
        apiStats.append(stat)
        
        if apiStats.count > 200 {
            apiStats = Array(apiStats.suffix(200))
        }
        
        saveMetrics()
    }
    
    /// 获取统计数据
    func getPageMetrics() -> [PerformanceMetric] {
        return pageMetrics
    }
    
    func getAPIStats() -> [APIStatistic] {
        return apiStats
    }
    
    /// 计算平均页面停留时长
    func averagePageDuration(_ page: String) -> TimeInterval? {
        let metrics = pageMetrics.filter { $0.page == page }
        guard !metrics.isEmpty else { return nil }
        return metrics.map { $0.duration }.reduce(0, +) / Double(metrics.count)
    }
    
    /// 计算 API 成功率
    func apiSuccessRate() -> Double? {
        guard !apiStats.isEmpty else { return nil }
        let successCount = apiStats.filter { $0.success }.count
        return Double(successCount) / Double(apiStats.count)
    }
    
    private func saveMetrics() {
        if let data = try? JSONEncoder().encode(pageMetrics) {
            UserDefaults.standard.set(data, forKey: "carkeeper_page_metrics")
        }
        if let data = try? JSONEncoder().encode(apiStats) {
            UserDefaults.standard.set(data, forKey: "carkeeper_api_stats")
        }
    }
    
    private func loadMetrics() {
        if let data = UserDefaults.standard.data(forKey: "carkeeper_page_metrics"),
           let metrics = try? JSONDecoder().decode([PerformanceMetric].self, from: data) {
            pageMetrics = metrics
        }
        if let data = UserDefaults.standard.data(forKey: "carkeeper_api_stats"),
           let stats = try? JSONDecoder().decode([APIStatistic].self, from: data) {
            apiStats = stats
        }
    }
}
