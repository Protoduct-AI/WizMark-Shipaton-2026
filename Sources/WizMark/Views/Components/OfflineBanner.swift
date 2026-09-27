import SwiftUI

struct OfflineBanner: View {

    @Environment(AppServices.self) private var services

    var body: some View {
        if !services.network.isConnected {
            HStack(spacing: 6) {
                Image(systemName: "wifi.slash")
                Text(String(localized: "network.offline", defaultValue: "Offline"))
                    .font(.caption)
                    .fontWeight(.medium)
            }
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 8)
            .background(Color(.systemYellow).opacity(0.1))
        }
    }
}

extension View {
    func offlineBanner() -> some View {
        overlay(alignment: .top) {
            OfflineBanner()
        }
    }
}
