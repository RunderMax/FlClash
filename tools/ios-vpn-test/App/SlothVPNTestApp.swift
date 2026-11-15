import NetworkExtension
import SwiftUI

@main
struct SlothVPNTestApp: App {
    var body: some Scene {
        WindowGroup {
            ContentView()
        }
    }
}

final class TunnelModel: ObservableObject {
    @Published var status = "还没连接"
    private var manager: NETunnelProviderManager?
    private var observer: NSObjectProtocol?
    private var connectedOnce = false

    init() {
        observer = NotificationCenter.default.addObserver(
            forName: .NEVPNStatusDidChange, object: nil, queue: .main
        ) { [weak self] _ in
            self?.refresh()
        }
    }

    // A signing tool may rename the extension, so it is found rather than assumed.
    private var tunnelBundleId: String? {
        guard let plugins = Bundle.main.builtInPlugInsURL,
              let urls = try? FileManager.default.contentsOfDirectory(
                  at: plugins, includingPropertiesForKeys: nil
              )
        else {
            return nil
        }
        return urls
            .filter { $0.pathExtension == "appex" }
            .compactMap { Bundle(url: $0)?.bundleIdentifier }
            .first
    }

    func connect() {
        guard let tunnelId = tunnelBundleId else {
            status = "❌ 找不到 VPN 组件"
            return
        }
        status = "正在连接…"
        connectedOnce = false
        NETunnelProviderManager.loadAllFromPreferences { managers, error in
            if let error {
                self.fail("读取配置失败", error)
                return
            }
            let manager = managers?.first ?? NETunnelProviderManager()
            let config = NETunnelProviderProtocol()
            config.providerBundleIdentifier = tunnelId
            config.serverAddress = "Sloth"
            manager.protocolConfiguration = config
            manager.localizedDescription = "Sloth 测试"
            manager.isEnabled = true
            manager.saveToPreferences { error in
                if let error {
                    self.fail("保存 VPN 配置失败", error)
                    return
                }
                manager.loadFromPreferences { error in
                    if let error {
                        self.fail("读取配置失败", error)
                        return
                    }
                    do {
                        try manager.connection.startVPNTunnel()
                        DispatchQueue.main.async {
                            self.manager = manager
                            self.refresh()
                        }
                    } catch {
                        self.fail("启动失败", error)
                    }
                }
            }
        }
    }

    func disconnect() {
        manager?.connection.stopVPNTunnel()
    }

    private func fail(_ step: String, _ error: Error) {
        DispatchQueue.main.async {
            self.status = "❌ \(step)：\(error.localizedDescription)"
        }
    }

    private func refresh() {
        guard let connection = manager?.connection else {
            return
        }
        switch connection.status {
        case .connected:
            connectedOnce = true
            status = "✅ 已连接，证书支持 VPN"
        case .connecting, .reasserting:
            status = "正在连接…"
        case .disconnecting:
            status = "正在断开…"
        case .disconnected:
            if connectedOnce {
                status = "已断开"
            } else {
                status = "❌ 没能连上，多半是证书不支持 VPN"
                showLastError(of: connection)
            }
        case .invalid:
            status = "❌ VPN 配置无效"
        @unknown default:
            status = "未知状态"
        }
    }

    private func showLastError(of connection: NEVPNConnection) {
        guard #available(iOS 16.0, *) else {
            return
        }
        connection.fetchLastDisconnectError { error in
            guard let error else {
                return
            }
            DispatchQueue.main.async {
                self.status = "❌ 没能连上：\(error.localizedDescription)"
            }
        }
    }
}

struct ContentView: View {
    @StateObject private var model = TunnelModel()

    var body: some View {
        VStack(spacing: 24) {
            Text("Sloth VPN 测试").font(.title.bold())
            Text(model.status).multilineTextAlignment(.center)
            Button("连接") { model.connect() }
                .buttonStyle(.borderedProminent)
            Button("断开") { model.disconnect() }
        }
        .padding(32)
    }
}
