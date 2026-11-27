import SwiftUI
import Foundation
import UIKit
import PhotosUI

enum WallpaperSource: String, CaseIterable, Identifiable {
    case photo
    case bing
    case spotlight

    var id: String { rawValue }

    var title: String {
        switch self {
        case .photo: return "相册自选"
        case .bing: return "必应每日"
        case .spotlight: return "Windows 聚焦"
        }
    }

    var segmentTitle: String {
        switch self {
        case .photo: return "相册"
        case .bing: return "必应"
        case .spotlight: return "聚焦"
        }
    }

    var note: String {
        switch self {
        case .photo: return "自己从相册挑一张，存在本机"
        case .bing: return "必应首页当天那张，每天自动换"
        case .spotlight: return "Windows 锁屏那套图，每天自动换"
        }
    }

    var isRemote: Bool { self != .photo }
}

@MainActor
final class WallpaperService: ObservableObject, @unchecked Sendable {
    static let shared = WallpaperService()

    @Published private(set) var image: UIImage?
    @Published private(set) var source: WallpaperSource
    @Published private(set) var credit: String
    @Published private(set) var failed: Bool

    private enum Key {
        static let source = "carkeeper_wallpaper_source"
        static let stamp = "carkeeper_wallpaper_stamp"
        static let credit = "carkeeper_wallpaper_credit"
    }

    private static let imageFile = "carkeeper-wallpaper.jpg"

    private static let bingIndex =
        "https://www.bing.com/HPImageArchive.aspx?format=js&idx=0&n=1&mkt=zh-CN"
    private static let spotlightIndex =
        "https://fd.api.iris.microsoft.com/v4/api/selection?placement=88000820&bcnt=4&country=cn&locale=zh-cn&fmt=json"

    private init() {
        source = WallpaperSource(rawValue: UserDefaults.standard.string(forKey: Key.source) ?? "")
            ?? .photo
        credit = UserDefaults.standard.string(forKey: Key.credit) ?? ""
        failed = false
        if let data = Self.readDisk(), let img = UIImage(data: data) {
            image = img
        } else {
            image = nil
        }
    }


    func use(_ new: WallpaperSource) {
        guard new != source else { return }
        source = new
        UserDefaults.standard.set(new.rawValue, forKey: Key.source)
        failed = false
        switch new {
        case .photo:
            credit = ""
            UserDefaults.standard.removeObject(forKey: Key.credit)
            loadFromDisk()
        case .bing, .spotlight:
            Task { await refresh(force: true) }
        }
    }

    func reload() {
        Task { await refresh(force: true) }
    }

    func setPhoto(_ data: Data?) {
        source = .photo
        UserDefaults.standard.set(WallpaperSource.photo.rawValue, forKey: Key.source)
        credit = ""
        failed = false
        UserDefaults.standard.removeObject(forKey: Key.credit)
        guard let data, let jpeg = UIImage(data: data)?.jpegData(compressionQuality: 0.9) else {
            image = nil
            Self.removeDisk()
            return
        }
        Self.writeDisk(jpeg)
        image = UIImage(data: jpeg)
    }

    func clear() {
        image = nil
        credit = ""
        failed = false
        source = .photo
        UserDefaults.standard.set(WallpaperSource.photo.rawValue, forKey: Key.source)
        UserDefaults.standard.removeObject(forKey: Key.stamp)
        UserDefaults.standard.removeObject(forKey: Key.credit)
        Self.removeDisk()
    }


    func refreshIfStale() async {
        guard source.isRemote else { return }
        if image == nil || UserDefaults.standard.integer(forKey: Key.stamp) != Self.dayStamp() {
            await refresh(force: false)
        }
    }

    func refresh(force: Bool) async {
        guard source.isRemote else { return }
        let today = Self.dayStamp()
        if !force, UserDefaults.standard.integer(forKey: Key.stamp) == today, image != nil { return }
        let kind = source
        var indexURL = Self.spotlightIndex
        if kind == .bing { indexURL = Self.bingIndex }
        do {
            let index = try await Self.fetch(URL(string: indexURL), timeout: Self.indexTimeout)
            let picks: [RemotePick]
            if kind == .bing {
                picks = Self.bingPick(from: index).map { [$0] } ?? []
            } else {
                picks = Self.spotlightPicks(from: index, stamp: today)
            }
            guard !picks.isEmpty else {
                failed = true
                return
            }
            var success = false
            for pick in picks.prefix(3) {
                guard let imgURL = URL(string: pick.url) else { continue }
                guard let bytes = try? await Self.fetch(imgURL, timeout: Self.imageTimeout),
                      let decoded = UIImage(data: bytes) else { continue }
                Self.writeDisk(bytes)
                image = decoded
                credit = pick.credit
                UserDefaults.standard.set(today, forKey: Key.stamp)
                UserDefaults.standard.set(pick.credit, forKey: Key.credit)
                success = true
                break
            }
            failed = !success
        } catch {
            failed = true
        }
    }

    private static func dayStamp() -> Int {
        Int(Date().timeIntervalSince1970 / 86_400)
    }


    private static func fetch(_ url: URL?, timeout: TimeInterval = 12) async throws -> Data {
        guard let url else { throw URLError(.badURL) }
        var req = URLRequest(url: url)
        req.timeoutInterval = timeout
        req.setValue("CarKeeper/1.0 (iOS)", forHTTPHeaderField: "User-Agent")
        let (data, resp) = try await URLSession.shared.data(for: req)
        if let http = resp as? HTTPURLResponse, http.statusCode != 200 {
            throw URLError(.badServerResponse)
        }
        return data
    }

    private static let indexTimeout: TimeInterval = 12
    private static let imageTimeout: TimeInterval = 45

    private struct RemotePick {
        let url: String
        let credit: String
    }

    private static func bingPick(from data: Data) -> RemotePick? {
        guard let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let images = obj["images"] as? [[String: Any]],
              let first = images.first,
              let base = first["urlbase"] as? String else { return nil }
        let credit = (first["copyright"] as? String) ?? ""
        return RemotePick(url: "https://www.bing.com" + base + "_1920x1080.jpg", credit: credit)
    }

    private static func spotlightPicks(from data: Data, stamp: Int) -> [RemotePick] {
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let batch = root["batchrsp"] as? [String: Any],
              let items = batch["items"] as? [[String: Any]] else { return [] }
        var picks: [RemotePick] = []
        for it in items {
            guard let text = it["item"] as? String,
                  let inner = try? JSONSerialization.jsonObject(with: Data(text.utf8)) as? [String: Any],
                  let ad = inner["ad"] as? [String: Any],
                  let url = assetURL(in: ad) else { continue }
            let credit = (ad["copyright"] as? String) ?? (ad["title"] as? String) ?? ""
            picks.append(RemotePick(url: url, credit: credit))
        }
        guard !picks.isEmpty else { return [] }
        let start = max(0, stamp) % picks.count
        return Array(picks[start...]) + Array(picks[..<start])
    }

    private static func assetURL(in ad: [String: Any]) -> String? {
        for name in ["landscapeImage", "portraitImage", "squareImage"] {
            if let asset = ad[name] as? [String: Any],
               let s = asset["asset"] as? String, s.hasPrefix("http") {
                return s
            }
        }
        for value in ad.values {
            guard let asset = value as? [String: Any] else { continue }
            for key in ["asset", "u", "url"] {
                guard let s = asset[key] as? String else { continue }
                if s.hasPrefix("http") { return s }
            }
        }
        return nil
    }


    private func loadFromDisk() {
        guard let data = Self.readDisk() else { image = nil; return }
        image = UIImage(data: data)
    }

    private static func fileURL() -> URL? {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first?
            .appendingPathComponent(imageFile)
    }

    private static func readDisk() -> Data? {
        guard let url = fileURL() else { return nil }
        return try? Data(contentsOf: url)
    }

    private static func writeDisk(_ data: Data) {
        guard let url = fileURL() else { return }
        try? data.write(to: url, options: .atomic)
    }

    private static func removeDisk() {
        guard let url = fileURL() else { return }
        try? FileManager.default.removeItem(at: url)
    }
}
