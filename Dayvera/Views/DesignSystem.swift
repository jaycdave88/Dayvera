import SwiftUI

enum AppAppearance: String, CaseIterable, Identifiable {
    case system
    case light
    case dark

    var id: String { rawValue }

    var title: String {
        switch self {
        case .system: "System"
        case .light: "Light"
        case .dark: "Dark"
        }
    }

    var colorScheme: ColorScheme? {
        switch self {
        case .system: nil
        case .light: .light
        case .dark: .dark
        }
    }
}

extension Color {
    static let coachInk = Color(red: 8 / 255, green: 22 / 255, blue: 46 / 255)
    static let coachIndigo = Color(uiColor: UIColor { traits in
        if traits.accessibilityContrast == .high {
            return traits.userInterfaceStyle == .dark
                ? UIColor(red: 164 / 255, green: 176 / 255, blue: 1, alpha: 1)
                : UIColor(red: 49 / 255, green: 62 / 255, blue: 171 / 255, alpha: 1)
        }
        return traits.userInterfaceStyle == .dark
            ? UIColor(red: 130 / 255, green: 147 / 255, blue: 1, alpha: 1)
            : UIColor(red: 70 / 255, green: 85 / 255, blue: 204 / 255, alpha: 1)
    })
    static let coachMint = Color(uiColor: UIColor { traits in
        if traits.accessibilityContrast == .high {
            return traits.userInterfaceStyle == .dark
                ? UIColor(red: 139 / 255, green: 245 / 255, blue: 215 / 255, alpha: 1)
                : UIColor(red: 0, green: 100 / 255, blue: 70 / 255, alpha: 1)
        }
        return traits.userInterfaceStyle == .dark
            ? UIColor(red: 101 / 255, green: 228 / 255, blue: 188 / 255, alpha: 1)
            : UIColor(red: 11 / 255, green: 122 / 255, blue: 90 / 255, alpha: 1)
    })
    static let coachAmber = Color(uiColor: UIColor { traits in
        if traits.accessibilityContrast == .high {
            return traits.userInterfaceStyle == .dark
                ? UIColor(red: 1, green: 211 / 255, blue: 126 / 255, alpha: 1)
                : UIColor(red: 110 / 255, green: 66 / 255, blue: 0, alpha: 1)
        }
        return traits.userInterfaceStyle == .dark
            ? UIColor(red: 1, green: 192 / 255, blue: 74 / 255, alpha: 1)
            : UIColor(red: 138 / 255, green: 86 / 255, blue: 0, alpha: 1)
    })
    static let coachRose = Color(uiColor: UIColor { traits in
        if traits.accessibilityContrast == .high {
            return traits.userInterfaceStyle == .dark
                ? UIColor(red: 1, green: 151 / 255, blue: 169 / 255, alpha: 1)
                : UIColor(red: 142 / 255, green: 17 / 255, blue: 49 / 255, alpha: 1)
        }
        return traits.userInterfaceStyle == .dark
            ? UIColor(red: 1, green: 113 / 255, blue: 139 / 255, alpha: 1)
            : UIColor(red: 179 / 255, green: 38 / 255, blue: 69 / 255, alpha: 1)
    })
    static let coachBackground = Color(uiColor: .systemGroupedBackground)
    static let coachSurface = Color(uiColor: .secondarySystemGroupedBackground)
    static let coachNestedSurface = Color(uiColor: .tertiarySystemGroupedBackground)
    static let coachBorder = Color(uiColor: .separator)
}

extension ReadinessBand {
    var color: Color {
        switch self {
        case .high: .coachMint
        case .moderate: .coachAmber
        case .low: .coachRose
        }
    }

    var symbol: String {
        switch self {
        case .high: "bolt.fill"
        case .moderate: "gauge.with.dots.needle.50percent"
        case .low: "leaf.fill"
        }
    }
}

struct CoachCard<Content: View>: View {
    @ViewBuilder let content: Content

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: 20, style: .continuous)
        content
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.coachSurface, in: shape)
            .overlay {
                shape.stroke(Color.coachBorder.opacity(0.45), lineWidth: 0.5)
            }
    }
}

struct SectionTitle: View {
    let title: String
    var subtitle: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title).font(.title3.weight(.semibold))
            if let subtitle { Text(subtitle).font(.subheadline).foregroundStyle(.secondary) }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct MetricTile: View {
    let label: String
    let value: String
    let detail: String
    var tint: Color = .coachIndigo

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label(label, systemImage: "circle.fill")
                .font(.footnote.weight(.semibold))
                .foregroundStyle(.secondary)
                .labelStyle(TintedDotLabelStyle(tint: tint))
            Text(value)
                .font(.title2.bold())
                .monospacedDigit()
                .fixedSize(horizontal: false, vertical: true)
            Text(detail)
                .font(.footnote)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(16)
        .frame(maxWidth: .infinity, minHeight: 120, alignment: .leading)
        .background(Color.coachNestedSurface, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }
}

private struct TintedDotLabelStyle: LabelStyle {
    let tint: Color
    func makeBody(configuration: Configuration) -> some View {
        HStack(spacing: 6) {
            configuration.icon.font(.system(size: 8)).foregroundStyle(tint)
            configuration.title
        }
    }
}

struct EmptyState: View {
    let symbol: String
    let title: String
    let detail: String

    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: symbol).font(.system(size: 34)).foregroundStyle(Color.coachIndigo)
            Text(title).font(.headline)
            Text(detail).font(.subheadline).foregroundStyle(.secondary).multilineTextAlignment(.center)
        }
        .padding(28)
        .frame(maxWidth: .infinity)
    }
}

extension Date {
    var shortTime: String { formatted(date: .omitted, time: .shortened) }
    var shortDay: String { formatted(.dateTime.weekday(.abbreviated).month(.abbreviated).day()) }
}

extension Double {
    var hoursMinutes: String {
        let total = max(Int(rounded()), 0)
        return "\(total / 60)h \(total % 60)m"
    }
}
