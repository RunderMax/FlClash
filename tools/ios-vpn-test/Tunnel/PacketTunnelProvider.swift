import NetworkExtension

final class PacketTunnelProvider: NEPacketTunnelProvider {
    // No route enters the tunnel, so the phone keeps using its own network.
    override func startTunnel(
        options: [String: NSObject]?,
        completionHandler: @escaping (Error?) -> Void
    ) {
        let settings = NEPacketTunnelNetworkSettings(tunnelRemoteAddress: "127.0.0.1")
        settings.ipv4Settings = NEIPv4Settings(
            addresses: ["198.18.0.1"],
            subnetMasks: ["255.255.255.255"]
        )
        setTunnelNetworkSettings(settings, completionHandler: completionHandler)
    }

    override func stopTunnel(
        with reason: NEProviderStopReason,
        completionHandler: @escaping () -> Void
    ) {
        completionHandler()
    }
}
