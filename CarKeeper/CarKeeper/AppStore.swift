import SwiftUI
import Observation
import Foundation
import CoreLocation
import Intents
import UserNotifications
import LocalAuthentication
import CoreHaptics
import AVFoundation
import Photos


@MainActor
@Observable
final class AppStore: @unchecked Sendable {
    static let shared = AppStore()

    var isLoggedIn: Bool = false
    var phone: String = ""
    var cars: [[String: Any]] = []
    var carId: String = ""
    var car: [String: Any]? = nil
    var user: [String: Any]? = nil

    var caches: [String: Any?] = [
        "charge": nil, "pm25": nil, "location": nil,
        "control": nil, "check": nil, "messages": nil
    ]

    private var cacheTimes: [String: Date] = [:]

    func cacheTime(_ key: String) -> Date? { cacheTimes[key] }

    private(set) var lastMissedSources: [String] = []

    private var lastPostedLat = Double.nan
    private var lastPostedLng = Double.nan

    var commandHistory: [HistoryEntry] = []
    struct HistoryEntry: Identifiable {
        let id = UUID()
        let cmd: String
        let name: String
        let startedAt: Date
        let finishedAt: Date?
        let success: Bool
        let confirmed: Bool
        let duration: TimeInterval

        var statusColor: Color {
            if !confirmed { return TokensPalette.warning }
            return success ? TokensPalette.success : TokensPalette.error
        }
        var iconName: String {
            if !confirmed { return "questionmark.circle.fill" }
            return success ? "checkmark.circle.fill" : "xmark.circle.fill"
        }
        var resultText: String {
            if !confirmed { return "未确认" }
            return success ? "成功" : "失败"
        }
        var statusCls: String {
            if !confirmed { return "na" }
            return success ? "ok" : "bad"
        }
        var durationText: String {
            guard duration > 0 else { return "--" }
            if duration < 60 { return String(format: "%.1fs", duration) }
            return "\(Int(duration / 60))min"
        }
    }

    func addCommandHistory(cmd: String, name: String, success: Bool,
                           duration: TimeInterval, confirmed: Bool = true) {
        commandHistory.insert(HistoryEntry(cmd: cmd, name: name,
                                          startedAt: Date().advanced(by: -duration),
                                          finishedAt: Date(), success: success,
                                          confirmed: confirmed, duration: duration), at: 0)
        if commandHistory.count > 50 { commandHistory = Array(commandHistory.prefix(50)) }
    }

    nonisolated static let lastServiceMileageKey = "carkeeper_last_service_mileage"

    nonisolated static let currentMileageKey = "carkeeper_current_mileage"

    nonisolated static let selectedCarIdKey = "carkeeper_selected_car_id"

    var lastServiceMileage: Int {
        get { UserDefaults.standard.integer(forKey: Self.lastServiceMileageKey) }
        set { UserDefaults.standard.set(newValue, forKey: Self.lastServiceMileageKey) }
    }
    nonisolated static let defaultServiceInterval: Int = 10000

    nonisolated static let servicePriceEstimate: Int = 800
    static let majorServicePriceEstimate: Int = 2500

    struct EnergyRecord: Identifiable {
        let id = UUID()
        let timestamp: Date
        let soc: Int
        let range: Int
    }
    var energyHistory: [EnergyRecord] = []

    struct ChargingPowerRecord: Identifiable {
        let id = UUID()
        let time: Date
        let power: Double
    }
    var chargingPowerHistory: [ChargingPowerRecord] = []

    struct TripRecord: Identifiable {
        let id = UUID()
        let startTime: Date
        let endTime: Date?
        let startLocation: CLLocation?
        let endLocation: CLLocation?
        let distanceKm: Double
        var durationText: String {
            let dur = (endTime?.timeIntervalSince(startTime) ?? 0) / 60
            return dur > 0 ? "\(Int(dur))min" : "--"
        }
        let startSoc: Int
        let endSoc: Int
        let avgEfficiency: Double?
        let kmPerPercent: Double?

        var startAddr: String = ""
        var endAddr: String = ""
    }
    var tripHistory: [TripRecord] = []
    private var currentTrip: (startTime: Date, startSoc: Int,
                              startLocation: CLLocation?, startMileage: Int?,
                              startAddr: String)? = nil

    var parkingLocation: CLLocation? {
        get { if let data = UserDefaults.standard.data(forKey: "carkeeper_parking_loc"), let loc = try? NSKeyedUnarchiver.unarchivedObject(ofClass: CLLocation.self, from: data) { return loc } else { return nil } }
        set {
            guard let loc = newValue else {
                UserDefaults.standard.removeObject(forKey: "carkeeper_parking_loc")
                return
            }
            if let data = try? NSKeyedArchiver.archivedData(withRootObject: loc, requiringSecureCoding: true) {
                UserDefaults.standard.set(data, forKey: "carkeeper_parking_loc")
            }
        }
    }
    var lastParkingTime: Date? {
        get { UserDefaults.standard.object(forKey: "carkeeper_parking_time") as? Date }
        set { UserDefaults.standard.set(newValue, forKey: "carkeeper_parking_time") }
    }


    var isOfflineMode: Bool = false

    struct MapFocus: Equatable, Identifiable {
        let lat: Double
        let lng: Double
        let label: String
        var id: String { "\(lat),\(lng)" }
    }
    var mapFocus: MapFocus? = nil



    func recordEnergySnapshot(soc: Int, rangeKm: Int) {
        let recent = energyHistory.filter { Date().timeIntervalSince($0.timestamp) < 60 }
        guard recent.isEmpty else { return }
        energyHistory.append(EnergyRecord(timestamp: Date(), soc: soc, range: rangeKm))
        if energyHistory.count > 20 { energyHistory = Array(energyHistory.suffix(20)) }
    }

    struct ParkingPoint: Codable {
        let lat: Double
        let lng: Double
        let time: Date
        let address: String
    }
    nonisolated static let parkingPointsKey = "carkeeper_parking_points"

    var parkingPoints: [ParkingPoint] {
        get {
            guard let data = UserDefaults.standard.data(forKey: Self.parkingPointsKey),
                  let list = try? JSONDecoder().decode([ParkingPoint].self, from: data) else { return [] }
            return list
        }
        set {
            let capped = Array(newValue.suffix(200))
            if let data = try? JSONEncoder().encode(capped) {
                UserDefaults.standard.set(data, forKey: Self.parkingPointsKey)
            }
        }
    }

    func saveParkingLocation(_ location: CLLocation?, at time: Date? = nil, address: String = "") {
        parkingLocation = location
        lastParkingTime = time ?? Date()
        guard let c = location?.coordinate else { return }
        var points = parkingPoints
        if let last = points.last {
            let d = CLLocation(latitude: last.lat, longitude: last.lng)
                .distance(from: CLLocation(latitude: c.latitude, longitude: c.longitude))
            if d < 120 { return }
        }
        points.append(ParkingPoint(lat: c.latitude, lng: c.longitude,
                                   time: time ?? Date(), address: address))
        parkingPoints = points
    }

    func startTrip(_ location: CLLocation? = nil, soc: Int? = nil,
                   at time: Date? = nil, mileage: Int? = nil, addr: String = "") {
        let currentSoc = soc ?? (energyHistory.last?.soc ?? 0)
        currentTrip = (startTime: time ?? Date(), startSoc: currentSoc,
                       startLocation: location, startMileage: mileage, startAddr: addr)
        DriveTrace.shared.begin()
    }

    func endTrip(distanceKm: Double, endSoc: Int? = nil,
                 endLocation: CLLocation? = nil, at time: Date? = nil,
                 endAddr: String = "") -> TripRecord? {
        guard let trip = currentTrip else { return nil }
        let endSoc = endSoc ?? (energyHistory.last?.soc ?? 0)
        let socUsed = trip.startSoc - endSoc
        let kmPerPercent: Double? = (socUsed > 0 && distanceKm > 0)
            ? distanceKm / Double(socUsed) : nil
        let record = TripRecord(
            startTime: trip.startTime,
            endTime: time ?? Date(),
            startLocation: trip.startLocation,
            endLocation: endLocation,
            distanceKm: distanceKm,
            startSoc: trip.startSoc,
            endSoc: endSoc,
            avgEfficiency: nil,
            kmPerPercent: kmPerPercent,
            startAddr: trip.startAddr,
            endAddr: endAddr
        )
        tripHistory.insert(record, at: 0)
        if tripHistory.count > 50 { tripHistory = Array(tripHistory.prefix(50)) }
        currentTrip = nil
        DriveTrace.shared.end()
        return record
    }


    private var processedEventIds: Set<String> {
        get { Set(UserDefaults.standard.stringArray(forKey: "carkeeper_processed_event_ids") ?? []) }
        set { UserDefaults.standard.set(Array(newValue.suffix(2000)),
                                        forKey: "carkeeper_processed_event_ids") }
    }

    nonisolated static func jumpParams(_ m: [String: Any]) -> [String: Any] {
        guard let raw = ciString(m, ["JumpParam", "jumpParam"]), !raw.isEmpty,
              let obj = jsonToAny(raw) else { return [:] }
        return (obj["uriParams"] as? [String: Any]) ?? obj
    }

    func ingestEvents(_ messages: [[String: Any]]) {
        guard !carId.isEmpty else { return }
        var seen = processedEventIds
        let events = messages.compactMap { m -> (id: String, ignition: Bool, at: Date,
                                                  loc: CLLocation?, addr: String)? in
            guard let kind = ciString(m, ["InfoTypeId", "infoTypeId"])?.uppercased(),
                  kind == "IGNITION" || kind == "FLAMEOUT" else { return nil }
            let id = ciString(m, ["StubId", "stubId"]) ?? ciString(m, ["Id", "id"]) ?? ""
            guard !id.isEmpty, !seen.contains(id) else { return nil }
            let p = Self.jumpParams(m)
            guard let at = VM.serverDate(p["gpsTime"])
                    ?? VM.serverDate(ciPick(m, ["CreatedAt", "createdAt"])) else { return nil }
            var loc: CLLocation?
            if let lat = VM.vnum(p["lat"]), let lng = VM.vnum(p["lng"]) {
                loc = CLLocation(latitude: lat, longitude: lng)
            }
            return (id, kind == "IGNITION", at, loc, (p["addrName"] as? String) ?? "")
        }
        let ordered = events.sorted { $0.at < $1.at }
        guard !ordered.isEmpty else { return }

        let soc = ciNumberInt(ciVal(caches, "charge"), ["RemainPower"])
        let mileage = ciNumber(ciVal(caches, "control"), ["TotalOdometer"]).map { Int($0.rounded()) }
        for e in ordered {
            seen.insert(e.id)
            if e.ignition {
                startTrip(e.loc, soc: soc, at: e.at, mileage: mileage, addr: e.addr)
            } else {
                let km: Double
                if let start = currentTrip?.startMileage, let end = mileage, end >= start {
                    km = Double(end - start)
                } else {
                    km = 0
                }
                _ = endTrip(distanceKm: km, endSoc: soc, endLocation: e.loc, at: e.at,
                            endAddr: e.addr)
                saveParkingLocation(e.loc, at: e.at, address: e.addr)
            }
        }
        processedEventIds = seen
    }



    var networkStatus: NetworkStatus {
        if isOfflineMode { return .offline }
        return lastMissedSources.isEmpty ? .online : .weak
    }
    enum NetworkStatus: String {
        case online = "在线"
        case weak = "弱网"
        case offline = "离线"
    }



    private static let pinKeychainService = "com.carkeeper.pin"
    private static let pinKeychainAccount = "car_pin"
    private static let biometricSetupKey = "carkeeper_biometric_setup"

    func savePin(_ pin: String) {
        guard let pinData = pin.data(using: .utf8) else { return }
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: Self.pinKeychainService,
            kSecAttrAccount as String: Self.pinKeychainAccount,
            kSecValueData as String: pinData,
            kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlockedThisDeviceOnly
        ]
        SecItemDelete(query as CFDictionary)
        SecItemAdd(query as CFDictionary, nil)
    }

    func readPin() -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: Self.pinKeychainService,
            kSecAttrAccount as String: Self.pinKeychainAccount,
            kSecReturnData as String: true,
            kSecMatchLimit as String: 1
        ]
        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        guard status == errSecSuccess, let data = result as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    func deletePin() {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: Self.pinKeychainService,
            kSecAttrAccount as String: Self.pinKeychainAccount
        ]
        SecItemDelete(query as CFDictionary)
    }

    var hasBiometricSetup: Bool {
        get { UserDefaults.standard.bool(forKey: Self.biometricSetupKey) }
        set { UserDefaults.standard.set(newValue, forKey: Self.biometricSetupKey) }
    }

    func canUseBiometric() -> Bool {
        let context = LAContext()
        var error: NSError?
        return context.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: &error)
    }

    func authenticateWithBiometrics(reason: String) async -> Bool {
        let context = LAContext()
        var error: NSError?
        guard context.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: &error) else {
            return false
        }
        do {
            try await context.evaluatePolicy(
                .deviceOwnerAuthenticationWithBiometrics,
                localizedReason: reason
            )
            return true
        } catch {
            return false
        }
    }

    func enableBiometric() {
        hasBiometricSetup = true
    }

    func disableBiometric() {
        hasBiometricSetup = false
    }



    var isCarMoving: Bool { VM.driveStatus(caches).isMoving }

    var carHeadingDeg: Double { Double(VM.locStatus(caches).degNum) }


    private init() {
        if let cfg = TokenStore.read(), !cfg.accessToken.isEmpty {
            isLoggedIn = true
            phone = cfg.mobile
        }
    }


    private var preloadTask: Task<Void, Never>? = nil

    private var bootstrapTask: Task<Void, Never>? = nil

    var isCharging: Bool {
        guard let charge = caches["charge"] as? [String: Any] else { return false }
        let status = ciString(charge, ["ChrgStatus"]) ?? ""
        return status == "1" || status == "2"
    }

    func bootstrap() async {
        if let running = bootstrapTask {
            await running.value
            return
        }
        let task = Task { await runBootstrap() }
        bootstrapTask = task
        await task.value
        bootstrapTask = nil
    }

    private func runBootstrap() async {
        let api = APIClient.shared
        do {
            let carsRes = try await api.getCars()
            let userRes = try await api.getUser()
            self.cars = carsRes
            if let u = userRes { user = u }
            let savedCarId = UserDefaults.standard.string(forKey: Self.selectedCarIdKey) ?? ""
            let picked = self.cars.first { (ciString($0, ["CarId", "carId"]) ?? "") == savedCarId } ?? self.cars.first
            if let first = picked {
                let id = ciString(first, ["CarId", "carId"]) ?? ""
                self.car = first
                self.carId = id
                if !savedCarId.isEmpty { UserDefaults.standard.set(id, forKey: Self.selectedCarIdKey) }
                preloadTask?.cancel()
                preloadTask = Task {
                    await fetchVehicleData()
                }
            }
        } catch {
            let apiErr = error as? APIError
            if apiErr?.expired == true || error.localizedDescription.contains("token expired") {
                NSLog("bootstrap: token expired — forcing logout")
                logout()
                Task { @MainActor in
                    ToastManager.shared.show("登录已过期，请重新登录", icon: "exclamationmark.triangle.fill")
                }
            } else {
                NSLog("bootstrap: \(error.localizedDescription)")
            }
        }
    }

    func cancelPreload() {
        preloadTask?.cancel()
        preloadTask = nil
    }

    func fetchCore() async {
        guard !carId.isEmpty else { return }
        let results = await gather(carId: carId, includeMessages: false, includeCheck: false)
        saveCache(results)
    }

    func fetchVehicleData() async {
        guard !carId.isEmpty else { return }
        let results = await gather(carId: carId, includeMessages: true, includeCheck: true)
        saveCache(results)
    }

    func fetchMotion() async {
        guard !carId.isEmpty else { return }
        var patch: [String: Any?] = [:]
        patch["location"] = try? await APIClient.shared.getLocation(carId: carId)
        saveCache(patch, declaresOffline: false)
    }

    private func gather(carId: String, includeMessages: Bool, includeCheck: Bool) async -> [String: Any?] {
        await withTaskGroup(of: (String, Any?).self) { group in
            let api = APIClient.shared
            group.addTask { () -> (String, Any?) in
                return ("charge", try? await api.getCharge(carId: carId))
            }
            group.addTask { () -> (String, Any?) in
                return ("pm25", try? await api.getCarPm25(carId: carId))
            }
            group.addTask { () -> (String, Any?) in
                return ("location", try? await api.getLocation(carId: carId))
            }
            group.addTask { () -> (String, Any?) in
                return ("control", try? await api.getControl(carId: carId))
            }
            if includeMessages {
                group.addTask { () -> (String, Any?) in
                    let r = try? await api.getMessages()
                    return ("messages", r)
                }
            }
            if includeCheck {
                group.addTask { () -> (String, Any?) in
                    return ("check", try? await api.getCarCheck(carId: carId))
                }
            }
            var out: [String: Any?] = [:]
            for await (key, value) in group {
                out[key] = value
            }
            return out
        }
    }

    func saveCache(_ patch: [String: Any?], declaresOffline: Bool = true) {
        if declaresOffline {
            lastMissedSources = patch.compactMap { $0.value == nil ? $0.key : nil }.sorted()
        }
        for (k, v) in patch {
            caches[k] = v
            if v == nil { cacheTimes[k] = nil } else { cacheTimes[k] = Date() }
        }
        if let msgs = patch["messages"] as? [[String: Any]] {
            ingestEvents(msgs)
        }
        if let charge = patch["charge"] as? [String: Any] {
            let soc = ciNumberInt(charge, ["RemainPower"])
            let range = ciNumberInt(charge, ["RemainedPowerMile"])
            if let soc, let range {
                recordEnergySnapshot(soc: soc, rangeKm: range)
            }
        }
        if declaresOffline {
            let anySuccess = patch.values.contains { $0 != nil }
            if anySuccess {
                isOfflineMode = false
            } else if !patch.isEmpty && isLoggedIn {
                isOfflineMode = true
            }
        }
        if let loc = patch["location"] as? [String: Any],
           let lat = ciNumber(loc, ["Lat"]), let lng = ciNumber(loc, ["Lng"]) {
            DriveTrace.shared.ingest(CLLocationCoordinate2D(latitude: lat, longitude: lng),
                                     moving: isCarMoving)
            let moved = !(abs(lat - lastPostedLat) < 0.00005 && abs(lng - lastPostedLng) < 0.00005)
            if moved {
                lastPostedLat = lat
                lastPostedLng = lng
                NotificationCenter.default.post(name: .locationUpdated, object: nil)
            }
        }
        recordHistory()
    }

    private func recordHistory() {
        guard !carId.isEmpty else { return }
        let e = VM.energy(caches, car)
        let control = ciVal(caches, "control")

        let pow = VM.chargePowerKW(ciVal(caches, "charge"), control)

        if isCharging, let p = pow, p > 0.1 {
            let due = chargingPowerHistory.last.map { Date().timeIntervalSince($0.time) >= 60 } ?? true
            if due {
                chargingPowerHistory.append(ChargingPowerRecord(time: Date(), power: p))
                if chargingPowerHistory.count > 240 {
                    chargingPowerHistory.removeFirst(chargingPowerHistory.count - 240)
                }
            }
        }

        let tyres: [Double?] = ["LfTyrePressure", "RfTyrePressure", "LrTyrePressure", "RrTyrePressure"]
            .map { ciNumber(control, [$0]) }

        HistoryStore.shared.record(socPct: e.socPct, charging: isCharging, powerKW: pow, tyres: tyres)

        ChargingStatusMonitor.shared.observe(soc: e.socPct, charging: isCharging, powerKW: pow)

        if let km = ciNumber(control, ["TotalOdometer"]), km > 0 {
            let intKm = Int(km.rounded())
            let previous = UserDefaults.standard.integer(forKey: Self.currentMileageKey)
            if previous != intKm {
                UserDefaults.standard.set(intKm, forKey: Self.currentMileageKey)
                if totalMileage != intKm { totalMileage = intKm }
            }
            if let plan = maintenancePlan, previous != intKm {
                Task { await MaintenanceReminderScheduler.shared.scheduleMaintenanceReminder(
                    lastServiceMileage: plan.last,
                    currentMileage: plan.current,
                    interval: plan.interval) }
            }
        }
    }


    func clearCache() {
        caches = ["charge": nil, "pm25": nil, "location": nil, "control": nil, "check": nil, "messages": nil]
    }

    static let cardOrderKey = "carkeeper_home_card_order"

    static let knownCardIds: [String] = [
        "socHero", "driveMetrics", "carSelector", "quickControl", "domainCard",
        "realtimeEnergy", "sohDashboard", "driveMode", "batterySection", "vehicle2D",
        "tyreCard", "comfortCard", "carbonSavings", "locationCard"
    ]

    var cardOrder: [String] {
        get {
            if let saved = UserDefaults.standard.array(forKey: Self.cardOrderKey) as? [String] {
                let filtered = saved.filter { Self.knownCardIds.contains($0) }
                return filtered.isEmpty ? Self.knownCardIds : filtered
            }
            return Self.knownCardIds
        }
        set { UserDefaults.standard.set(newValue, forKey: Self.cardOrderKey) }
    }


    func logout() {
        cancelPreload()
        bootstrapTask = nil
        TokenStore.clear()
        UserDefaults.standard.removeObject(forKey: cacheStorageKey)
        UserDefaults.standard.removeObject(forKey: Self.selectedCarIdKey)
        deletePin()
        isLoggedIn = false
        phone = ""
        cars = []
        carId = ""
        car = nil
        user = nil
        clearCache()
        tripHistory = []
        currentTrip = nil
        energyHistory = []
        chargingPowerHistory = []
        commandHistory = []
        HistoryStore.shared.clear()
        isOfflineMode = false
        parkingLocation = nil
        lastParkingTime = nil
        UserDefaults.standard.removeObject(forKey: Self.lastServiceMileageKey)
        UserDefaults.standard.removeObject(forKey: "carkeeper_parking_time")
        UserDefaults.standard.removeObject(forKey: "carkeeper_mileage_entries")
        UserDefaults.standard.removeObject(forKey: "carkeeper_insurance_policies")
        InspectionCalendar.shared.resetAll()
        for key in ["carkeeper_parking_points", "carkeeper_processed_event_ids",
                    "carkeeper_maintenance_photos", "carkeeper_service_reminders",
                    "carkeeper_current_mileage", "carkeeper_total_mileage",
                    "carkeeper_service_timestamp"] {
            UserDefaults.standard.removeObject(forKey: key)
        }
        NotificationCenter.default.post(name: .didLogout, object: nil)
    }

    func selectCar(_ idx: Int) {
        guard cars.indices.contains(idx) else { return }
        let c = cars[idx]
        let newId = ciString(c, ["CarId", "carId"]) ?? ""
        car = c
        carId = newId
        UserDefaults.standard.set(newId, forKey: Self.selectedCarIdKey)
        clearCache()
        Task { await fetchVehicleData() }
    }



    func sendControlCommand(_ cmd: String) async -> Bool {
        guard isLoggedIn, !carId.isEmpty else { return false }
        let pin = readPin() ?? ""
        do {
            _ = try await APIClient.shared.sendControlCommand(cmd: cmd, carId: carId, pin: pin)
            addCommandHistory(cmd: cmd, name: cmd, success: true, duration: 0)
            return true
        } catch {
            addCommandHistory(cmd: cmd, name: cmd, success: false, duration: 0)
            return false
        }
    }

    var currentLocation: CLLocation? {
        guard let loc = caches["location"] as? [String: Any],
              let lat = ciNumber(loc, ["Lat"]),
              let lng = ciNumber(loc, ["Lng"]) else { return nil }
        return CLLocation(latitude: lat, longitude: lng)
    }

    struct ParkingRecord: Identifiable {
        let id = UUID()
        let location: CLLocation
        let time: Date
        let address: String
    }
    var parkingHistory: [ParkingRecord] {
        parkingPoints.map {
            ParkingRecord(location: CLLocation(latitude: $0.lat, longitude: $0.lng),
                          time: $0.time, address: $0.address)
        }
    }

    var totalMileage: Int {
        get { UserDefaults.standard.integer(forKey: "carkeeper_total_mileage") }
        set { UserDefaults.standard.set(newValue, forKey: "carkeeper_total_mileage") }
    }

    var controlCache: [String: Any]? { ciVal(caches, "control") }

    var maintenancePlan: VM.MaintenancePlan? { VM.maintenancePlan(car, ciVal(caches, "control")) }

    var serviceTimestamp: TimeInterval {
        get { UserDefaults.standard.double(forKey: "carkeeper_service_timestamp") }
        set { UserDefaults.standard.set(newValue, forKey: "carkeeper_service_timestamp") }
    }
}


@MainActor
final class ToastManager: ObservableObject {
    static let shared = ToastManager()

    @Published var currentItem: (text: String, icon: String)? = nil

    private var dismissHandle: DispatchWorkItem?

    private init() {}

    func show(_ text: String, icon: String = "checkmark.circle.fill", duration: Double = 1.8) {
        dismissHandle?.cancel()
        currentItem = (text, icon)
        let work = DispatchWorkItem { [weak self] in self?.currentItem = nil }
        dismissHandle = work
        DispatchQueue.main.asyncAfter(deadline: .now() + duration, execute: work)
    }
}
