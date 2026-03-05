import SwiftUI

struct BitcoinWidget: View {
    @State private var price: Double?
    @State private var change24h: Double?
    @State private var isLoading = true

    private let timer = Timer.publish(every: 60, on: .main, in: .common).autoconnect()

    var body: some View {
        ZStack {
            // MSN-blue glass background
            RoundedRectangle(cornerRadius: 16)
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
                    RoundedRectangle(cornerRadius: 16)
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
                    RoundedRectangle(cornerRadius: 16)
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
                .shadow(color: Color(red: 0.16, green: 0.46, blue: 0.96).opacity(0.30), radius: 10, x: 0, y: 5)

            VStack(spacing: 6) {
                // Header
                HStack {
                    Text("₿")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundColor(Color(red: 0.95, green: 0.75, blue: 0.15))
                    Text("BITCOIN")
                        .font(.system(size: 10, weight: .medium, design: .default))
                        .tracking(2)
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
                            .font(.system(size: 14, weight: .light))
                            .foregroundColor(Color(red: 0.82, green: 0.90, blue: 1.0).opacity(0.8))
                        Text(formattedPrice)
                            .font(.system(size: 24, weight: .semibold, design: .rounded))
                            .foregroundColor(Color.white.opacity(0.96))
                    }

                    // 24h change
                    if let change = change24h {
                        HStack(spacing: 4) {
                            Image(systemName: change >= 0 ? "arrow.up.right" : "arrow.down.right")
                                .font(.system(size: 9, weight: .bold))
                            Text(String(format: "%.1f%%", abs(change)))
                                .font(.system(size: 11, weight: .medium, design: .rounded))
                            Text("24h")
                                .font(.system(size: 9))
                                .foregroundColor(.white.opacity(0.4))
                        }
                        .foregroundColor(change >= 0 ? Color(red: 0.30, green: 0.85, blue: 0.45) : Color(red: 0.95, green: 0.35, blue: 0.30))
                    }
                }

                Spacer()
            }
            .padding(16)
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
}
