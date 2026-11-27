import SwiftUI

enum SafeSymbol {
    private static var cache: [String: String] = [:]
    private static let lock = NSLock()

    static func name(_ requested: String, fallback: String = "questionmark.circle.fill") -> String {
        let key = requested + "|" + fallback
        lock.lock()
        defer { lock.unlock() }
        if let hit = cache[key] { return hit }
        let resolved = UIImage(systemName: requested) != nil ? requested : fallback
        cache[key] = resolved
        return resolved
    }
}

extension Image {
    init(safeSymbol name: String, fallback: String = "questionmark.circle.fill") {
        self.init(systemName: SafeSymbol.name(name, fallback: fallback))
    }
}




struct AppCanvas: View {
    var body: some View {
        TokensPalette.canvas
            .ignoresSafeArea()
            .allowsHitTesting(false)
    }
}


struct StatusDot: View {
    let cls: String
    var size: CGFloat = 8
    var body: some View {
        Circle()
            .fill(TokensPalette.statusColor(cls))
            .frame(width: size, height: size)
            .opacity(cls == "na" ? 0.35 : 1)
    }
}
