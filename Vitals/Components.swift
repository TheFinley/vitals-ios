import SwiftUI

/// Palette mirrored from the web dashboard: gold emphasis for the one number that matters,
/// blue / green / amber for protein / carbs / fat, semantic tones kept separate.
enum Theme {
    static let emphasis = Color(light: Color(red: 0.541, green: 0.380, blue: 0.0), dark: Color(red: 0.957, green: 0.769, blue: 0.239))
    static let protein = Color(light: Color(red: 0.06, green: 0.48, blue: 0.68), dark: Color(red: 0.18, green: 0.63, blue: 0.84))
    static let carbs = Color(light: Color(red: 0.28, green: 0.51, blue: 0.12), dark: Color(red: 0.36, green: 0.66, blue: 0.23))
    static let fat = Color(light: Color(red: 0.61, green: 0.39, blue: 0.09), dark: Color(red: 0.78, green: 0.51, blue: 0.16))
    static let heart = Color(light: Color(red: 0.76, green: 0.25, blue: 0.18), dark: Color(red: 0.88, green: 0.30, blue: 0.25))
    static let sleep = Color(light: Color(red: 0.48, green: 0.27, blue: 0.62), dark: Color(red: 0.60, green: 0.36, blue: 0.76))
    static let good = carbs
    static let warn = fat
    static let bad = heart
    static let info = protein

    static func color(for tone: Tone) -> Color {
        switch tone { case .good: good; case .warn: warn; case .bad: bad; case .info: info; case .neutral: .secondary }
    }
    static func color(for n: Nutrient) -> Color {
        switch n { case .protein: protein; case .carbs: carbs; case .fat: fat; case .kcal: emphasis; default: .secondary }
    }
}

extension Color {
    init(light: Color, dark: Color) {
        self.init(uiColor: UIColor { $0.userInterfaceStyle == .dark ? UIColor(dark) : UIColor(light) })
    }
}

extension Font {
    static func num(_ size: CGFloat, weight: Font.Weight = .bold) -> Font { .system(size: size, weight: weight, design: .rounded) }
}

// MARK: - Cards & tiles

struct Card<Content: View>: View {
    var title: String? = nil
    var subtitle: String? = nil
    var symbol: String? = nil
    @ViewBuilder var content: Content
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if let title {
                HStack(alignment: .firstTextBaseline) {
                    if let symbol { Image(systemName: symbol).foregroundStyle(.secondary).font(.subheadline) }
                    Text(title).font(.headline)
                    Spacer()
                    if let subtitle { Text(subtitle).font(.caption).foregroundStyle(.secondary).multilineTextAlignment(.trailing) }
                }
            }
            content
        }
        .padding(16)
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
    }
}

struct StatTile: View {
    var label: String
    var value: String
    var unit: String = ""
    var symbol: String
    var color: Color
    var detail: String? = nil
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Image(systemName: symbol).font(.system(size: 15, weight: .semibold)).foregroundStyle(color)
                .frame(width: 30, height: 30).background(color.opacity(0.14), in: RoundedRectangle(cornerRadius: 9, style: .continuous))
            HStack(alignment: .firstTextBaseline, spacing: 3) {
                Text(value).font(.num(24)).monospacedDigit()
                if !unit.isEmpty { Text(unit).font(.caption).fontWeight(.semibold).foregroundStyle(.secondary) }
            }
            Text(label).font(.caption).foregroundStyle(.secondary)
            if let detail { Text(detail).font(.caption2).foregroundStyle(.tertiary) }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .padding(14)
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }
}

struct Ring: View {
    var progress: Double        // 0…1+
    var color: Color
    var lineWidth: CGFloat = 12
    var body: some View {
        ZStack {
            Circle().stroke(color.opacity(0.14), lineWidth: lineWidth)
            Circle().trim(from: 0, to: min(1, max(0, progress)))
                .stroke(progress > 1 ? Theme.bad : color, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                .rotationEffect(.degrees(-90))
                .animation(.spring(duration: 0.9), value: progress)
        }
    }
}

struct MacroBar: View {
    var label: String
    var value: Double
    var target: Double
    var color: Color
    var body: some View {
        VStack(spacing: 5) {
            HStack {
                Text(label).font(.caption).fontWeight(.semibold).foregroundStyle(.secondary)
                Spacer()
                (Text(value.g0).fontWeight(.bold) + Text(" / \(target.g0) g")).font(.caption).monospacedDigit().foregroundStyle(.secondary)
            }
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(color.opacity(0.14))
                    Capsule().fill(value > target * 1.1 ? Theme.bad : color)
                        .frame(width: geo.size.width * min(1, target > 0 ? value / target : 0))
                        .animation(.spring(duration: 0.8), value: value)
                }
            }
            .frame(height: 8)
        }
    }
}

struct TonePill: View {
    var text: String
    var tone: Tone
    var body: some View {
        Text(text).font(.caption2).fontWeight(.bold)
            .padding(.horizontal, 7).padding(.vertical, 3)
            .foregroundStyle(Theme.color(for: tone))
            .background(Theme.color(for: tone).opacity(0.14), in: Capsule())
    }
}

struct NutrientTile: View {
    var nutrient: Nutrient
    var value: Double
    var reference: Double
    var hasData: Bool
    var body: some View {
        let st = hasData ? nutrientStatus(nutrient, value: value, reference: reference) : (tone: Tone.neutral, text: "no data")
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(nutrient.label).font(.caption).fontWeight(.semibold).foregroundStyle(.secondary)
                Spacer()
                TonePill(text: st.text, tone: st.tone)
            }
            HStack(alignment: .firstTextBaseline, spacing: 2) {
                Text(nutrient.unit == "g" || nutrient.unit == "µg" ? value.g1 : value.g0).font(.num(17)).monospacedDigit()
                Text(nutrient.unit).font(.caption2).foregroundStyle(.secondary)
            }
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(Color.primary.opacity(0.08))
                    Capsule().fill(Theme.color(for: st.tone)).frame(width: geo.size.width * min(1, reference > 0 ? value / reference : 0))
                }
            }.frame(height: 5)
            Text("\(nutrient.kind == .max ? "limit" : "aim") \(reference.g0) \(nutrient.unit)").font(.caption2).foregroundStyle(.tertiary)
        }
        .padding(12)
        .background(Color(.tertiarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }
}

struct SuggestionRow: View {
    var kind: CoachSuggestion.Kind
    var title: String
    var body_: String
    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            let (txt, tone): (String, Tone) = switch kind { case .eat: ("Eat", .good); case .avoid: ("Skip", .bad); case .tip: ("Tip", .info) }
            TonePill(text: txt, tone: tone).padding(.top, 2)
            VStack(alignment: .leading, spacing: 3) {
                Text(title).font(.subheadline).fontWeight(.semibold)
                Text(body_).font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(Color(.tertiarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }
}

struct EmptyHint: View {
    var title: String
    var text: String
    var body: some View {
        VStack(spacing: 4) {
            Text(title).font(.subheadline).fontWeight(.semibold)
            Text(text).font(.caption).foregroundStyle(.secondary).multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity).padding(.vertical, 22).padding(.horizontal, 12)
        .background(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(style: StrokeStyle(lineWidth: 1, dash: [5, 4])).foregroundStyle(.quaternary))
    }
}
