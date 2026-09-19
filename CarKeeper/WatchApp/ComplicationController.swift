// =============================================================================
// ComplicationController — #NEW-106 Apple Watch 复杂功能
// 主屏实时显示 SOC 百分比圆环
// =============================================================================

import ClockKit
import SwiftUI
import Foundation

class ComplicationController: NSObject, CLKComplicationDataSource {
    
    // MARK: - Timeline Configuration
    func getSupportedTimeTravelDirections(for complication: CLKComplication, at time: Date, handler: @escaping (CLKComplicationTimeTravelDirections) -> Void) {
        handler([.forward, .backward])
    }
    
    func getCurrentTimelineEntry(for complication: CLKComplication, withHandler handler: @escaping (CLKComplicationTimelineEntry?) -> Void) {
        let defaults = UserDefaults(suiteName: "group.com.you.CarKeeper") ?? UserDefaults.standard
        let soc = defaults.integer(forKey: "widget_soc")
        let range = defaults.integer(forKey: "widget_range")
        
        let template = CLKComplicationTemplateModularLargeStandardBody()
        template.headerTextProvider = .static(text: "EV")
        template.body1TextProvider = .static(text: "\(soc)%")
        template.body2TextProvider = .static(text: "\(range)km")
        
        let entry = CLKComplicationTimelineEntry(date: Date, complicationTemplate: template)
        handler(entry)
    }
    
    // MARK: - Placeholder & Preview Templates
    func getLocalizableSampleTemplate(for complication: CLKComplication, withHandler handler: @escaping (CLKComplicationTemplate?) -> Void) {
        let template = CLKComplicationTemplateModularLargeStandardBody()
        template.headerTextProvider = .static(text: "EV")
        template.body1TextProvider = .static(text: "78%")
        template.body2TextProvider = .static(text: "380km")
        handler(template)
    }
    
    // MARK: - Timeline Entries
    func getTimelineEntries(for complication: CLKComplication, after date: Date, limit: Int, withHandler handler: @escaping ([CLKComplicationTimelineEntry]?) -> Void) {
        var entries: [CLKComplicationTimelineEntry] = []
        let defaults = UserDefaults(suiteName: "group.com.you.CarKeeper") ?? UserDefaults.standard
        let soc = defaults.integer(forKey: "widget_soc")
        let range = defaults.integer(forKey: "widget_range")
        
        for offset in 0..<limit {
            let time = date.addingTimeInterval(Double(offset) * 300) // 每5分钟
            let template = CLKComplicationTemplateModularLargeStandardBody()
            template.headerTextProvider = .static(text: "EV")
            template.body1TextProvider = .static(text: "\(soc)%")
            template.body2TextProvider = .static(text: "\(range)km")
            entries.append(CLKComplicationTimelineEntry(date: time, complicationTemplate: template))
        }
        handler(entries)
    }
}
