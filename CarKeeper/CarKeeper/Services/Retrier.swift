import Foundation


struct RetryPolicy {
    var maxAttempts: Int
    var baseDelay: TimeInterval
    var backoff: Double
    var maxDelay: TimeInterval
    var jitter: Double

    init(maxAttempts: Int, baseDelay: TimeInterval, backoff: Double, maxDelay: TimeInterval, jitter: Double) {
        self.maxAttempts = maxAttempts
        self.baseDelay = baseDelay
        self.backoff = backoff
        self.maxDelay = maxDelay
        self.jitter = jitter
    }

    static let `default` = RetryPolicy(maxAttempts: 4, baseDelay: 1.0, backoff: 2.0, maxDelay: 8.0, jitter: 0.3)
}

enum Retryable {
    static func isNetworkError(_ e: Error) -> Bool {
        if let urlErr = e as? URLError {
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

    static func isAPIErrorRetryable(_ e: Error) -> Bool {
        guard let apiErr = e as? APIError else { return false }
        if apiErr.expired || apiErr.noRefresh { return false }
        if let sc = apiErr.statusCode { return (500..<600).contains(sc) }
        return false
    }

    static func isRetryable(_ e: Error) -> Bool {
        isNetworkError(e) || isAPIErrorRetryable(e)
    }
}

struct Retrier {
    static let global = Retrier(policy: .default)

    let policy: RetryPolicy

    init(policy: RetryPolicy) { self.policy = policy }

    @discardableResult
    func retrying<T>(
        _ action: @escaping (Int) async throws -> T,
        label: String = "request"
    ) async throws -> T {
        let maxAttempts = max(1, policy.maxAttempts)

        for attempt in 1...maxAttempts {
            do {
                return try await action(attempt)
            } catch {
                let isRetryable = Retryable.isRetryable(error)
                if !isRetryable || attempt == maxAttempts {
                    throw error
                }
                let base = policy.baseDelay * pow(policy.backoff, Double(attempt - 1))
                let capped = min(base, policy.maxDelay)
                let jittered = policy.jitter > 0
                    ? capped * (1.0 + Double.random(in: 0...policy.jitter))
                    : capped
                let delay = jittered.clamp(to: 0.1...30.0)
                NSLog("[Retrier] \(label) attempt \(attempt)/\(maxAttempts) failed (retryable), backoff %.2fs", delay)
                try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
                if Task.isCancelled {
                    throw CancellationError()
                }
            }
        }
        throw APIError(message: "重试失败")
    }

    func run<T>(_ body: @escaping () async throws -> T, label: String = "request") async throws -> T {
        try await retrying({ _ in try await body() }, label: label)
    }
}

extension Comparable {
    func clamp(to range: ClosedRange<Self>) -> Self {
        min(max(self, range.lowerBound), range.upperBound)
    }
}
