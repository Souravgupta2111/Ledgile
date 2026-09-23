import SwiftUI

struct SectionCard<Content: View>: View {

    var cornerRadius: CGFloat = Radius.card

    var showsSeparators: Bool = true

    var separatorInset: CGFloat = Spacing.lg

    @ViewBuilder var content: Content

    var body: some View {
        VStack(spacing: 0) {
            Group(subviews: content) { rows in
                ForEach(rows.indices, id: \.self) { index in
                    rows[index]
                    if showsSeparators && index < rows.count - 1 {
                        RowSeparator(leadingInset: separatorInset)
                    }
                }
            }
        }
        .background(Color.surface)
        .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
    }
}

struct RowSeparator: View {
    var leadingInset: CGFloat = Spacing.lg

    var body: some View {
        Rectangle()
            .fill(Color.rowSeparator)
            .frame(height: Sizing.separator)
            .padding(.leading, leadingInset)
    }
}

extension View {

    func cardRow(isFirst: Bool, isLast: Bool) -> some View {
        modifier(CardRow(isFirst: isFirst, isLast: isLast))
    }
}

private struct CardRow: ViewModifier {
    let isFirst: Bool
    let isLast: Bool

    func body(content: Content) -> some View {
        content
            .listRowInsets(EdgeInsets(top: 0, leading: Spacing.lg, bottom: 0, trailing: Spacing.lg))
            .listRowSeparator(.hidden)
            .listRowBackground(
                Color.surface
                    .clipShape(
                        .rect(
                            topLeadingRadius: isFirst ? Radius.card : 0,
                            bottomLeadingRadius: isLast ? Radius.card : 0,
                            bottomTrailingRadius: isLast ? Radius.card : 0,
                            topTrailingRadius: isFirst ? Radius.card : 0,
                            style: .continuous
                        )
                    )
                    .padding(.horizontal, Spacing.lg)
                    .overlay(alignment: .bottom) {
                        if !isLast {
                            RowSeparator(leadingInset: Spacing.xxl)
                                .padding(.horizontal, Spacing.lg)
                        }
                    }
            )
    }
}

extension View {

    func screenBackground() -> some View {
        self.background(Color.screenBackground.ignoresSafeArea())
    }

    func screenPadding() -> some View {
        self.padding(.horizontal, Spacing.lg)
    }
}
