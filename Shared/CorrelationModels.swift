import Foundation

enum TimeWindow: String, CaseIterable, Sendable, Codable {
    case all = "ALL"
    case days30 = "30D"
    case days90 = "90D"
    case days180 = "180D"
    case year1 = "1Y"

    var days: Int {
        switch self {
        case .all: return 9999  // 哨兵值，CorrelationEngine 特殊处理
        case .days30: return 30
        case .days90: return 90
        case .days180: return 180
        case .year1: return 365
        }
    }

    var displayName: String {
        switch self {
        case .all: return "全部"
        case .days30: return "30D"
        case .days90: return "90D"
        case .days180: return "180D"
        case .year1: return "1Y"
        }
    }
}

struct CorrelationResult: Sendable, Codable, Equatable {
    let pearsonR: Double
    let beta: Double
    let divergenceRatio: Double
    let dataPoints: Int
    let window: TimeWindow
    let computedAt: Date
}

struct SourceCorrelation: Sendable, Identifiable {
    let sourceID: String
    let sourceName: String
    let correlations: [TimeWindow: CorrelationResult]

    var id: String { sourceID }
}
