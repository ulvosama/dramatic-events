import Foundation

/// Queries GitHub Releases to detect newer versions.
/// Repo: https://github.com/ulvosama/dramatic-events
enum UpdateChecker {

    static let owner = "ulvosama"
    static let repo  = "dramatic-events"

    struct LatestRelease {
        let version: String          // e.g. "1.0.1" (no "v" prefix)
        let downloadURL: URL?        // first .dmg asset, if any
        let zipURL: URL?             // first .zip asset — used by the silent updater
        let pageURL: URL             // GitHub release page
    }

    enum CheckResult {
        case upToDate(currentVersion: String)
        case updateAvailable(LatestRelease)
        case failed(Error)
    }

    static var currentVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0.0.0"
    }

    static func check(completion: @escaping (CheckResult) -> Void) {
        guard let url = URL(string: "https://api.github.com/repos/\(owner)/\(repo)/releases/latest") else {
            completion(.failed(URLError(.badURL)))
            return
        }
        var req = URLRequest(url: url)
        req.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        req.timeoutInterval = 10

        URLSession.shared.dataTask(with: req) { data, _, error in
            if let error = error {
                completion(.failed(error))
                return
            }
            guard let data = data else {
                completion(.failed(URLError(.badServerResponse)))
                return
            }
            do {
                let decoder = JSONDecoder()
                decoder.keyDecodingStrategy = .convertFromSnakeCase
                let resp = try decoder.decode(GHResponse.self, from: data)
                let version = resp.tagName.hasPrefix("v")
                    ? String(resp.tagName.dropFirst())
                    : resp.tagName
                let dmg = resp.assets.first { $0.name.lowercased().hasSuffix(".dmg") }
                let zip = resp.assets.first { $0.name.lowercased().hasSuffix(".zip") }
                let downloadURL = dmg.flatMap { URL(string: $0.browserDownloadUrl) }
                let zipURL = zip.flatMap { URL(string: $0.browserDownloadUrl) }
                let pageURL = URL(string: resp.htmlUrl) ?? url
                let release = LatestRelease(version: version,
                                            downloadURL: downloadURL,
                                            zipURL: zipURL,
                                            pageURL: pageURL)
                if isNewer(version, than: currentVersion) {
                    completion(.updateAvailable(release))
                } else {
                    completion(.upToDate(currentVersion: currentVersion))
                }
            } catch {
                completion(.failed(error))
            }
        }.resume()
    }

    /// Naive SemVer compare — splits on `.`, treats missing components as 0.
    static func isNewer(_ latest: String, than current: String) -> Bool {
        let l = latest.split(separator: ".").compactMap { Int($0) }
        let c = current.split(separator: ".").compactMap { Int($0) }
        for i in 0..<max(l.count, c.count) {
            let a = i < l.count ? l[i] : 0
            let b = i < c.count ? c[i] : 0
            if a > b { return true }
            if a < b { return false }
        }
        return false
    }

    private struct GHResponse: Decodable {
        let tagName: String
        let htmlUrl: String
        let assets: [Asset]
        struct Asset: Decodable {
            let name: String
            let browserDownloadUrl: String
        }
    }
}
