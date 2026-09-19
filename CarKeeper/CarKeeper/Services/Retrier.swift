import Foundation

// 全局自动重试机制。
//
// 设计目标：
// - 所有网络请求（认证 / 数据 / 车控）统一走 `retrying`，
//   由它负责「可重试错误」的指数退避 + 抖动自动重发；
// - 只有「可重试」的错误才重试（网络中断 / 超时 / 5xx / 连接被重置）；
//   业务层错误（4xx、token 过期、短信「码不匹配」等）绝不重试，避免副作用；
// - 可配置最大次数、基础延迟、退避倍数、抖动幅度；
// - 提供全局默认策略 `Retrier.global`，以及单次调用覆盖。

struct RetryPolicy {
    /// 最大尝试次数（包含首次），>=1。
    var maxAttempts: Int
    /// 首次重试前的基础延迟（秒）。
    var baseDelay: TimeInterval
    /// 每次重试的退避倍数（指数）。
    var backoff: Double
    /// 最大延迟上限（秒），避免无限拉长。
    var maxDelay: TimeInterval
    /// 抖动比例 0...1，实际延迟 = base * backoff^n * (1 + jitter * random)。
    var jitter: Double

    init(maxAttempts: Int, baseDelay: TimeInterval, backoff: Double, maxDelay: TimeInterval, jitter: Double) {
        self.maxAttempts = maxAttempts
        self.baseDelay = baseDelay
        self.backoff = backoff
        self.maxDelay = maxDelay
        self.jitter = jitter
    }

    /// 全局默认：#10 指数退避加固 — 1s→2s→4s→8s，最多 4 次重试
    /// 弱网下单请求最坏 ≈ 15s + 1s + 2s + 4s + 8s + 15s ≈ 45s，比原来 31.5s 更宽容
    static let `default` = RetryPolicy(maxAttempts: 4, baseDelay: 1.0, backoff: 2.0, maxDelay: 8.0, jitter: 0.3)
    /// 只跑一次，绝不重试。用于有副作用的接口（发短信、车控）。
    static let none = RetryPolicy(maxAttempts: 1, baseDelay: 0, backoff: 1, maxDelay: 0, jitter: 0)
    /// 激进一点：更多次数，适合弱网环境的数据拉取。
    static let aggressive = RetryPolicy(maxAttempts: 6, baseDelay: 0.5, backoff: 1.8, maxDelay: 12.0, jitter: 0.5)
    /// 仅数据拉取用：3 次，2s→4s→8s 退避，适合对实时性要求不高但需要可靠性的接口
    static let dataReliable = RetryPolicy(maxAttempts: 3, baseDelay: 2.0, backoff: 2.0, maxDelay: 8.0, jitter: 0.2)
}

/// 判断一个错误是否「可重试」。
enum Retryable {
    /// 网络层错误：URLSession 抛的 URLError、超时、连接重置等。
    static func isNetworkError(_ e: Error) -> Bool {
        if let urlErr = e as? URLError {
            // .timedOut / .networkConnectionLost / .notConnectedToInternet /
            // .cancelled（被系统 cancel）/ .cannotConnectToHost / .dnsLookupFailed
            switch urlErr.code {
            case .timedOut, .networkConnectionLost, .notConnectedToInternet,
                 .cannotConnectToHost, .dnsLookupFailed, .resourceUnavailable:
                return true
            default:
                return false
            }
        }
        if e is CancellationError { return true }
        return false
    }

    /// 业务层 APIError：只有 5xx（服务端瞬时故障）视为可重试；
    /// 4xx、token 过期、noRefresh 一律不重试。
    static func isAPIErrorRetryable(_ e: Error) -> Bool {
        guard let apiErr = e as? APIError else { return false }
        if apiErr.expired || apiErr.noRefresh { return false }
        if let sc = apiErr.statusCode { return (500..<600).contains(sc) }
        return false
    }

    /// 统一入口：网络错误或可重试的 APIError 都返回 true。
    static func isRetryable(_ e: Error) -> Bool {
        isNetworkError(e) || isAPIErrorRetryable(e)
    }
}

/// 全局自动重试器。无状态，可安全跨任务共享。
struct Retrier {
    /// 全局默认策略。生产 App 直接用它；特定调用可传自己的 policy 覆盖。
    static let global = Retrier(policy: .default)

    let policy: RetryPolicy

    init(policy: RetryPolicy) { self.policy = policy }

    /// 执行一个异步动作；遇到可重试错误按策略自动重发。
    ///
    /// - `label`：用于日志标识调用来源（如 "getControl"），帮助排查。
    /// - `maxAttemptsOverride`：单次覆盖最大尝试次数；传 nil 用策略默认。
    @discardableResult
    func retrying<T>(
        _ action: @escaping (Int) async throws -> T,
        label: String = "request",
        maxAttemptsOverride: Int? = nil
    ) async throws -> T {
        let maxAttempts = max(1, maxAttemptsOverride ?? policy.maxAttempts)

        var lastError: Error?
        for attempt in 1...maxAttempts {
            do {
                return try await action(attempt)
            } catch {
                lastError = error
                let isRetryable = Retryable.isRetryable(error)
                if !isRetryable || attempt == maxAttempts {
                    throw error
                }
                // 计算带抖动的延迟
                let base = policy.baseDelay * pow(policy.backoff, Double(attempt - 1))
                let capped = min(base, policy.maxDelay)
                let jittered = policy.jitter > 0
                    ? capped * (1.0 + Double.random(in: 0...policy.jitter))
                    : capped
                let delay = jittered.clamp(to: 0.1...30.0)
                NSLog("[Retrier] \(label) attempt \(attempt)/\(maxAttempts) failed (retryable), backoff %.2fs", delay)
                try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
                // 若任务被取消，立刻抛出，不再等待。
                if Task.isCancelled {
                    throw CancellationError()
                }
            }
        }
        throw lastError ?? APIError(message: "重试失败")
    }

    /// 便捷版：包装一个普通 `() async throws -> T` 闭包（忽略 attempt 序号）。
    func run<T>(_ body: @escaping () async throws -> T, label: String = "request") async throws -> T {
        try await retrying({ _ in try await body() }, label: label)
    }
}

extension Comparable {
    func clamp(to range: ClosedRange<Self>) -> Self {
        min(max(self, range.lowerBound), range.upperBound)
    }
}
