import SwiftUI

struct LabelValueRow: View {
    let title: String
    let value: String

    var emphasised: Bool = false

    var titleColor: Color = .textPrimary
    var valueColor: Color = .textPrimary

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: Spacing.md) {
            Text(title)
                .font(emphasised ? .bodyBold : .bodyText)
                .foregroundStyle(titleColor)

            Spacer(minLength: Spacing.sm)

            Text(value)
                .font(emphasised ? .bodyBold : .bodyText)
                .foregroundStyle(valueColor)
                .multilineTextAlignment(.trailing)
        }
        .padding(.horizontal, Spacing.lg)
        .padding(.vertical, Spacing.md)
        .frame(minHeight: Sizing.minTouchTarget)
    }
}

struct ItemRow: View {
    let title: String
    var subtitle: String? = nil
    var amount: String? = nil

    var systemImage: String? = nil

    var amountColor: Color = .brand

    var titleColor: Color = .textPrimary

    var showsChevron: Bool = true

    var body: some View {
        HStack(spacing: Spacing.md) {
            if let systemImage {
                Image(systemName: systemImage)
                    .font(.bodyText)
                    .foregroundStyle(Color.textSecondary)
                    .frame(width: Sizing.iconBadge, height: Sizing.iconBadge)
                    .background(Color.screenBackground)
                    .clipShape(Circle())
            }

            VStack(alignment: .leading, spacing: Spacing.xs) {
                Text(title)
                    .font(.bodyText)
                    .foregroundStyle(titleColor)
                    .lineLimit(1)

                if let subtitle {
                    Text(subtitle)
                        .font(.subheading)
                        .foregroundStyle(Color.textSecondary)
                        .lineLimit(1)
                }
            }

            Spacer(minLength: Spacing.sm)

            if let amount {
                Text(amount)
                    .font(.bodyText)
                    .foregroundStyle(amountColor)
            }

            if showsChevron { RowChevron() }
        }
        .padding(.horizontal, Spacing.lg)
        .padding(.vertical, Spacing.md)
        .frame(minHeight: Sizing.minTouchTarget)
    }
}

struct RowChevron: View {
    var body: some View {
        Image(systemName: "chevron.right")
            .font(.meta)
            .fontWeight(.semibold)
            .foregroundStyle(Color.textTertiary)
            .accessibilityHidden(true)
    }
}
