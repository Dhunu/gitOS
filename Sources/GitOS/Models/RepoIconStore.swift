import AppKit
import Observation

/// Finds a recognizable icon for each repository, the way project lists in other tools do:
/// the favicon of the repo's website (GitHub "homepage") when it has one, otherwise the
/// owner's GitHub avatar. Icons are cached on disk; repos without either keep their initial tile.
@MainActor
@Observable
final class RepoIconStore {
    static let shared = RepoIconStore()

    private(set) var icons: [UUID: NSImage] = [:]
    private var inFlight: Set<UUID> = []
    /// Repos that yielded nothing this launch; retried on the next launch.
    private var missing: Set<UUID> = []

    /// The repo's icon if one is known. Starts a background lookup the first time a repo is asked for.
    func icon(for repo: RepoRef, account: Account?) -> NSImage? {
        if let image = icons[repo.id] { return image }
        guard !inFlight.contains(repo.id), !missing.contains(repo.id) else { return nil }
        inFlight.insert(repo.id)
        let token = account.flatMap { Keychain.get($0.id.uuidString) }
        Task { [weak self] in
            let image = await RepoIconLoader.icon(forRepoAt: repo.url, token: token)
            guard let self else { return }
            inFlight.remove(repo.id)
            if let image { icons[repo.id] = image } else { missing.insert(repo.id) }
        }
        return nil
    }
}

enum RepoIconLoader {
    static func icon(forRepoAt repoURL: URL, token: String?) async -> NSImage? {
        guard let remote = try? await GitRepository(url: repoURL).remotes()
                .sorted(by: { ($0.name == "origin" ? 0 : 1) < ($1.name == "origin" ? 0 : 1) })
                .first(where: { $0.isGitHub && $0.owner != nil && $0.repo != nil }),
              let owner = remote.owner, let name = remote.repo else { return nil }
        let key = "github.com-\(owner)-\(name)"
        if let cached = cachedImage(key: key) { return cached }

        let meta = await metadata(owner: owner, repo: name, token: token)
        var image: NSImage?
        if let homepage = meta?.homepage, !homepage.isEmpty,
           let url = URL(string: homepage.hasPrefix("http") ? homepage : "https://\(homepage)"), url.host() != nil {
            image = await websiteIcon(for: url)
        }
        if image == nil {
            let avatar = meta?.owner?.avatarURL ?? URL(string: "https://github.com/\(owner).png?size=96")
            image = await fetchImage(avatar)
        }
        if let image { cache(image, key: key) }
        return image
    }

    // MARK: GitHub metadata

    private struct Meta: Decodable {
        struct Owner: Decodable {
            let avatarURL: URL?
            enum CodingKeys: String, CodingKey { case avatarURL = "avatar_url" }
        }
        let homepage: String?
        let owner: Owner?
    }

    private static func metadata(owner: String, repo: String, token: String?) async -> Meta? {
        guard let url = URL(string: "https://api.github.com/repos/\(owner)/\(repo)") else { return nil }
        var request = URLRequest(url: url, timeoutInterval: 10)
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        if let token { request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization") }
        guard let (data, response) = try? await URLSession.shared.data(for: request),
              (response as? HTTPURLResponse)?.statusCode == 200 else { return nil }
        return try? JSONDecoder().decode(Meta.self, from: data)
    }

    // MARK: Website favicon

    /// The site's icon: `<link rel=…icon…>` candidates from its HTML, then /favicon.ico.
    static func websiteIcon(for site: URL) async -> NSImage? {
        var candidates: [URL] = []
        var request = URLRequest(url: site, timeoutInterval: 10)
        request.setValue("text/html", forHTTPHeaderField: "Accept")
        if let (data, response) = try? await URLSession.shared.data(for: request),
           (response as? HTTPURLResponse)?.statusCode == 200 {
            let base = response.url ?? site
            let html = String(decoding: data.prefix(512 * 1024), as: UTF8.self)
            candidates = iconLinks(inHTML: html, base: base)
        }
        if let fallback = URL(string: "/favicon.ico", relativeTo: site)?.absoluteURL {
            candidates.append(fallback)
        }
        for url in candidates {
            if let image = await fetchImage(url) { return image }
        }
        return nil
    }

    /// Icon URLs declared in the page head, best first (apple-touch icons are the largest).
    static func iconLinks(inHTML html: String, base: URL) -> [URL] {
        var touch: [URL] = []
        var plain: [URL] = []
        for match in html.matches(of: /<link\b[^>]*>/.ignoresCase()) {
            let tag = match.output
            guard let rel = attribute("rel", in: tag)?.lowercased(), rel.contains("icon"),
                  !rel.contains("mask-icon"),
                  let href = attribute("href", in: tag), !href.isEmpty,
                  let url = URL(string: href, relativeTo: base)?.absoluteURL,
                  url.scheme == "https" || url.scheme == "http"
            else { continue }
            if rel.contains("apple-touch") { touch.append(url) } else { plain.append(url) }
        }
        var seen = Set<URL>()
        return (touch + plain).filter { seen.insert($0).inserted }
    }

    private static func attribute(_ name: String, in tag: Substring) -> String? {
        guard let nameRange = tag.range(of: "\(name)=", options: .caseInsensitive) else { return nil }
        var rest = tag[nameRange.upperBound...]
        guard let first = rest.first else { return nil }
        if first == "\"" || first == "'" {
            rest = rest.dropFirst()
            return rest.firstIndex(of: first).map { String(rest[..<$0]) }
        }
        return String(rest.prefix { !$0.isWhitespace && $0 != ">" })
    }

    // MARK: Fetching and caching

    private static func fetchImage(_ url: URL?) async -> NSImage? {
        guard let url else { return nil }
        let request = URLRequest(url: url, timeoutInterval: 10)
        guard let (data, response) = try? await URLSession.shared.data(for: request),
              (response as? HTTPURLResponse)?.statusCode == 200,
              (response.mimeType?.hasPrefix("text/html") ?? false) == false,
              let image = NSImage(data: data), image.size.width >= 16 else { return nil }
        return image
    }

    private static var cacheDirectory: URL {
        URL.applicationSupportDirectory.appending(path: "GitOS/RepoIcons", directoryHint: .isDirectory)
    }

    private static func cachedImage(key: String) -> NSImage? {
        NSImage(contentsOf: cacheDirectory.appending(path: "\(key).png"))
    }

    private static func cache(_ image: NSImage, key: String) {
        guard let data = pngData(image, side: 96) else { return }
        try? FileManager.default.createDirectory(at: cacheDirectory, withIntermediateDirectories: true)
        try? data.write(to: cacheDirectory.appending(path: "\(key).png"))
    }

    /// Rasterizes to a small square PNG so .ico and .svg favicons cache uniformly.
    private static func pngData(_ image: NSImage, side: CGFloat) -> Data? {
        let scale = min(side / max(image.size.width, 1), side / max(image.size.height, 1), 1)
        let size = NSSize(width: max(image.size.width * scale, 1), height: max(image.size.height * scale, 1))
        guard let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(size.width), pixelsHigh: Int(size.height),
                                         bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                                         colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)
        else { return nil }
        NSGraphicsContext.saveGraphicsState()
        defer { NSGraphicsContext.restoreGraphicsState() }
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
        image.draw(in: NSRect(origin: .zero, size: size), from: .zero, operation: .copy, fraction: 1)
        return rep.representation(using: .png, properties: [:])
    }
}
