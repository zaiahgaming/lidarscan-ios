import Foundation
import Network
import Darwin

public struct DiscoveredStudio: Identifiable, Hashable {
    public let id: String
    public let name: String
    public let host: String
    public let port: Int
    public let candidateIPs: [String]

    public init(id: String, name: String, host: String, port: Int, candidateIPs: [String] = []) {
        self.id = id
        self.name = name
        self.host = host
        self.port = port
        self.candidateIPs = candidateIPs
    }

    public var urlString: String {
        "http://\(host):\(port)"
    }
}

public final class BonjourClient: NSObject, ObservableObject, NetServiceBrowserDelegate, NetServiceDelegate {
    @Published public var discoveredServers: [DiscoveredStudio] = []
    @Published public var isBrowsing: Bool = false
    @Published public var browseError: String?

    private var netServiceBrowser: NetServiceBrowser?
    private var resolvingServices: [NetService] = []
    private var resolvedMap: [String: DiscoveredStudio] = [:]

    public override init() {
        super.init()
    }

    public func startBrowsing() {
        stopBrowsing()
        browseError = nil
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

    public func netServiceBrowser(_ browser: NetServiceBrowser, didNotSearch errorDict: [String: NSNumber]) {
        DispatchQueue.main.async {
            self.isBrowsing = false
            self.browseError = "Bonjour search failed. Check LidarScan's Local Network access in Settings, or enter a server address manually."
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

        var candidateIPs: [String] = []
        if let addresses = sender.addresses {
            for data in addresses {
                guard data.count >= MemoryLayout<sockaddr>.size else { continue }
                data.withUnsafeBytes { rawPtr in
                    guard let base = rawPtr.baseAddress else { return }
                    let sa = base.assumingMemoryBound(to: sockaddr.self)
                    if sa.pointee.sa_family == UInt8(AF_INET) && data.count >= MemoryLayout<sockaddr_in>.size {
                        let sin = base.assumingMemoryBound(to: sockaddr_in.self)
                        var addr = sin.pointee.sin_addr
                        var buffer = [CChar](repeating: 0, count: Int(INET_ADDRSTRLEN))
                        if inet_ntop(AF_INET, &addr, &buffer, socklen_t(INET_ADDRSTRLEN)) != nil {
                            let ip = String(cString: buffer)
                            if !ip.isEmpty && ip != "127.0.0.1" && !candidateIPs.contains(ip) {
                                candidateIPs.append(ip)
                            }
                        }
                    }
                }
            }
        }

        // Sort candidate IPs so that typical home/office Wi-Fi (192.168.x.x, 10.x.x.x) come first,
        // and virtual/hotspot/docker subnets (172.x.x.x) come last.
        candidateIPs.sort { ip1, ip2 in
            func rank(_ ip: String) -> Int {
                if ip.hasPrefix("192.168.") { return 0 }
                if ip.hasPrefix("10.") { return 1 }
                return 2
            }
            let r1 = rank(ip1)
            let r2 = rank(ip2)
            if r1 != r2 { return r1 < r2 }
            return ip1 < ip2
        }

        let bestHost = candidateIPs.first ?? hostName

        let studio = DiscoveredStudio(
            id: name,
            name: name,
            host: bestHost,
            port: port > 0 ? port : 8765,
            candidateIPs: candidateIPs
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
