import Foundation

/// Where releases live. install.sh uses the same repository and command.
public enum ReleaseInfo {
    public static let repository = "ahmetkorkmaz3/EnvSwitcher"
    public static let latestReleaseAPI = URL(string: "https://api.github.com/repos/\(repository)/releases/latest")!
    public static let installCommand = "curl -fsSL https://raw.githubusercontent.com/\(repository)/main/install.sh | sh"
}

public protocol HTTPClient: Sendable {
    /// Returns the body and the HTTP status code.
    func get(_ url: URL) async throws -> (Data, Int)
}

public struct URLSessionHTTPClient: HTTPClient {
    public init() {}

    public func get(_ url: URL) async throws -> (Data, Int) {
        var request = URLRequest(url: url, timeoutInterval: 15)
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.setValue("EnvSwitcher", forHTTPHeaderField: "User-Agent")
        let (data, response) = try await URLSession.shared.data(for: request)
        return (data, (response as? HTTPURLResponse)?.statusCode ?? 0)
    }
}

public struct AvailableUpdate: Equatable, Sendable, Codable {
    public let version: SemanticVersion
    /// The release page on GitHub.
    public let url: URL

    public init(version: SemanticVersion, url: URL) {
        self.version = version
        self.url = url
    }
}

public enum UpdateResult: Equatable, Sendable {
    case upToDate
    case available(AvailableUpdate)
}

public enum UpdateError: Error, Equatable {
    case badStatus(Int)
    case invalidResponse
}

/// Reads the latest GitHub release (spec 2026-10-08, section 7.1).
public struct UpdateChecker: Sendable {
    let client: any HTTPClient
    let url: URL

    public init(client: any HTTPClient = URLSessionHTTPClient(), url: URL = ReleaseInfo.latestReleaseAPI) {
        self.client = client
        self.url = url
    }

    private struct Release: Decodable {
        let tagName: String
        let htmlURL: URL

        enum CodingKeys: String, CodingKey {
            case tagName = "tag_name"
            case htmlURL = "html_url"
        }
    }

    public func check(current: SemanticVersion) async throws -> UpdateResult {
        let (data, status) = try await client.get(url)
        guard status == 200 else { throw UpdateError.badStatus(status) }
        guard let release = try? JSONDecoder().decode(Release.self, from: data),
              let latest = SemanticVersion(release.tagName)
        else { throw UpdateError.invalidResponse }
        return latest > current ? .available(AvailableUpdate(version: latest, url: release.htmlURL)) : .upToDate
    }
}

/// The last check and the update it found. It lives in UserDefaults, so the menu still shows the update after a restart.
public struct StoredUpdate: Codable, Equatable, Sendable {
    public var lastCheck: Date?
    public var found: AvailableUpdate?

    public init(lastCheck: Date? = nil, found: AvailableUpdate? = nil) {
        self.lastCheck = lastCheck
        self.found = found
    }

    /// Returns the stored update only while it is newer than the running version.
    public func available(current: SemanticVersion) -> AvailableUpdate? {
        guard let found, found.version > current else { return nil }
        return found
    }
}
