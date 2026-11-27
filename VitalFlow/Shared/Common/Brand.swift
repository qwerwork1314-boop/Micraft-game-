import SwiftUI

/// VitalFlow brand system: black, white, emerald green and deep blue.
enum Brand {
    static let emerald = Color(red: 0.063, green: 0.725, blue: 0.506)      // #10B981
    static let emeraldDeep = Color(red: 0.016, green: 0.471, blue: 0.341)  // #047857
    static let deepBlue = Color(red: 0.118, green: 0.227, blue: 0.541)     // #1E3A8A
    static let ocean = Color(red: 0.149, green: 0.388, blue: 0.922)        // #2563EB
    static let ink = Color(red: 0.039, green: 0.047, blue: 0.071)          // #0A0C12
    static let amber = Color(red: 0.961, green: 0.620, blue: 0.043)        // #F59E0B (attention, not alarm)
    static let coral = Color(red: 0.937, green: 0.396, blue: 0.341)        // heart rate accent

    static let flow = LinearGradient(colors: [deepBlue, ocean, emerald], startPoint: .topLeading, endPoint: .bottomTrailing)
    static let night = LinearGradient(colors: [Color(red: 0.07, green: 0.09, blue: 0.24), deepBlue], startPoint: .top, endPoint: .bottom)

    /// Colour for a 0–100 wellness score. Calm palette: never red-alarm.
    static func scoreColor(_ score: Int?) -> Color {
        guard let s = score else { return .secondary }
        switch s {
        case 67...: return emerald
        case 34..<67: return ocean
        default: return amber
        }
    }

    /// Stress uses the inverse mapping (low stress = emerald).
    static func stressColor(_ score: Int?) -> Color {
        guard let s = score else { return .secondary }
        return scoreColor(100 - s)
    }
}

/// Ring gauge used on iPhone, Apple Watch and widgets.
struct ScoreRing: View {
    var progress: Double          // 0…1
    var color: Color
    var lineWidth: CGFloat = 10

    var body: some View {
        ZStack {
            Circle().stroke(color.opacity(0.18), lineWidth: lineWidth)
            Circle()
                .trim(from: 0, to: max(0.001, min(1, progress)))
                .stroke(AngularGradient(colors: [color.opacity(0.65), color], center: .center),
                        style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                .rotationEffect(.degrees(-90))
        }
        .accessibilityHidden(true)
    }
}
