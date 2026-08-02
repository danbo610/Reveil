//
//  NetworkAddressDetailsModel.swift
//  Reveil
//
//  Resolves the public addresses shown on the dashboard through ip.im. Requests are deliberately
//  sequential to preserve the card's domestic/foreign/blocked order and stay well inside the
//  service's rate limit; each completed lookup is published immediately.
//

import Combine
import Foundation

private struct NetworkAddressDetails {
    struct Field {
        let name: String
        let value: String
    }

    let address: String
    let fields: [Field]
}

private enum NetworkAddressDetailsProvider {
    private static let baseURL = URL(string: "https://ip.im")!
    private static let timeout: TimeInterval = 10

    private static let fieldOrder = [
        "hostname", "city", "region", "country", "loc", "org", "postal", "timezone", "asn",
    ]

    private static let fieldNames = [
        "hostname": "Hostname",
        "city": "City",
        "region": "Region",
        "country": "Country",
        "loc": "Loc",
        "org": "Org",
        "postal": "Postal",
        "timezone": "Timezone",
        "asn": "ASN",
    ]

    static func details(for address: String) async -> NetworkAddressDetails? {
        let url = baseURL.appendingPathComponent(address)
        var request = URLRequest(
            url: url,
            cachePolicy: .reloadIgnoringLocalAndRemoteCacheData,
            timeoutInterval: timeout
        )
        request.setValue("text/plain", forHTTPHeaderField: "Accept")
        // ip.im serves its key/value response to command-line clients and a full HTML page to
        // browsers, so match the curl request this feature is intended to perform.
        request.setValue("curl/8.7.1", forHTTPHeaderField: "User-Agent")

        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = timeout
        configuration.timeoutIntervalForResource = timeout
        let session = URLSession(configuration: configuration)

        guard let (data, response) = try? await session.data(for: request),
              let response = response as? HTTPURLResponse,
              (200 ..< 300).contains(response.statusCode),
              let body = String(data: data, encoding: .utf8)
        else {
            return nil
        }

        return parse(body, expectedAddress: address)
    }

    private static func parse(_ body: String, expectedAddress: String) -> NetworkAddressDetails? {
        var values = [String: String]()

        for rawLine in body.split(whereSeparator: { $0.isNewline }) {
            let line = String(rawLine).trimmingCharacters(in: .whitespacesAndNewlines)
            guard let separator = line.firstIndex(of: ":") else { continue }

            let key = String(line[..<separator])
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .lowercased()
            let value = String(line[line.index(after: separator)...])
                .trimmingCharacters(in: .whitespacesAndNewlines)

            guard key == "ip" || fieldNames[key] != nil, !value.isEmpty else { continue }
            values[key] = value
        }

        guard values["ip"] == expectedAddress else { return nil }
        let fields = fieldOrder.compactMap { key -> NetworkAddressDetails.Field? in
            guard let name = fieldNames[key], let value = values[key] else { return nil }
            return NetworkAddressDetails.Field(name: name, value: value)
        }
        guard !fields.isEmpty else { return nil }

        return NetworkAddressDetails(address: expectedAddress, fields: fields)
    }
}

@MainActor
final class NetworkAddressDetailsModel: ObservableObject {
    @Published private(set) var entries = [BasicEntry]()
    @Published private(set) var isLoading = false

    private var requestedAddresses = [String]()
    private var requestID = UUID()
    private var lookupTask: Task<Void, Never>?

    deinit {
        lookupTask?.cancel()
    }

    func load(addresses: [String]) {
        let uniqueAddresses = Self.unique(addresses)
        guard uniqueAddresses != requestedAddresses else { return }

        requestedAddresses = uniqueAddresses
        lookupTask?.cancel()
        requestID = UUID()
        let currentRequestID = requestID
        entries = []

        guard !uniqueAddresses.isEmpty else {
            isLoading = false
            return
        }

        isLoading = true
        lookupTask = Task { [weak self] in
            for address in uniqueAddresses {
                guard !Task.isCancelled else { return }
                let details = await NetworkAddressDetailsProvider.details(for: address)
                guard let self,
                      !Task.isCancelled,
                      self.requestID == currentRequestID
                else {
                    return
                }

                if let details {
                    self.append(details)
                } else {
                    self.appendFailure(for: address)
                }
            }

            guard let self, self.requestID == currentRequestID else { return }
            self.isLoading = false
            self.lookupTask = nil
        }
    }

    func cancel() {
        lookupTask?.cancel()
        lookupTask = nil
        requestID = UUID()
        requestedAddresses = []
        isLoading = false
    }

    private func append(_ details: NetworkAddressDetails) {
        let fields = details.fields.map { field in
            BasicEntry(
                key: .Custom(name: "ip.im:\(details.address):\(field.name)"),
                name: field.name,
                value: field.value
            )
        }
        entries += [BasicEntry(sectionName: details.address)] + fields
    }

    private func appendFailure(for address: String) {
        entries += [
            BasicEntry(sectionName: address),
            BasicEntry(
                key: .Custom(name: "ip.im:\(address):status"),
                name: NSLocalizedString("IP_LOOKUP_STATUS", comment: "Status"),
                value: NSLocalizedString("IP_LOOKUP_FAILED", comment: "Unable to load")
            ),
        ]
    }

    private static func unique(_ addresses: [String]) -> [String] {
        var seen = Set<String>()
        return addresses.filter { !$0.isEmpty && seen.insert($0).inserted }
    }
}
