//
//  ConnectionStatus.swift
//  FruitcakeAi
//
//  A slim banner that appears at the top of the chat when the backend is
//  unreachable. Renders nothing at all when connected — zero layout cost.
//

import SwiftUI

struct ConnectionStatus: View {

    @Environment(ConnectivityMonitor.self) private var monitor

    var body: some View {
        if !monitor.isBackendReachable {
            HStack(spacing: 8) {
                Image(systemName: "wifi.exclamationmark")
                    .imageScale(.small)
                Text("Offline — using on-device AI")
                    .font(.caption.weight(.medium))
            }
            .foregroundStyle(.orange)
            .padding(.vertical, 6)
            .padding(.horizontal, 14)
            .frame(maxWidth: .infinity)
            .background(.orange.opacity(0.12))
            .transition(.move(edge: .top).combined(with: .opacity))
        }
    }
}

#Preview {
    VStack {
        // Simulate offline state by constructing monitor via AuthManager stub
        ConnectionStatus()
            .environment(ConnectivityMonitor(authManager: AuthManager()))
    }
}
