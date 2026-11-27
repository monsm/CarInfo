import Foundation


final class DateText {

    static let shared = DateText()

    private init() {}

    private var pool: [String: DateFormatter] = [:]
    private let lock = NSLock()

    func formatter(_ format: String, locale: String? = nil) -> DateFormatter {
        let key = "\(locale ?? "-")|\(format)"
        lock.lock()
        if let pooled = pool[key] {
            lock.unlock()
            return pooled
        }
        let f = DateFormatter()
        if let locale { f.locale = Locale(identifier: locale) }
        f.dateFormat = format
        pool[key] = f
        lock.unlock()
        return f
    }

    func string(_ date: Date, _ format: String, locale: String? = nil) -> String {
        formatter(format, locale: locale).string(from: date)
    }

    func date(_ text: String, formats: [String], locale: String? = nil) -> Date? {
        for f in formats {
            if let d = formatter(f, locale: locale).date(from: text) { return d }
        }
        return nil
    }
}
