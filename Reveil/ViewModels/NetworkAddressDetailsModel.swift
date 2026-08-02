//
//  NetworkAddressDetailsModel.swift
//  Reveil
//
//  Resolves the public addresses shown on the dashboard through ip.im. Results are cached by IP;
//  misses are requested sequentially to preserve the card's order and each result is published
//  immediately.
//

import Combine
import Foundation

private struct NetworkAddressDetails: Codable {
    struct Field: Codable {
        let name: String
        let value: String
    }

    let address: String
    let fields: [Field]
}

private enum NetworkAddressDetailsProvider {
    private static let baseURL = URL(string: "https://ip.im")!
    private static let timeout: TimeInterval = 10

    private static let fieldNames = [
        "hostname": "Hostname",
        "countrycode": "CountryCode",
        "country": "Country",
        "province": "Province",
        "city": "City",
        "region": "Region",
        "districts": "Districts",
        "loc": "Loc",
        "org": "Org",
        "isp": "Isp",
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
        var responseAddress: String?
        var fields = [NetworkAddressDetails.Field]()
        var seenKeys = Set<String>()

        for rawLine in body.split(whereSeparator: { $0.isNewline }) {
            let line = String(rawLine).trimmingCharacters(in: .whitespacesAndNewlines)
            guard let separator = line.firstIndex(of: ":") else { continue }

            let key = String(line[..<separator])
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .lowercased()
            let value = String(line[line.index(after: separator)...])
                .trimmingCharacters(in: .whitespacesAndNewlines)

            guard !value.isEmpty else { continue }
            if key == "ip" {
                responseAddress = value
            } else if let name = fieldNames[key], seenKeys.insert(key).inserted {
                fields.append(NetworkAddressDetails.Field(name: name, value: value))
            }
        }

        guard responseAddress == expectedAddress, !fields.isEmpty else { return nil }

        return NetworkAddressDetails(address: expectedAddress, fields: fields)
    }
}

private enum NetworkAddressDetailsCache {
    private struct Record: Codable {
        let details: NetworkAddressDetails
        let storedAt: Date
    }

    private static let defaultsKey = "NetworkAddressDetailsCache.v1"
    private static let maximumAge: TimeInterval = 3 * 24 * 60 * 60

    static func details(for address: String, now: Date = Date()) -> NetworkAddressDetails? {
        let records = validRecords(now: now)
        guard let record = records[address],
              record.details.address == address,
              !record.details.fields.isEmpty
        else {
            return nil
        }
        return record.details
    }

    static func store(_ details: NetworkAddressDetails, now: Date = Date()) {
        var records = validRecords(now: now)
        records[details.address] = Record(details: details, storedAt: now)
        write(records)
    }

    private static func validRecords(now: Date) -> [String: Record] {
        guard let data = UserDefaults.standard.data(forKey: defaultsKey),
              let records = try? JSONDecoder().decode([String: Record].self, from: data)
        else {
            return [:]
        }

        return records.filter { now.timeIntervalSince($0.value.storedAt) < maximumAge }
    }

    private static func write(_ records: [String: Record]) {
        guard let data = try? JSONEncoder().encode(records) else { return }
        UserDefaults.standard.set(data, forKey: defaultsKey)
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

                if let cachedDetails = NetworkAddressDetailsCache.details(for: address) {
                    guard let self,
                          !Task.isCancelled,
                          self.requestID == currentRequestID
                    else {
                        return
                    }
                    self.append(cachedDetails)
                    continue
                }

                let details = await NetworkAddressDetailsProvider.details(for: address)
                guard let self,
                      !Task.isCancelled,
                      self.requestID == currentRequestID
                else {
                    return
                }

                if let details {
                    NetworkAddressDetailsCache.store(details)
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
