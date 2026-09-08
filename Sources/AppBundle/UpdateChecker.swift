import AppKit
import Combine
import Common
import Foundation

struct SmoothRelease: Equatable, Sendable {
    let version: String
    let title: String
    let pageUrl: URL
    let publishedAt: Date?
}

enum UpdateCheckStatus: Equatable, Sendable {
    case idle
    case checking
    case current(SmoothRelease)
    case available(SmoothRelease)
    case failed(String)
}

private struct GitHubReleaseResponse: Decodable {
    let tagName: String
    let name: String?
    let htmlUrl: URL
    let publishedAt: Date?

    private enum CodingKeys: String, CodingKey {
        case tagName = "tag_name"
        case name
        case htmlUrl = "html_url"
        case publishedAt = "published_at"
    }
}

@MainActor
final class UpdateChecker: ObservableObject {
    static let shared = UpdateChecker()

    private static let automaticKey = "AeroSpaceSmooth.automatically-check-for-updates"
    private static let lastCheckKey = "AeroSpaceSmooth.last-update-check"
    private static let releasesApi = URL(string: "https://api.github.com/repos/cassel/TileSail/releases/latest").orDie()
    private let defaults: UserDefaults
    private let session: URLSession

    @Published private(set) var automaticallyChecks: Bool
    @Published private(set) var status: UpdateCheckStatus = .idle

    init(defaults: UserDefaults = .standard, session: URLSession = .shared) {
        self.defaults = defaults
        self.session = session
        automaticallyChecks = defaults.object(forKey: Self.automaticKey) as? Bool ?? true
    }

    func setAutomaticallyChecks(_ enabled: Bool) {
        automaticallyChecks = enabled
        defaults.set(enabled, forKey: Self.automaticKey)
    }

    func checkAutomaticallyIfNeeded() async {
        guard automaticallyChecks else { return }
        let lastCheck = defaults.object(forKey: Self.lastCheckKey) as? Date ?? .distantPast
        guard Date.now.timeIntervalSince(lastCheck) >= 24 * 60 * 60 else { return }
        await check()
    }

    func check() async {
        guard status != .checking else { return }
        status = .checking
        do {
            var request = URLRequest(url: Self.releasesApi)
            request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
            request.setValue("TileSail/\(aeroSpaceAppVersion)", forHTTPHeaderField: "User-Agent")
            let (data, response) = try await session.data(for: request)
            guard let httpResponse = response as? HTTPURLResponse else {
                throw UpdateCheckerError.invalidResponse
            }
            guard httpResponse.statusCode == 200 else {
                throw httpResponse.statusCode == 404 ? UpdateCheckerError.noPublishedReleases : .httpStatus(httpResponse.statusCode)
            }
            let release = try Self.decodeRelease(data)
            defaults.set(Date.now, forKey: Self.lastCheckKey)
            status = Self.isVersion(release.version, newerThan: aeroSpaceAppVersion)
                ? .available(release)
                : .current(release)
        } catch {
            status = .failed(error.localizedDescription)
        }
    }

    nonisolated static func decodeRelease(_ data: Data) throws -> SmoothRelease {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let response = try decoder.decode(GitHubReleaseResponse.self, from: data)
        return SmoothRelease(
            version: response.tagName,
            title: response.name ?? response.tagName,
            pageUrl: response.htmlUrl,
            publishedAt: response.publishedAt,
        )
    }

    nonisolated static func isVersion(_ candidate: String, newerThan current: String) -> Bool {
        let candidateParts = numericVersionParts(candidate)
        let currentParts = numericVersionParts(current)
        for index in 0 ..< max(candidateParts.count, currentParts.count) {
            let lhs = candidateParts.getOrNil(atIndex: index) ?? 0
            let rhs = currentParts.getOrNil(atIndex: index) ?? 0
            if lhs != rhs { return lhs > rhs }
        }
        return false
    }
}

private enum UpdateCheckerError: LocalizedError {
    case invalidResponse
    case noPublishedReleases
    case httpStatus(Int)

    var errorDescription: String? {
        switch self {
            case .invalidResponse: "The update service returned an invalid response."
            case .noPublishedReleases: "No public TileSail releases are available yet."
            case .httpStatus(let status): "The update service returned HTTP \(status)."
        }
    }
}

private func numericVersionParts(_ version: String) -> [Int] {
    version
        .trimmingCharacters(in: CharacterSet(charactersIn: "vV"))
        .split(whereSeparator: { !$0.isNumber })
        .prefix(4)
        .compactMap { Int($0) }
}
