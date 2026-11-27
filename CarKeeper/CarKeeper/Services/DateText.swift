import Foundation


final class DateText {

    static let shared = DateText()

    static let serverTimeZone: TimeZone = TimeZone(identifier: "Asia/Shanghai")
        ?? TimeZone(secondsFromGMT: 8 * 3600)
        ?? TimeZone.current

    private init() {}

    private var pool: [String: DateFormatter] = [:]
    private let lock = NSLock()

    private func formatter(_ format: String, locale: String?, timeZone: TimeZone?) -> DateFormatter {
        let key = "\(locale ?? "-")|\(timeZone?.identifier ?? "-")|\(format)"
        lock.lock()
        if let pooled = pool[key] {
            lock.unlock()
            return pooled
        }
        let f = DateFormatter()
        if let locale { f.locale = Locale(identifier: locale) }
        if let timeZone { f.timeZone = timeZone }
        f.dateFormat = format
        pool[key] = f
        lock.unlock()
        return f
    }

    func string(_ date: Date, _ format: String, locale: String? = nil, timeZone: TimeZone? = nil) -> String {
        formatter(format, locale: locale, timeZone: timeZone).string(from: date)
    }

    func date(_ text: String, formats: [String], locale: String? = nil, timeZone: TimeZone? = nil) -> Date? {
        for format in formats {
            if let d = formatter(format, locale: locale, timeZone: timeZone).date(from: text) {
                return d
            }
        }
        return nil
    }
}
