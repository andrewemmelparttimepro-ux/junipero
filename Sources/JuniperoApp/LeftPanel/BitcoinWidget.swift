import SwiftUI

enum BitcoinWidgetStyle {
    case regular
    case compact
}

struct BitcoinWidget: View {
    let style: BitcoinWidgetStyle
    @State private var price: Double?
    @State private var change24h: Double?
    @State private var isLoading = true

    private let timer = Timer.publish(every: 60, on: .main, in: .common).autoconnect()

    init(style: BitcoinWidgetStyle = .regular) {
        self.style = style
    }

    var body: some View {
        ZStack {
            // MSN-blue glass background
            RoundedRectangle(cornerRadius: metrics.cornerRadius)
                .fill(
                    LinearGradient(
                        colors: [
                            Color(red: 0.19, green: 0.34, blue: 0.62).opacity(0.90),
                            Color(red: 0.10, green: 0.22, blue: 0.48).opacity(0.94),
                            Color(red: 0.06, green: 0.16, blue: 0.38).opacity(0.96),
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .overlay(
                    RoundedRectangle(cornerRadius: metrics.cornerRadius)
                        .fill(
                            LinearGradient(
                                colors: [
                                    Color.white.opacity(0.16),
                                    Color.white.opacity(0.05),
                                    Color.clear,
                                ],
                                startPoint: .top,
                                endPoint: .bottom
                            )
                        )
                )
                .overlay(
                    RoundedRectangle(cornerRadius: metrics.cornerRadius)
                        .stroke(
                            LinearGradient(
                                colors: [
                                    Color(red: 0.62, green: 0.84, blue: 1.0).opacity(0.55),
                                    Color.white.opacity(0.10),
                                    Color.clear
                                ],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            ),
                            lineWidth: 0.8
                        )
                )
                .shadow(color: Color(red: 0.16, green: 0.46, blue: 0.96).opacity(0.28), radius: metrics.shadowRadius, x: 0, y: metrics.shadowYOffset)

            VStack(spacing: metrics.verticalSpacing) {
                // Header
                HStack {
                    Text("₿")
                        .font(.system(size: metrics.symbolSize, weight: .bold))
                        .foregroundColor(Color(red: 0.95, green: 0.75, blue: 0.15))
                    Text("BITCOIN")
                        .font(.system(size: metrics.headerSize, weight: .medium, design: .default))
                        .tracking(metrics.headerTracking)
                        .foregroundColor(Color(red: 0.86, green: 0.94, blue: 1.0).opacity(0.75))
                    Spacer()
                }

                Spacer()

                if isLoading && price == nil {
                    ProgressView()
                        .scaleEffect(0.6)
                        .tint(.white.opacity(0.5))
                } else {
                    // Price
                    HStack(alignment: .firstTextBaseline) {
                        Text("$")
                            .font(.system(size: metrics.pricePrefixSize, weight: .light))
                            .foregroundColor(Color(red: 0.82, green: 0.90, blue: 1.0).opacity(0.8))
                        Text(formattedPrice)
                            .font(.system(size: metrics.priceSize, weight: .semibold, design: .rounded))
                            .foregroundColor(Color.white.opacity(0.96))
                    }

                    // 24h change
                    if let change = change24h {
                        HStack(spacing: 4) {
                            Image(systemName: change >= 0 ? "arrow.up.right" : "arrow.down.right")
                                .font(.system(size: metrics.changeIconSize, weight: .bold))
                            Text(String(format: "%.1f%%", abs(change)))
                                .font(.system(size: metrics.changeTextSize, weight: .medium, design: .rounded))
                            Text("24h")
                                .font(.system(size: metrics.changeCaptionSize))
                                .foregroundColor(.white.opacity(0.4))
                        }
                        .foregroundColor(change >= 0 ? Color(red: 0.30, green: 0.85, blue: 0.45) : Color(red: 0.95, green: 0.35, blue: 0.30))
                    }
                }

                Spacer()
            }
            .padding(metrics.padding)
        }
        .task {
            await fetchPrice()
        }
        .onReceive(timer) { _ in
            Task { await fetchPrice() }
        }
    }

    private var formattedPrice: String {
        guard let price = price else { return "—" }
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.maximumFractionDigits = 0
        return formatter.string(from: NSNumber(value: price)) ?? "—"
    }

    private func fetchPrice() async {
        guard let url = URL(string: "https://api.coingecko.com/api/v3/simple/price?ids=bitcoin&vs_currencies=usd&include_24hr_change=true") else { return }

        do {
            let (data, _) = try await URLSession.shared.data(from: url)
            if let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
               let btc = json["bitcoin"] as? [String: Any] {
                await MainActor.run {
                    self.price = btc["usd"] as? Double
                    self.change24h = btc["usd_24h_change"] as? Double
                    self.isLoading = false
                }
            }
        } catch {
            print("BTC fetch error: \(error)")
            await MainActor.run {
                self.isLoading = false
            }
        }
    }

    private var metrics: Metrics {
        switch style {
        case .regular:
            return Metrics(
                cornerRadius: 16,
                shadowRadius: 10,
                shadowYOffset: 5,
                padding: 16,
                verticalSpacing: 6,
                symbolSize: 14,
                headerSize: 10,
                headerTracking: 2,
                pricePrefixSize: 14,
                priceSize: 24,
                changeIconSize: 9,
                changeTextSize: 11,
                changeCaptionSize: 9
            )
        case .compact:
            return Metrics(
                cornerRadius: 14,
                shadowRadius: 8,
                shadowYOffset: 4,
                padding: 14,
                verticalSpacing: 5,
                symbolSize: 12,
                headerSize: 9,
                headerTracking: 1.8,
                pricePrefixSize: 12,
                priceSize: 20,
                changeIconSize: 8,
                changeTextSize: 10,
                changeCaptionSize: 8
            )
        }
    }

    private struct Metrics {
        let cornerRadius: CGFloat
        let shadowRadius: CGFloat
        let shadowYOffset: CGFloat
        let padding: CGFloat
        let verticalSpacing: CGFloat
        let symbolSize: CGFloat
        let headerSize: CGFloat
        let headerTracking: CGFloat
        let pricePrefixSize: CGFloat
        let priceSize: CGFloat
        let changeIconSize: CGFloat
        let changeTextSize: CGFloat
        let changeCaptionSize: CGFloat
    }
}
