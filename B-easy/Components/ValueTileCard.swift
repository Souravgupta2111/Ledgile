import SwiftUI

struct ValueTileCard: View {

    enum Style {

        case brand

        case beige

        var background: Color {
            switch self {
            case .brand: return .brand
            case .beige: return .fixedBeige
            }
        }

        var foreground: Color {
            switch self {
            case .brand: return .fixedOnDark
            case .beige: return .fixedOnLight
            }
        }

        var secondaryOpacity: Double {
            switch self {
            case .brand: return 0.75
            case .beige: return 0.6
            }
        }
    }

    let style: Style

    let title: String

    let subtitle: String

    let amount: String

    var countLine: String?

    var trailingLine: (text: String, color: Color)?

    var action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 0) {
                HStack(alignment: .firstTextBaseline, spacing: Spacing.sm) {
                    Text(title)
                        .font(.cellTitle)
                        .foregroundStyle(style.foreground)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)

                    Spacer(minLength: 0)

                    Image(systemName: "chevron.right")
                        .font(.footnote)
                        .fontWeight(.semibold)
                        .foregroundStyle(style.foreground.opacity(style.secondaryOpacity))
                }

                Text(subtitle)
                    .font(.meta)
                    .foregroundStyle(style.foreground.opacity(style.secondaryOpacity))
                    .padding(.top, Spacing.xs)

                Text(amount)
                    .font(.cardValueSoft)
                    .foregroundStyle(style.foreground)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                    .padding(.top, Spacing.xs)

                Spacer(minLength: Spacing.sm)

                if let trailingLine {
                    Text(trailingLine.text)
                        .font(.meta)
                        .foregroundStyle(trailingLine.color)
                }

                if let countLine {
                    Text(countLine)
                        .font(.meta)
                        .foregroundStyle(style.foreground.opacity(style.secondaryOpacity))
                        .padding(.top, trailingLine != nil ? Spacing.xs : 0)
                }
            }
            .padding(Spacing.lg)
            .frame(maxWidth: .infinity, minHeight: 156, alignment: .topLeading)
            .background(style.background)
            .clipShape(RoundedRectangle(cornerRadius: Radius.card, style: .continuous))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(title), \(subtitle) \(amount)")
    }
}

enum PercentChange {
    static func line(_ value: Double?, on style: ValueTileCard.Style) -> (text: String, color: Color) {
        guard let value, value != 0 else {
            return ("0.0%", style.foreground)
        }
        let magnitude = abs(value)
        if value > 0 {
            return (String(format: "+ %.1f%%", magnitude), style == .brand ? .fixedOnDark : .brand)
        }
        return (String(format: "- %.1f%%", magnitude), .negative)
    }
}
