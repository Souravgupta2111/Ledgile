import SwiftUI

// MARK: - Navigation Actions

struct StockNavigationActions {
    var onManualEntry: () -> Void = {}
    var onVoiceEntry: () -> Void = {}
    var onScanEntry: () -> Void = {}
    var onItemTapped: (Item) -> Void = { _ in }
    var onPurchaseTapped: () -> Void = {}
    var onLowStockTapped: () -> Void = {}
    var onExpiryTapped: () -> Void = {}
    var onInventoryTapped: () -> Void = {}
}

struct StockTabView: View {
    @StateObject private var viewModel = StockTabViewModel()
    @State private var sheetState: SalesSheetState = .collapsed
    @State private var dragOffset: CGFloat = 0

    // Inline voice state
    @State private var isListening: Bool = false
    @State private var transcribedText: String = ""

    var actions = StockNavigationActions()

    /// UIKit VC registers a callback to push transcription updates into SwiftUI.
    var onTranscriptionUpdate: ((@escaping (String) -> Void) -> Void)?
    /// UIKit VC registers a callback to toggle listening state.
    var onListeningStateChanged: ((@escaping (Bool) -> Void) -> Void)?

    var body: some View {
        GeometryReader { geometry in
            let availableHeight = geometry.size.height

            ZStack(alignment: .bottom) {
                // Background screen content
                VStack(spacing: 0) {
                    topTitleHeader

                    Spacer()

                    // Centered status area
                    VStack(spacing: 12) {
                        SalesWaveformView(isListening: isListening)

                        Text(captionText)
                            .font(.system(size: 15, weight: .regular))
                            .foregroundStyle(isListening ? Color.textPrimary : Color.textSecondary)
                            .multilineTextAlignment(.center)
                            .lineSpacing(3)
                            .padding(.horizontal, Spacing.xl)
                            .frame(minHeight: 44)
                            .animation(.easeInOut(duration: 0.2), value: isListening)
                    }

                    Spacer()

                    // Voice Button (Centered)
                    shazamVoiceButton

                    // Scan & Manual buttons
                    secondaryButtonsRow
                        .padding(.top, 20)

                    // Space between buttons and collapsed modal sheet
                    Spacer()
                        .frame(height: 148)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                .screenBackground()

                // Pull-up Modal Sheet
                modalSheet(availableHeight: availableHeight)
            }
        }
        .onAppear {
            viewModel.loadStockData()
            // Register callbacks from UIKit VC
            onTranscriptionUpdate? { text in
                transcribedText = text
            }
            onListeningStateChanged? { listening in
                isListening = listening
                if !listening {
                    // Reset caption after a delay when done
                    DispatchQueue.main.asyncAfter(deadline: .now() + 5) {
                        if !self.isListening {
                            self.transcribedText = ""
                        }
                    }
                }
            }
        }
    }

    // MARK: - Caption Text

    private var captionText: String {
        if isListening || !transcribedText.isEmpty {
            return transcribedText
        }
        return "Tap and speak, scan or add manually\nto record a purchase"
    }

    // MARK: - Top Header

    private var topTitleHeader: some View {
        HStack {
            Text("Stock")
                .font(.displayTitleBold)
                .foregroundStyle(Color.textPrimary)
                .accessibilityAddTraits(.isHeader)

            Spacer()
        }
        .padding(.horizontal, Spacing.lg + 2)
        .padding(.top, Spacing.xs)
        .padding(.bottom, Spacing.sm)
    }

    // MARK: - Shazam-style Voice Button

    private var shazamVoiceButton: some View {
        Button {
            actions.onVoiceEntry()
        } label: {
            ZStack {
                // Pulsing ring when listening
                if isListening {
                    Circle()
                        .stroke(Color.brand.opacity(0.3), lineWidth: 3)
                        .frame(width: 150, height: 150)
                        .scaleEffect(isListening ? 1.15 : 1.0)
                        .opacity(isListening ? 0.0 : 0.6)
                        .animation(.easeInOut(duration: 1.2).repeatForever(autoreverses: false), value: isListening)
                }

                Circle()
                    .fill(isListening ? Color.red : Color.brand)
                    .frame(width: 130, height: 130)
                    .shadow(
                        color: (isListening ? Color.red : Color.brand).opacity(0.38),
                        radius: 18,
                        x: 0,
                        y: 8
                    )

                Image(systemName: isListening ? "stop.fill" : "mic.fill")
                    .font(.system(size: 46, weight: .semibold))
                    .foregroundStyle(Color.white)
            }
            .frame(width: 150, height: 150)
        }
        .buttonStyle(ActionCircleButtonStyle())
        .animation(.easeInOut(duration: 0.25), value: isListening)
    }

    // MARK: - Scan & Manual Row

    private var secondaryButtonsRow: some View {
        HStack(spacing: 56) {
            // Scan Button
            Button {
                actions.onScanEntry()
            } label: {
                VStack(spacing: 6) {
                    Circle()
                        .fill(Color(red: 0.88, green: 0.94, blue: 0.86))
                        .frame(width: 54, height: 54)
                        .overlay {
                            Image(systemName: "camera.viewfinder")
                                .font(.system(size: 22, weight: .medium))
                                .foregroundStyle(Color(red: 0.18, green: 0.38, blue: 0.15))
                        }

                    Text("Scan")
                        .font(.system(size: 13, weight: .regular))
                        .foregroundStyle(Color.textPrimary)
                }
                .frame(width: 70)
            }
            .buttonStyle(ActionCircleButtonStyle())

            // Manual Button
            Button {
                actions.onManualEntry()
            } label: {
                VStack(spacing: 6) {
                    Circle()
                        .fill(Color(red: 0.88, green: 0.94, blue: 0.86))
                        .frame(width: 54, height: 54)
                        .overlay {
                            Image(systemName: "square.and.pencil")
                                .font(.system(size: 20, weight: .medium))
                                .foregroundStyle(Color(red: 0.18, green: 0.38, blue: 0.15))
                        }

                    Text("Manual")
                        .font(.system(size: 13, weight: .regular))
                        .foregroundStyle(Color.textPrimary)
                }
                .frame(width: 70)
            }
            .buttonStyle(ActionCircleButtonStyle())
        }
    }

    // MARK: - Modal Sheet (Liquid Glass)

    private func modalSheet(availableHeight: CGFloat) -> some View {
        let currentHeight = currentSheetHeight(availableHeight: availableHeight)

        return VStack(spacing: 0) {
            // Drag Handle
            Capsule()
                .fill(Color(uiColor: .systemGray3))
                .frame(width: 40, height: 5)
                .padding(.top, 10)
                .padding(.bottom, 12)
                .contentShape(Rectangle())
                .onTapGesture {
                    toggleSheet()
                }
                .frame(maxWidth: .infinity)
                .gesture(dragGesture(availableHeight: availableHeight))

            // Scrollable Sheet Content
            ScrollView(.vertical, showsIndicators: sheetState == .expanded) {
                VStack(alignment: .leading, spacing: Spacing.lg) {
                    summaryTiles
                    itemsSection
                }
                .padding(.horizontal, Spacing.lg)
                .padding(.bottom, Spacing.xxxl)
            }
            .scrollDisabled(sheetState == .collapsed)
        }
        .frame(height: currentHeight, alignment: .top)
        .frame(maxWidth: .infinity)
        .background(.ultraThinMaterial)
        .clipShape(
            UnevenRoundedRectangle(
                topLeadingRadius: 28,
                bottomLeadingRadius: 0,
                bottomTrailingRadius: 0,
                topTrailingRadius: 28,
                style: .continuous
            )
        )
        .shadow(color: Color.black.opacity(0.10), radius: 16, x: 0, y: -6)
        .overlay(alignment: .top) {
            // Subtle top border for glass edge
            UnevenRoundedRectangle(
                topLeadingRadius: 28,
                bottomLeadingRadius: 0,
                bottomTrailingRadius: 0,
                topTrailingRadius: 28,
                style: .continuous
            )
            .stroke(Color.white.opacity(0.3), lineWidth: 0.5)
            .frame(height: currentHeight)
        }
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(.ultraThinMaterial)
                .frame(height: 250)
                .offset(y: 250)
        }
    }

    // MARK: - Summary Tiles

    private var summaryTiles: some View {
        VStack(spacing: Spacing.md) {
            // Row 1: Inventory + Purchase
            HStack(spacing: Spacing.md) {
                ValueTileCard(
                    style: .brand,
                    title: "Inventory",
                    subtitle: "Value",
                    amount: String(format: "₹%.0f", viewModel.totalInventoryValue),
                    countLine: "\(viewModel.totalItemsCount) items",
                    trailingLine: nil
                ) {
                    actions.onInventoryTapped()
                }

                ValueTileCard(
                    style: .beige,
                    title: "Purchase",
                    subtitle: "Today",
                    amount: Money.rounded(viewModel.todayPurchaseAmount),
                    countLine: "\(viewModel.todayPurchaseItemCount) \(viewModel.todayPurchaseItemCount == 1 ? "item" : "items")",
                    trailingLine: nil
                ) {
                    actions.onPurchaseTapped()
                }
            }

            // Row 2: Low Stock + Expiry Alerts
            HStack(spacing: Spacing.md) {
                AlertCardView(
                    title: "Low Stock Alert",
                    subtitle: "\(viewModel.lowStockItemsCount) items",
                    action: { actions.onLowStockTapped() }
                )

                AlertCardView(
                    title: "Expiry Alert",
                    subtitle: "\(viewModel.expiryAlertsCount) items",
                    action: { actions.onExpiryTapped() }
                )
            }
        }
    }

    // MARK: - Items Section

    private var itemsSection: some View {
        VStack(alignment: .leading, spacing: Spacing.md) {
            HStack {
                Text("Items")
                    .font(.system(size: 20, weight: .bold))
                    .foregroundStyle(Color.textPrimary)

                Spacer()
            }
            .padding(.top, Spacing.xs)

            if viewModel.items.isEmpty {
                VStack(spacing: Spacing.md) {
                    Image(systemName: "shippingbox")
                        .font(.system(size: 40, weight: .light))
                        .foregroundStyle(Color(uiColor: .tertiaryLabel))

                    Text("Your stock items will appear here")
                        .font(.subheading)
                        .foregroundStyle(Color.textSecondary)
                }
                .frame(maxWidth: .infinity)
                .padding(.top, Spacing.xl)
                .padding(.bottom, Spacing.xxl)
            } else {
                SectionCard {
                    ForEach(viewModel.items, id: \.id) { item in
                        Button {
                            actions.onItemTapped(item)
                        } label: {
                            HStack {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(item.name)
                                        .font(.system(size: 16, weight: .medium))
                                        .foregroundStyle(Color.textPrimary)
                                    Text("\(item.currentStock.cleanString) \(item.unit)")
                                        .font(.system(size: 14))
                                        .foregroundStyle(Color.textSecondary)
                                }
                                Spacer()
                                Text(String(format: "₹%.0f", item.defaultSellingPrice))
                                    .font(.system(size: 16, weight: .medium))
                                    .foregroundStyle(Color.textPrimary)
                            }
                            .padding(.vertical, 14)
                            .padding(.horizontal, Spacing.lg)
                        }
                    }
                }
            }
        }
    }

    // MARK: - Sheet Drag & Snap Helpers

    private func currentSheetHeight(availableHeight: CGFloat) -> CGFloat {
        let base = sheetState.height(availableHeight: availableHeight)
        let raw = base - dragOffset
        let minHeight = SalesSheetState.collapsed.height(availableHeight: availableHeight)
        let maxHeight = SalesSheetState.expanded.height(availableHeight: availableHeight)
        return max(minHeight, min(raw, maxHeight))
    }

    private func dragGesture(availableHeight: CGFloat) -> some Gesture {
        DragGesture(minimumDistance: 8)
            .onChanged { value in
                dragOffset = value.translation.height
            }
            .onEnded { value in
                let translation = value.translation.height
                let velocity = value.predictedEndTranslation.height - translation
                let projected = translation + velocity * 0.3

                withAnimation(.spring(response: 0.38, dampingFraction: 0.82)) {
                    if projected < -50 {
                        switch sheetState {
                        case .collapsed:
                            sheetState = projected < -180 ? .expanded : .half
                        case .half:
                            sheetState = .expanded
                        case .expanded:
                            break
                        }
                    } else if projected > 50 {
                        switch sheetState {
                        case .expanded:
                            sheetState = projected > 180 ? .collapsed : .half
                        case .half:
                            sheetState = .collapsed
                        case .collapsed:
                            break
                        }
                    }
                    dragOffset = 0
                }
            }
    }

    private func toggleSheet() {
        withAnimation(.spring(response: 0.38, dampingFraction: 0.82)) {
            if sheetState == .collapsed {
                sheetState = .half
            } else if sheetState == .half {
                sheetState = .expanded
            } else {
                sheetState = .collapsed
            }
        }
    }
}

// MARK: - Alert Card View

struct AlertCardView: View {
    let title: String
    let subtitle: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text(title)
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(Color.red)
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(Color(uiColor: .tertiaryLabel))
                }
                Text(subtitle)
                    .font(.system(size: 14, weight: .regular))
                    .foregroundStyle(Color.textPrimary)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.white)
            .clipShape(RoundedRectangle(cornerRadius: Radius.card, style: .continuous))
        }
    }
}
