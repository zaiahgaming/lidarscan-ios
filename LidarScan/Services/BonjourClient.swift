import Foundation
import Network
import Darwin

public struct DiscoveredStudio: Identifiable, Hashable {
    public let id: String
    public let name: String
    public let host: String
    public let port: Int

    public var urlString: String {
        "http://\(host):\(port)"
    }
}

public final class BonjourClient: NSObject, ObservableObject, NetServiceBrowserDelegate, NetServiceDelegate {
    @Published public var discoveredServers: [DiscoveredStudio] = []
    @Published public var isBrowsing: Bool = false

    private var netServiceBrowser: NetServiceBrowser?
    private var resolvingServices: [NetService] = []
    private var resolvedMap: [String: DiscoveredStudio] = [:]

    public override init() {
        super.init()
    }

    public func startBrowsing() {
        stopBrowsing()
        isBrowsing = true
        netServiceBrowser = NetServiceBrowser()
        netServiceBrowser?.delegate = self
        netServiceBrowser?.searchForServices(ofType: "_lidarscan._tcp.", inDomain: "local.")
    }

    public func stopBrowsing() {
        netServiceBrowser?.stop()
        netServiceBrowser = nil
        resolvingServices.forEach { $0.stop() }
        resolvingServices.removeAll()
        isBrowsing = false
    }

    // MARK: - NetServiceBrowserDelegate

    public func netServiceBrowser(_ browser: NetServiceBrowser, didFind service: NetService, moreComing: Bool) {
        service.delegate = self
        resolvingServices.append(service)
        service.resolve(withTimeout: 5.0)
    }

    public func netServiceBrowser(_ browser: NetServiceBrowser, didRemove service: NetService, moreComing: Bool) {
        resolvingServices.removeAll { $0 == service }
        resolvedMap.removeValue(forKey: service.name)
        DispatchQueue.main.async {
            self.discoveredServers = Array(self.resolvedMap.values)
        }
    }

    // MARK: - NetServiceDelegate

    public func netServiceDidResolveAddress(_ sender: NetService) {
        let name = sender.name
        let port = sender.port
        var hostName = sender.hostName ?? "localhost"
        if hostName.hasSuffix(".") {
            hostName.removeLast()
        }

        // Extract IP address from addresses data if available
        var ipAddress = hostName
        if let addresses = sender.addresses {
            for data in addresses {
                data.withUnsafeBytes { rawPtr in
                    let sockaddr = rawPtr.bindMemory(to: sockaddr.self).baseAddress!
                    if sockaddr.pointee.sa_family == UInt8(AF_INET) {
                        var addr = rawPtr.bindMemory(to: sockaddr_in.self).baseAddress!.pointee.sin_addr
                        var buffer = [CChar](repeating: 0, count: Int(INET_ADDRSTRLEN))
                        if inet_ntop(AF_INET, &addr, &buffer, socklen_t(INET_ADDRSTRLEN)) != nil {
                            ipAddress = String(cString: buffer)
                        }
                    }
                }
            }
        }

        let studio = DiscoveredStudio(
            id: name,
            name: name,
            host: ipAddress,
            port: port > 0 ? port : 8765
        )

        resolvedMap[name] = studio
        DispatchQueue.main.async {
            self.discoveredServers = Array(self.resolvedMap.values)
        }
    }

    public func netService(_ sender: NetService, didNotResolve errorDict: [String: NSNumber]) {
        resolvingServices.removeAll { $0 == sender }
    }
}
