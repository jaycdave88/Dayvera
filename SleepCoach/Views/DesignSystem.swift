import SwiftUI

extension Color {
    static let coachInk = Color(red: 0.08, green: 0.10, blue: 0.16)
    // Apple's semantic indigo adapts its luminance for light, dark, and
    // Increase Contrast appearances while preserving the product accent.
    static let coachIndigo = Color(uiColor: .systemIndigo)
    static let coachMint = Color(red: 0.22, green: 0.72, blue: 0.58)
    static let coachAmber = Color(red: 0.96, green: 0.65, blue: 0.24)
    static let coachRose = Color(red: 0.91, green: 0.34, blue: 0.42)
    static let coachSurface = Color(uiColor: .secondarySystemGroupedBackground)
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
        content
            .padding(18)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .stroke(Color.primary.opacity(0.06), lineWidth: 1)
            }
    }
}

struct SectionTitle: View {
    let title: String
    var subtitle: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title).font(.title3.bold())
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
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
                .labelStyle(TintedDotLabelStyle(tint: tint))
            Text(value).font(.title2.bold()).monospacedDigit().minimumScaleFactor(0.75)
            Text(detail).font(.caption).foregroundStyle(.secondary)
        }
        .padding(15)
        .frame(maxWidth: .infinity, minHeight: 118, alignment: .leading)
        .background(Color.coachSurface, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
    }
}

private struct TintedDotLabelStyle: LabelStyle {
    let tint: Color
    func makeBody(configuration: Configuration) -> some View {
        HStack(spacing: 6) {
            configuration.icon.font(.system(size: 7)).foregroundStyle(tint)
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
