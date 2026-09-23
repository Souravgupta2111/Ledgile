import SwiftUI

// MARK: - Sheet State

enum SalesSheetState {
    case collapsed
    case half
    case expanded

    func height(availableHeight: CGFloat) -> CGFloat {
        switch self {
        case .collapsed:
            return 118
        case .half:
            return min(availableHeight * 0.58, 495)
        case .expanded:
            return max(availableHeight - 50, 520)
        }
    }
}

// MARK: - Navigation Actions

/// Callback-based navigation so UIKit host can perform segues / pushes.
struct SalesNavigationActions {
    var onManualEntry: () -> Void = {}
    var onVoiceEntry: () -> Void = {}
    var onScanEntry: () -> Void = {}
    var onRevenueTapped: () -> Void = {}
    var onProfitTapped: () -> Void = {}
    var onTransactionTapped: (Transaction) -> Void = { _ in }
}

// MARK: - Sales View

struct SalesTabView: View {

    @State private var viewModel = SalesTabViewModel()
    @State private var sheetState: SalesSheetState = .collapsed
    @State private var dragOffset: CGFloat = 0

    // Voice button visual state (no actual recording — delegates to UIKit VC)
    @State private var isVoiceActive = false
    @State private var ripplePulse = false

    var actions = SalesNavigationActions()

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
                        SalesWaveformView(isListening: false)

                        Text("Tap and speak, scan or add manually\nto record a sale")
                            .font(.system(size: 15, weight: .regular))
                            .foregroundStyle(Color.textSecondary)
                            .multilineTextAlignment(.center)
                            .lineSpacing(3)
                            .padding(.horizontal, Spacing.xl)
                            .frame(minHeight: 44)
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
            viewModel.loadSalesData()
        }
    }

    // MARK: - Top Header

    private var topTitleHeader: some View {
        HStack {
            Text("Sales")
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
                Circle()
                    .fill(Color.brand)
                    .frame(width: 130, height: 130)
                    .shadow(
                        color: Color.brand.opacity(0.38),
                        radius: 18,
                        x: 0,
                        y: 8
                    )

                Image(systemName: "mic.fill")
                    .font(.system(size: 46, weight: .semibold))
                    .foregroundStyle(Color.white)
            }
            .frame(width: 130, height: 130)
        }
        .buttonStyle(ActionCircleButtonStyle())
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
                            Image(systemName: "qrcode.viewfinder")
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
                            Image(systemName: "pencil")
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

    // MARK: - Modal Sheet

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
                .background(Color(.systemBackground))
                .gesture(dragGesture(availableHeight: availableHeight))

            // Scrollable Sheet Content
            ScrollView(.vertical, showsIndicators: sheetState == .expanded) {
                VStack(alignment: .leading, spacing: Spacing.lg) {
                    summaryTiles
                    transactionsSection
                }
                .padding(.horizontal, Spacing.lg)
                .padding(.bottom, Spacing.xxxl)
            }
            .scrollDisabled(sheetState == .collapsed)
        }
        .frame(height: currentHeight, alignment: .top)
        .frame(maxWidth: .infinity)
        .background(Color(.systemBackground))
        .clipShape(
            UnevenRoundedRectangle(
                topLeadingRadius: 28,
                bottomLeadingRadius: 0,
                bottomTrailingRadius: 0,
                topTrailingRadius: 28,
                style: .continuous
            )
        )
        .shadow(color: Color.black.opacity(0.08), radius: 12, x: 0, y: -4)
        .overlay(alignment: .bottom) {
            Color(.systemBackground)
                .frame(height: 250)
                .offset(y: 250)
        }
    }

    // MARK: - Date Picker

    private var datePickerView: some View {
        DatePicker(
            "Select Date",
            selection: Binding(get: { viewModel.selectedDate },
                               set: { viewModel.selectedDate = $0 }),
            in: viewModel.selectableDates,
            displayedComponents: .date
        )
        .labelsHidden()
        .datePickerStyle(.compact)
        .tint(Color.brand)
    }

    // MARK: - Summary Tiles

    private var summaryTiles: some View {
        HStack(spacing: Spacing.md) {
            ValueTileCard(
                style: .brand,
                title: "Revenue",
                subtitle: "Today",
                amount: Money.rounded(viewModel.revenue),
                countLine: "\(viewModel.receiptCount) receipts",
                trailingLine: PercentChange.line(viewModel.salesPercentChange, on: .brand)
            ) {
                actions.onRevenueTapped()
            }

            ValueTileCard(
                style: .beige,
                title: "Profit",
                subtitle: "Today",
                amount: Money.rounded(viewModel.profit),
                countLine: "\(Quantity.plain(viewModel.itemsSoldCount)) \(Int(viewModel.itemsSoldCount) > 1 ? "items" : "item")",
                trailingLine: PercentChange.line(viewModel.profitPercentChange, on: .beige)
            ) {
                actions.onProfitTapped()
            }
        }
    }

    // MARK: - Transactions Section

    private var transactionsSection: some View {
        VStack(alignment: .leading, spacing: Spacing.md) {
            HStack {
                Text("Transactions")
                    .font(.system(size: 20, weight: .bold))
                    .foregroundStyle(Color.textPrimary)

                Spacer()

                datePickerView
            }
            .padding(.top, Spacing.xs)

            if viewModel.isEmpty {
                VStack(spacing: Spacing.md) {
                    Image(systemName: "cart")
                        .font(.system(size: 40, weight: .light))
                        .foregroundStyle(Color(uiColor: .tertiaryLabel))

                    Text("Sales you make will appear here")
                        .font(.subheading)
                        .foregroundStyle(Color.textSecondary)
                }
                .frame(maxWidth: .infinity)
                .padding(.top, Spacing.xl)
                .padding(.bottom, Spacing.xxl)
            } else {
                SectionCard {
                    ForEach(viewModel.filteredTransactions, id: \.transaction.id) { entry in
                        TransactionRow(transaction: entry.transaction,
                                       itemsSummary: entry.itemsSummary) {
                            actions.onTransactionTapped(entry.transaction)
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
            switch sheetState {
            case .collapsed:
                sheetState = .half
            case .half:
                sheetState = .collapsed
            case .expanded:
                sheetState = .half
            }
        }
    }

    /// Reload data (called by host VC on viewWillAppear).
    func reload() {
        viewModel.loadSalesData()
    }
}

// MARK: - Audio Waveform View

struct SalesWaveformView: View {
    var isListening: Bool = false

    private let baseHeights: [CGFloat] = [16, 26, 38, 26, 16]
    @State private var animating = false

    var body: some View {
        HStack(spacing: 4.5) {
            ForEach(0..<baseHeights.count, id: \.self) { index in
                Capsule()
                    .fill(isListening ? Color.brand : Color(uiColor: .systemGray3))
                    .frame(width: 3.5, height: height(for: index))
            }
        }
        .animation(.easeInOut(duration: 0.2), value: isListening)
        .onAppear {
            if isListening {
                startAnimation()
            }
        }
        .onChange(of: isListening) { _, listening in
            if listening {
                startAnimation()
            } else {
                animating = false
            }
        }
    }

    private func height(for index: Int) -> CGFloat {
        guard isListening, animating else { return baseHeights[index] }
        let factors: [CGFloat] = [1.6, 0.7, 1.2, 0.8, 1.5]
        return baseHeights[index] * factors[index]
    }

    private func startAnimation() {
        withAnimation(.easeInOut(duration: 0.4).repeatForever(autoreverses: true)) {
            animating = true
        }
    }
}

// MARK: - Button Press Style

struct ActionCircleButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.92 : 1.0)
            .animation(.easeOut(duration: 0.15), value: configuration.isPressed)
    }
}
