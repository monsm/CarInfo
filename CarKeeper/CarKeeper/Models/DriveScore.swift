import Foundation

struct DriveScore {
    static let baselineEfficiency = 15.0

    let usesPercent: Bool
    let metric: [Double]
    let baseline: Double?
    let energy: Int?
    let steady: Int?
    let hit: Int?
    let overall: Int?

    init(efforts: [Double], percents: [Double]) {
        let usesPercent = efforts.isEmpty
        let metric = usesPercent ? percents : efforts

        let baseline: Double?
        if !usesPercent {
            baseline = Self.baselineEfficiency
        } else if percents.count >= 2 {
            let sorted = percents.sorted()
            baseline = sorted[sorted.count / 2]
        } else {
            baseline = nil
        }

        let energy: Int?
        if let baseline, !metric.isEmpty {
            let avg = metric.reduce(0, +) / Double(metric.count)
            energy = Self.efficiencyPoints(avg, baseline: baseline, lowerIsBetter: !usesPercent)
        } else {
            energy = nil
        }

        let steady: Int?
        if metric.count >= 3 {
            let mean = metric.reduce(0, +) / Double(metric.count)
            if mean > 0 {
                let variance = metric.reduce(0.0) { $0 + ($1 - mean) * ($1 - mean) } / Double(metric.count)
                steady = Self.clamp(Int(100 - variance.squareRoot() / mean * 200))
            } else {
                steady = nil
            }
        } else {
            steady = nil
        }

        let hit: Int?
        if let baseline, !metric.isEmpty {
            let count = usesPercent
                ? metric.filter { $0 >= baseline * 0.9 }.count
                : metric.filter { $0 <= baseline }.count
            hit = Self.clamp(Int(Double(count) / Double(metric.count) * 100))
        } else {
            hit = nil
        }

        let dims = [energy, steady, hit].compactMap { $0 }
        self.usesPercent = usesPercent
        self.metric = metric
        self.baseline = baseline
        self.energy = energy
        self.steady = steady
        self.hit = hit
        self.overall = dims.isEmpty ? nil : Int(Double(dims.reduce(0, +)) / Double(dims.count))
    }

    var grade: String? {
        guard let s = overall else { return nil }
        switch s {
        case 90...: return "S"
        case 80..<90: return "A"
        case 70..<80: return "B"
        case 60..<70: return "C"
        default: return "D"
        }
    }

    static func clamp(_ v: Int) -> Int { max(0, min(100, v)) }

    static func efficiencyPoints(_ v: Double, baseline: Double, lowerIsBetter: Bool) -> Int {
        guard baseline > 0 else { return 0 }
        if lowerIsBetter { return clamp(Int(100 - (v - baseline) * 4)) }
        return clamp(Int((v / baseline - 0.7) / 0.6 * 100))
    }
}
