import SwiftUI

struct GatewayStatusPanel: View {
    @EnvironmentObject var gatewayClient: GatewayClient

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Gateway")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundColor(.white.opacity(0.94))
                Spacer()
                Text(gatewayClient.transportMode.rawValue.uppercased())
                    .font(.system(size: 9, weight: .bold))
                    .foregroundColor(Color(red: 0.65, green: 0.80, blue: 1.0))
            }
            Text(gatewayClient.connectionStatus)
                .font(.system(size: 11.5, weight: .medium))
                .foregroundColor(Color.white.opacity(0.7))
            VStack(alignment: .leading, spacing: 8) {
                ForEach(gatewayClient.sessions) { session in
                    VStack(alignment: .leading, spacing: 3) {
                        Text(session.label)
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundColor(.white.opacity(0.9))
                        Text(session.preview)
                            .font(.system(size: 10, weight: .medium))
                            .foregroundColor(.white.opacity(0.56))
                            .lineLimit(2)
                    }
                    .padding(10)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Color.white.opacity(0.04)))
                }
            }
        }
        .padding(14)
        .background(RoundedRectangle(cornerRadius: 18, style: .continuous).fill(Color.white.opacity(0.04)).overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).stroke(Color.white.opacity(0.06), lineWidth: 1)))
    }
}
