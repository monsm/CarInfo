import SwiftUI
import Observation
import Foundation
import CoreLocation
import LocalAuthentication


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

    typealias HistoryEntry = CommandRecord
    typealias EnergyRecord = EnergySample
    typealias TripRecord = TripLog
    typealias ParkingPoint = ParkingMark
    typealias ParkingRecord = ParkingVisit
    typealias MapFocus = MapTarget
    typealias NetworkStatus = LinkStatus

    typealias OpenTrip = TripTracker.Open

    private var cacheTimes: [String: Date] = [:]

    func cacheTime(_ key: String) -> Date? { cacheTimes[key] }

    private(set) var lastMissedSources: [String] = []

    private var lastPostedLat = Double.nan
    private var lastPostedLng = Double.nan

    var commandHistory: [HistoryEntry] = []

    func addCommandHistory(cmd: String, name: String, success: Bool,
                           duration: TimeInterval, confirmed: Bool = true) {
        let entry = HistoryEntry(cmd: cmd, name: name,
                                 startedAt: Date().advanced(by: -duration),
                                 finishedAt: Date(), success: success,
                                 confirmed: confirmed, duration: duration)
        commandHistory = CommandHistoryTracker.insert(entry, into: commandHistory)
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

    var energyHistory: [EnergyRecord] = []

    var tripHistory: [TripRecord] = []
    private var currentTrip: OpenTrip? = nil

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

    var mapFocus: MapFocus? = nil



    func recordEnergySnapshot(soc: Int, rangeKm: Int) {
        let recent = energyHistory.filter { Date().timeIntervalSince($0.timestamp) < 60 }
        guard recent.isEmpty else { return }
        energyHistory.append(EnergyRecord(timestamp: Date(), soc: soc, range: rangeKm))
        if energyHistory.count > 20 { energyHistory = Array(energyHistory.suffix(20)) }
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
        if ParkingTracker.shouldSkip(last: points.last, new: c) { return }
        points.append(ParkingPoint(lat: c.latitude, lng: c.longitude,
                                   time: time ?? Date(), address: address))
        parkingPoints = points
    }

    func startTrip(_ location: CLLocation? = nil, soc: Int? = nil,
                   at time: Date? = nil, mileage: Int? = nil, addr: String = "") {
        let currentSoc = soc ?? (energyHistory.last?.soc ?? 0)
        currentTrip = OpenTrip(startTime: time ?? Date(), startSoc: currentSoc,
                               startLocation: location, startMileage: mileage, startAddr: addr)
        DriveTrace.shared.begin()
    }

    func endTrip(distanceKm: Double, endSoc: Int? = nil,
                 endLocation: CLLocation? = nil, at time: Date? = nil,
                 endAddr: String = "") -> TripRecord? {
        guard let trip = currentTrip else { return nil }
        let endSoc = endSoc ?? (energyHistory.last?.soc ?? 0)
        let record = TripTracker.makeRecord(trip, distanceKm: distanceKm, endSoc: endSoc,
                                            endLocation: endLocation, at: time ?? Date(),
                                            endAddr: endAddr)
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
                let km = TripTracker.tripKm(open: currentTrip, endMileage: mileage)
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



    private static let biometricSetupKey = "carkeeper_biometric_setup"

    func savePin(_ pin: String) { PinStore.save(pin) }

    func readPin() -> String? { PinStore.read() }

    func deletePin() { PinStore.delete() }

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

    var isCarMoving: Bool { VM.isMovingFast(caches) }

    var carHeadingDeg: Double { VM.headingDegFast(caches) }


    private init() {
        if let cfg = TokenStore.read(), !cfg.accessToken.isEmpty {
            isLoggedIn = true
            phone = cfg.mobile
        }
    }


    private var preloadTask: Task<Void, Never>? = nil

    private var bootstrapTask: Task<BootstrapOutcome, Never>? = nil

    var isCharging: Bool {
        guard let charge = caches["charge"] as? [String: Any] else { return false }
        let status = ciString(charge, ["ChrgStatus"]) ?? ""
        return status == "1" || status == "2"
    }

    enum BootstrapOutcome: Equatable {
        case success
        case networkFailure
        case sessionExpired
    }

    @discardableResult
    func bootstrap() async -> BootstrapOutcome {
        if let running = bootstrapTask {
            return await running.value
        }
        let task = Task { await runBootstrap() }
        bootstrapTask = task
        let outcome = await task.value
        bootstrapTask = nil
        return outcome
    }

    private func runBootstrap() async -> BootstrapOutcome {
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
            return .success
        } catch {
            let apiErr = error as? APIError
            if apiErr?.isAuthFailure == true || error.localizedDescription.contains("token expired") {
                NSLog("bootstrap: token expired — forcing logout")
                logout()
                Task { @MainActor in
                    ToastManager.shared.show("登录已过期，请重新登录", icon: "exclamationmark.triangle.fill")
                }
                return .sessionExpired
            }
            NSLog("bootstrap: \(error.localizedDescription)")
            return .networkFailure
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
        var changedSources = Set<String>()
        for (k, v) in patch {
            if let v {
                caches[k] = v
                cacheTimes[k] = Date()
                changedSources.insert(k)
            }
        }
        if changedSources.contains("charge") || changedSources.contains("control") {
            recordHistory()
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
    }

    private func recordHistory() {
        guard !carId.isEmpty else { return }
        let e = VM.energy(caches, car)
        let control = ciVal(caches, "control")

        let pow = VM.chargePowerKW(ciVal(caches, "charge"), control)

        HistoryStore.shared.record(socPct: e.socPct, charging: isCharging, powerKW: pow)

        ChargingStatusMonitor.shared.observe(soc: e.socPct, charging: isCharging, powerKW: pow)

        if let km = ciNumber(control, ["TotalOdometer"]), km > 0 {
            let intKm = Int(km.rounded())
            let previous = UserDefaults.standard.integer(forKey: Self.currentMileageKey)
            if totalMileage != intKm { totalMileage = intKm }
            if previous != intKm {
                UserDefaults.standard.set(intKm, forKey: Self.currentMileageKey)
                if let plan = maintenancePlan {
                    Task { await MaintenanceReminderScheduler.shared.scheduleMaintenanceReminder(
                        lastServiceMileage: plan.last,
                        currentMileage: plan.current,
                        interval: plan.interval) }
                }
            }
        }
    }


    func clearCache() {
        caches = ["charge": nil, "pm25": nil, "location": nil, "control": nil, "check": nil, "messages": nil]
        cacheTimes = [:]
        lastMissedSources = []
        isOfflineMode = false
    }

    static let cardOrderKey = "carkeeper_home_card_order"

    static let knownCardIds: [String] = [
        "socHero", "driveMetrics", "carSelector", "quickControl", "domainCard",
        "realtimeEnergy", "sohDashboard", "driveMode", "batterySection", "vehicle2D",
        "tyreCard", "comfortCard", "carbonSavings", "locationCard"
    ]

    var cardOrder: [String] {
        get {
            Self.normalizeCardOrder(UserDefaults.standard.array(forKey: Self.cardOrderKey) as? [String],
                                    known: Self.knownCardIds)
        }
        set { UserDefaults.standard.set(newValue, forKey: Self.cardOrderKey) }
    }

    nonisolated static func normalizeCardOrder(_ saved: [String]?, known: [String]) -> [String] {
        guard let saved else { return known }
        let kept = saved.filter { known.contains($0) }
        let missing = known.filter { !kept.contains($0) }
        return kept + missing
    }


    func logout() {
        cancelPreload()
        bootstrapTask = nil
        RefreshLoop.shared.stop()
        KeepAwake.shared.stop()
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
                    "carkeeper_maintenance_photos",
                    "carkeeper_current_mileage", "carkeeper_total_mileage"] {
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
