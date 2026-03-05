import SwiftUI

struct BitcoinWidget: View {
    @State private var price: Double?
    @State private var change24h: Double?
    @State private var isLoading = true

    private let timer = Timer.publish(every: 60, on: .main, in: .common).autoconnect()

    var body: some View {
        ZStack {
            // Obsidian glass background
            RoundedRectangle(cornerRadius: 16)
                .fill(
                    LinearGradient(
                        colors: [
                            Color(red: 0.12, green: 0.12, blue: 0.14).opacity(0.85),
                            Color(red: 0.06, green: 0.06, blue: 0.08).opacity(0.90),
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 16)
                        .stroke(
                            LinearGradient(
                                colors: [
                                    Color.white.opacity(0.15),
                                    Color.white.opacity(0.03),
                                    Color.clear
                                ],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            ),
                            lineWidth: 0.5
                        )
                )
                .shadow(color: .black.opacity(0.3), radius: 8, x: 0, y: 4)

            VStack(spacing: 6) {
                // Header
                HStack {
                    Text("₿")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundColor(Color(red: 0.95, green: 0.75, blue: 0.15))
                    Text("BITCOIN")
                        .font(.system(size: 10, weight: .medium, design: .default))
                        .tracking(2)
                        .foregroundColor(Color.white.opacity(0.5))
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
                            .foregroundColor(Color.white.opacity(0.6))
                        Text(formattedPrice)
                            .font(.system(size: 24, weight: .semibold, design: .rounded))
                            .foregroundColor(.white)
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
