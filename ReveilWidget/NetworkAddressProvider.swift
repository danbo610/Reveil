//
//  NetworkAddressProvider.swift
//  ReveilWidget
//
//  Reads the three public addresses ip111.cn reports. They differ from each other whenever a
//  rule-based proxy sends each class of traffic out of a different exit, which is the point of
//  showing all three: domestic sites go direct, ordinary foreign sites through one node, and
//  sites that need a proxy through another.
//
//  Each value comes from a probe that lives in the matching place. ip111.cn renders the domestic
//  address into its own page — its server is in China, so the address it sees is the one used for
//  domestic traffic. The other two are the probes its page embeds as iframes. Both check the
//  Referer, so requests carry the one their page sends.
//

import Foundation

#if canImport(Darwin)
import Darwin
#endif

struct NetworkAddress {
    let address: String
    let location: String

    // The probes answer "113.90.130.56<br/>中国 深圳" — address, then markup, then the place.
    // The separator is not always the same: it has been seen as a plain space and as <br/>, so
    // every tag is turned into whitespace before the value is split rather than assuming either.
    init?(reported: String?) {
        guard let reported else { return nil }
        let stripped = reported.replacingOccurrences(
            of: "<[^>]+>", with: " ", options: .regularExpression
        )
        let fields = stripped
            .components(separatedBy: .whitespacesAndNewlines)
            .filter { !$0.isEmpty }
        guard let first = fields.first, first.contains(".") else { return nil }
        address = first
        location = fields.dropFirst().joined(separator: " ")
    }
}

struct NetworkAddresses {
    var local: String?
    var domestic: NetworkAddress?
    var foreign: NetworkAddress?
    var blocked: NetworkAddress?

    var publicAddresses: [String] {
        [domestic?.address, foreign?.address, blocked?.address].compactMap { $0 }
    }

    static let placeholder = NetworkAddresses(
        local: "192.168.1.100",
        domestic: NetworkAddress(reported: "113.90.130.56<br/>中国 深圳"),
        foreign: NetworkAddress(reported: "23.132.124.147<br/>美国 洛杉矶"),
        blocked: NetworkAddress(reported: "104.21.70.10<br/>美国 圣何塞")
    )
}

enum NetworkAddressProvider {
    // The widget's kind. Shared so that the app reloads exactly the widget it has data for.
    static let widgetKind = "NetworkAddressWidget"

    private static let domesticPageURL = URL(string: "https://ip111.cn/")!
    private static let foreignProbeURL = URL(string: "https://us.ip111.cn/ip.php")!
    private static let blockedProbeURL = URL(string: "https://sspanel.net/ip.php")!
    private static let referer = "https://ip111.cn/"
    private static let timeout: TimeInterval = 8

    // Read straight from the interface list — no network involved, so it is always available even
    // when every probe times out. Deliberately self-contained rather than reusing the app's
    // interface models, because this file is compiled into the widget too.
    static var localAddress: String? {
        var interfaces: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&interfaces) == 0 else { return nil }
        defer { freeifaddrs(interfaces) }

        var wifi: String?
        var cellular: String?
        var pointer = interfaces
        while let current = pointer {
            let interface = current.pointee
            pointer = interface.ifa_next

            guard interface.ifa_flags & UInt32(IFF_UP) != 0,
                  let address = interface.ifa_addr,
                  address.pointee.sa_family == UInt8(AF_INET)
            else {
                continue
            }

            var host = [CChar](repeating: 0, count: Int(NI_MAXHOST))
            guard getnameinfo(address, socklen_t(address.pointee.sa_len),
                              &host, socklen_t(host.count), nil, 0, NI_NUMERICHOST) == 0
            else {
                continue
            }

            let name = String(cString: interface.ifa_name)
            let value = String(cString: host)
            if name == "en0" {
                wifi = value
            } else if name == "pdp_ip0" {
                cellular = value
            }
        }

        // Wi-Fi first: when both are up it is the one carrying the traffic.
        return wifi ?? cellular
    }

    static func current() async -> NetworkAddresses {
        // Concurrently, so one slow probe does not hold up the other two. A probe that cannot be
        // reached simply yields nil, which the view renders as a dash rather than stale data.
        async let domestic = fetch(domesticPageURL, parser: addressFromPage)
        async let foreign = fetch(foreignProbeURL, parser: addressFromProbe)
        async let blocked = fetch(blockedProbeURL, parser: addressFromProbe)

        return await NetworkAddresses(
            local: localAddress,
            domestic: NetworkAddress(reported: domestic),
            foreign: NetworkAddress(reported: foreign),
            blocked: NetworkAddress(reported: blocked)
        )
    }

    private static func fetch(_ url: URL, parser: @escaping (String) -> String?) async -> String? {
        var request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalAndRemoteCacheData,
                                 timeoutInterval: timeout)
        request.setValue(referer, forHTTPHeaderField: "Referer")
        request.setValue("Mozilla/5.0", forHTTPHeaderField: "User-Agent")

        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = timeout
        configuration.timeoutIntervalForResource = timeout
        let session = URLSession(configuration: configuration)

        guard let (data, _) = try? await session.data(for: request),
              let body = String(data: data, encoding: .utf8)
        else {
            return nil
        }
        return parser(body)
    }

    // "…从国内测试…<div class="card-body">\n<p>\n113.90.130.56<br/>中国 深圳</p>"
    private static func addressFromPage(_ body: String) -> String? {
        guard let marker = body.range(of: "从国内测试") else { return nil }
        let tail = body[marker.upperBound...]
        guard let open = tail.range(of: "<p>") else { return nil }
        let afterOpen = tail[open.upperBound...]
        guard let close = afterOpen.range(of: "</p>") else { return nil }
        return String(afterOpen[..<close.lowerBound])
    }

    // "<div style="text-align:center">23.132.124.147<br/>美国 洛杉矶</div>"
    private static func addressFromProbe(_ body: String) -> String? {
        guard let open = body.range(of: ">"), let close = body.range(of: "</div>"),
              open.upperBound <= close.lowerBound
        else {
            return nil
        }
        return String(body[open.upperBound ..< close.lowerBound])
    }
}
