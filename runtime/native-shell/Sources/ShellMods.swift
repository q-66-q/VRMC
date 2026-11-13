import SwiftUI
import CryptoKit
import Security
import UniformTypeIdentifiers

// VRMC mod browser (release 1.4): find, install, update and manage Fabric mods for the VRMC instance
// without leaving the headset. Modrinth uses its open API; CurseForge's official API requires a free
// personal API key (console.curseforge.com), stored in the Keychain on this device only.
//
// Every download is verified against the hash the site publishes before it is moved into
// instances/default/mods. Required dependencies are installed with the mod. The mods VRMC itself
// needs (VRMC provider, Vivecraft, Fabric API) are protected from being disabled or deleted here.
// Changes take effect the next time the game starts.

enum ModSource: String, Codable, CaseIterable, Identifiable, Sendable {
    case modrinth
    case curseforge

    var id: String { rawValue }
    var title: String {
        switch self {
        case .modrinth: return "Modrinth"
        case .curseforge: return "CurseForge"
        }
    }
}

enum ModSort: String, CaseIterable, Identifiable, Sendable {
    case relevance, downloads, updated

    var id: String { rawValue }
    var title: String {
        switch self {
        case .relevance: return "Relevance"
        case .downloads: return "Downloads"
        case .updated: return "Recently updated"
        }
    }
}

struct ModHit: Identifiable, Hashable, Sendable {
    let source: ModSource
    let projectId: String
    let slug: String
    let title: String
    let author: String
    let summary: String
    let downloads: Int
    let iconURL: URL?
    let pageURL: URL?
    let categories: [String]

    var id: String { source.rawValue + ":" + projectId }

    /// Mods that replace or hook the renderer. VRMC renders through Vivecraft into the headset's
    /// compositor; these are likely to break that path, so the UI says so before installing.
    var renderingWarning: String? {
        let s = slug.lowercased()
        let risky = ["sodium", "iris", "embeddium", "rubidium", "optifabric", "canvas", "nvidium",
                     "immediatelyfast", "distanthorizons", "distant-horizons", "bobby", "c2me-fabric",
                     "exordium", "entityculling", "more-culling", "moreculling"]
        if risky.contains(where: { s == $0 || s.hasPrefix($0 + "-") }) {
            return "Changes how the game renders. VRMC renders through Vivecraft on Vision Pro, so this mod may not work or may crash the game."
        }
        return nil
    }
}

struct ModFile: Sendable {
    let source: ModSource
    let projectId: String
    let versionId: String
    let versionName: String
    let fileName: String
    let url: URL?
    let sha1: String?
    let sha512: String?
    let size: Int
    let requiredDependencies: [String]
    let pageURL: URL?
}

struct InstalledMod: Codable, Identifiable, Hashable, Sendable {
    var fileName: String
    var source: ModSource?
    var projectId: String?
    var versionId: String?
    var versionName: String?
    var title: String?
    var iconURL: String?

    var id: String { baseFileName }
    var enabled: Bool { !fileName.hasSuffix(".disabled") }
    var baseFileName: String {
        fileName.hasSuffix(".disabled") ? String(fileName.dropLast(".disabled".count)) : fileName
    }
    var displayName: String { title ?? baseFileName }

    /// Mods VRMC needs to run in VR. They are managed by setup, never disabled/deleted here.
    var isCore: Bool {
        let n = baseFileName.lowercased()
        return n.hasPrefix("vrmc-provider") || n.hasPrefix("vivecraft") || n.hasPrefix("fabric-api")
    }
}

struct ModError: Error, Sendable {
    let message: String
}

// MARK: - Keychain (CurseForge API key)

enum ModKeychain {
    nonisolated private static let service = "dev.vrmc.curseforge"
    nonisolated private static let account = "api-key"

    nonisolated static func load() -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var item: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess,
              let data = item as? Data, let key = String(data: data, encoding: .utf8),
              !key.isEmpty else { return nil }
        return key
    }

    @discardableResult
    nonisolated static func save(_ key: String?) -> Bool {
        let base: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
        SecItemDelete(base as CFDictionary)
        guard let key, !key.isEmpty, let data = key.data(using: .utf8) else { return true }
        var add = base
        add[kSecValueData as String] = data
        add[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        return SecItemAdd(add as CFDictionary, nil) == errSecSuccess
    }
}

// MARK: - HTTP

enum ModHTTP {
    /// Generic client name; no user or device details are sent.
    nonisolated static let userAgent = "VRMC-visionOS/1.4 (Fabric mod browser)"

    nonisolated static func get(_ url: URL, headers: [String: String] = [:]) async throws -> Data {
        var request = URLRequest(url: url)
        request.timeoutInterval = 30
        request.setValue(userAgent, forHTTPHeaderField: "User-Agent")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        for (k, v) in headers { request.setValue(v, forHTTPHeaderField: k) }
        return try await send(request)
    }

    nonisolated static func postJSON(_ url: URL, body: Data) async throws -> Data {
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = 30
        request.httpBody = body
        request.setValue(userAgent, forHTTPHeaderField: "User-Agent")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        return try await send(request)
    }

    nonisolated private static func send(_ request: URLRequest) async throws -> Data {
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw ModError(message: "No response") }
        switch http.statusCode {
        case 200..<300: return data
        case 401, 403: throw ModError(message: "The server refused the request (HTTP \(http.statusCode)). Check the API key.")
        case 404: throw ModError(message: "Not found (HTTP 404).")
        case 429: throw ModError(message: "Too many requests. Wait a moment and try again.")
        default: throw ModError(message: "Server error (HTTP \(http.statusCode)).")
        }
    }

    nonisolated static func query(_ base: String, _ items: [(String, String)]) -> URL? {
        var components = URLComponents(string: base)
        components?.queryItems = items.map { URLQueryItem(name: $0.0, value: $0.1) }
        return components?.url
    }
}

// MARK: - Modrinth

enum ModrinthAPI {
    nonisolated static let base = "https://api.modrinth.com/v2"
    /// Fabric API's Modrinth project; installed by setup, so never re-installed as a dependency.
    nonisolated static let fabricAPIProject = "P7dR8mSH"

    private struct SearchResponse: Decodable {
        struct Hit: Decodable {
            let project_id: String
            let slug: String?
            let title: String
            let description: String?
            let author: String?
            let downloads: Int?
            let icon_url: String?
            let display_categories: [String]?
        }
        let hits: [Hit]
    }

    private struct Version: Decodable {
        struct File: Decodable {
            struct Hashes: Decodable { let sha1: String?; let sha512: String? }
            let url: String
            let filename: String
            let primary: Bool?
            let size: Int?
            let hashes: Hashes?
        }
        struct Dependency: Decodable {
            let project_id: String?
            let dependency_type: String?
        }
        let id: String
        let project_id: String
        let name: String?
        let version_number: String?
        let files: [File]
        let dependencies: [Dependency]?
    }

    private struct Project: Decodable {
        let id: String
        let slug: String?
        let title: String
        let description: String?
        let icon_url: String?
        let downloads: Int?
        let categories: [String]?
    }

    nonisolated static func search(query: String, sort: ModSort, gameVersion: String) async throws -> [ModHit] {
        let index: String
        switch sort {
        case .relevance: index = query.isEmpty ? "downloads" : "relevance"
        case .downloads: index = "downloads"
        case .updated: index = "updated"
        }
        let facets = "[[\"project_type:mod\"],[\"categories:fabric\"],[\"versions:\(gameVersion)\"]]"
        guard let url = ModHTTP.query(base + "/search", [
            ("query", query), ("facets", facets), ("index", index), ("limit", "40"),
        ]) else { throw ModError(message: "Bad search") }
        let decoded = try JSONDecoder().decode(SearchResponse.self, from: try await ModHTTP.get(url))
        return decoded.hits.map { h in
            ModHit(source: .modrinth, projectId: h.project_id, slug: h.slug ?? h.project_id, title: h.title,
                   author: h.author ?? "", summary: h.description ?? "", downloads: h.downloads ?? 0,
                   iconURL: h.icon_url.flatMap(URL.init(string:)),
                   pageURL: URL(string: "https://modrinth.com/mod/\(h.slug ?? h.project_id)"),
                   categories: h.display_categories ?? [])
        }
    }

    nonisolated static func project(_ id: String) async throws -> ModHit {
        guard let url = URL(string: base + "/project/" + id) else { throw ModError(message: "Bad project") }
        let p = try JSONDecoder().decode(Project.self, from: try await ModHTTP.get(url))
        return ModHit(source: .modrinth, projectId: p.id, slug: p.slug ?? p.id, title: p.title, author: "",
                      summary: p.description ?? "", downloads: p.downloads ?? 0,
                      iconURL: p.icon_url.flatMap(URL.init(string:)),
                      pageURL: URL(string: "https://modrinth.com/mod/\(p.slug ?? p.id)"),
                      categories: p.categories ?? [])
    }

    /// Newest version of a project for this loader + game version (the API returns newest first).
    nonisolated static func latestFile(projectId: String, gameVersion: String) async throws -> ModFile? {
        guard let url = ModHTTP.query(base + "/project/\(projectId)/version", [
            ("loaders", "[\"fabric\"]"), ("game_versions", "[\"\(gameVersion)\"]"),
        ]) else { throw ModError(message: "Bad project") }
        let versions = try JSONDecoder().decode([Version].self, from: try await ModHTTP.get(url))
        return versions.first.flatMap(file(from:))
    }

    /// Latest compatible versions for installed jars, keyed by the jar's SHA-1.
    nonisolated static func updates(sha1s: [String], gameVersion: String) async throws -> [String: ModFile] {
        guard !sha1s.isEmpty, let url = URL(string: base + "/version_files/update") else { return [:] }
        let body = try JSONSerialization.data(withJSONObject: [
            "hashes": sha1s, "algorithm": "sha1", "loaders": ["fabric"], "game_versions": [gameVersion],
        ])
        let decoded = try JSONDecoder().decode([String: Version].self,
                                               from: try await ModHTTP.postJSON(url, body: body))
        var out: [String: ModFile] = [:]
        for (hash, version) in decoded {
            if let f = file(from: version) { out[hash] = f }
        }
        return out
    }

    nonisolated private static func file(from v: Version) -> ModFile? {
        guard let f = v.files.first(where: { $0.primary == true }) ?? v.files.first else { return nil }
        let deps = (v.dependencies ?? []).filter { $0.dependency_type == "required" }.compactMap { $0.project_id }
        return ModFile(source: .modrinth, projectId: v.project_id, versionId: v.id,
                       versionName: v.version_number ?? v.name ?? v.id, fileName: f.filename,
                       url: URL(string: f.url), sha1: f.hashes?.sha1, sha512: f.hashes?.sha512,
                       size: f.size ?? 0, requiredDependencies: deps, pageURL: nil)
    }
}

// MARK: - CurseForge

enum CurseForgeAPI {
    nonisolated static let base = "https://api.curseforge.com/v1"
    nonisolated static let minecraftGameId = "432"
    nonisolated static let modsClassId = "6"
    nonisolated static let fabricLoaderType = "4"
    nonisolated static let fabricAPIModId = "306612"

    private struct SearchResponse: Decodable {
        struct Mod: Decodable {
            struct Logo: Decodable { let thumbnailUrl: String? }
            struct Author: Decodable { let name: String }
            struct Links: Decodable { let websiteUrl: String? }
            struct Category: Decodable { let name: String }
            let id: Int
            let name: String
            let slug: String?
            let summary: String?
            let downloadCount: Double?
            let logo: Logo?
            let authors: [Author]?
            let links: Links?
            let categories: [Category]?
        }
        let data: [Mod]
    }

    private struct ModResponse: Decodable {
        let data: SearchResponse.Mod
    }

    private struct FilesResponse: Decodable {
        struct File: Decodable {
            struct Hash: Decodable { let value: String; let algo: Int }
            struct Dependency: Decodable { let modId: Int; let relationType: Int }
            let id: Int
            let modId: Int
            let displayName: String?
            let fileName: String
            let downloadUrl: String?
            let fileLength: Int?
            let hashes: [Hash]?
            let dependencies: [Dependency]?
            let gameVersions: [String]?
        }
        let data: [File]
    }

    nonisolated private static func headers(_ key: String) -> [String: String] { ["x-api-key": key] }

    nonisolated static func search(query: String, sort: ModSort, gameVersion: String, key: String) async throws -> [ModHit] {
        // sortField: 1 featured, 2 popularity, 3 last updated, 6 total downloads
        let sortField: String
        switch sort {
        case .relevance: sortField = query.isEmpty ? "2" : "1"
        case .downloads: sortField = "6"
        case .updated: sortField = "3"
        }
        guard let url = ModHTTP.query(base + "/mods/search", [
            ("gameId", minecraftGameId), ("classId", modsClassId), ("searchFilter", query),
            ("gameVersion", gameVersion), ("modLoaderType", fabricLoaderType),
            ("sortField", sortField), ("sortOrder", "desc"), ("pageSize", "40"),
        ]) else { throw ModError(message: "Bad search") }
        let decoded = try JSONDecoder().decode(SearchResponse.self,
                                               from: try await ModHTTP.get(url, headers: headers(key)))
        return decoded.data.map(hit(from:))
    }

    nonisolated private static func hit(from m: SearchResponse.Mod) -> ModHit {
        ModHit(source: .curseforge, projectId: String(m.id), slug: m.slug ?? String(m.id), title: m.name,
               author: m.authors?.first?.name ?? "", summary: m.summary ?? "",
               downloads: Int(m.downloadCount ?? 0), iconURL: m.logo?.thumbnailUrl.flatMap(URL.init(string:)),
               pageURL: m.links?.websiteUrl.flatMap(URL.init(string:)),
               categories: (m.categories ?? []).map(\.name))
    }

    nonisolated static func project(_ id: String, key: String) async throws -> ModHit {
        guard let url = URL(string: base + "/mods/" + id) else { throw ModError(message: "Bad mod") }
        let decoded = try JSONDecoder().decode(ModResponse.self,
                                               from: try await ModHTTP.get(url, headers: headers(key)))
        return hit(from: decoded.data)
    }

    nonisolated static func latestFile(modId: String, gameVersion: String, key: String,
                                       pageURL: URL?) async throws -> ModFile? {
        guard let url = ModHTTP.query(base + "/mods/\(modId)/files", [
            ("gameVersion", gameVersion), ("modLoaderType", fabricLoaderType), ("pageSize", "20"),
        ]) else { throw ModError(message: "Bad mod") }
        let decoded = try JSONDecoder().decode(FilesResponse.self,
                                               from: try await ModHTTP.get(url, headers: headers(key)))
        // Newest first; keep only files that name this game version.
        let files = decoded.data.filter { ($0.gameVersions ?? []).contains(gameVersion) }.sorted { $0.id > $1.id }
        guard let f = files.first else { return nil }
        let deps = (f.dependencies ?? []).filter { $0.relationType == 3 }.map { String($0.modId) }
        return ModFile(source: .curseforge, projectId: String(f.modId), versionId: String(f.id),
                       versionName: f.displayName ?? f.fileName, fileName: f.fileName,
                       url: f.downloadUrl.flatMap(URL.init(string:)),
                       sha1: f.hashes?.first(where: { $0.algo == 1 })?.value, sha512: nil,
                       size: f.fileLength ?? 0, requiredDependencies: deps, pageURL: pageURL)
    }
}

// MARK: - Store

@MainActor
@Observable
final class ModStore {
    static let shared = ModStore()

    var source: ModSource = .modrinth
    var sort: ModSort = .relevance
    var query = ""
    private(set) var results: [ModHit] = []
    private(set) var searching = false
    private(set) var message = ""
    private(set) var installed: [InstalledMod] = []
    private(set) var installing: Set<String> = []
    /// Available updates keyed by installed base file name.
    private(set) var updates: [String: ModFile] = [:]
    private(set) var checkingUpdates = false
    private(set) var curseForgeKeySet = ModKeychain.load() != nil
    /// Set after any change to the mods folder; the game picks it up on its next start.
    private(set) var changedSinceLaunch = false
    private var lastSearchKey = ""

    nonisolated static let gameVersion = SetupManager.minecraftVersion

    private init() {}

    // MARK: Paths and index

    nonisolated static func modsDirectory() -> URL { SetupManager.modsDirectory() }

    nonisolated static func indexURL() -> URL {
        SetupManager.gameDirectory().appendingPathComponent("vrmc-mods.json")
    }

    nonisolated private static func loadIndex() -> [String: InstalledMod] {
        guard let data = try? Data(contentsOf: indexURL()),
              let list = try? JSONDecoder().decode([InstalledMod].self, from: data) else { return [:] }
        var out: [String: InstalledMod] = [:]
        for m in list { out[m.baseFileName] = m }
        return out
    }

    nonisolated private static func saveIndex(_ index: [String: InstalledMod]) {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        if let data = try? encoder.encode(Array(index.values).sorted { $0.baseFileName < $1.baseFileName }) {
            try? data.write(to: indexURL(), options: .atomic)
        }
    }

    func refreshInstalled() {
        let dir = Self.modsDirectory()
        let index = Self.loadIndex()
        let names = (try? FileManager.default.contentsOfDirectory(atPath: dir.path)) ?? []
        var list: [InstalledMod] = []
        for name in names where name.hasSuffix(".jar") || name.hasSuffix(".jar.disabled") {
            if name.hasPrefix(".") { continue }
            var entry = InstalledMod(fileName: name)
            if let known = index[entry.baseFileName] {
                entry = known
                entry.fileName = name
            }
            list.append(entry)
        }
        installed = list.sorted {
            if $0.isCore != $1.isCore { return $0.isCore }
            return $0.displayName.localizedCaseInsensitiveCompare($1.displayName) == .orderedAscending
        }
    }

    func isInstalled(_ hit: ModHit) -> Bool {
        installed.contains { $0.source == hit.source && $0.projectId == hit.projectId }
    }

    // MARK: Search

    func setCurseForgeKey(_ key: String?) {
        let trimmed = key?.trimmingCharacters(in: .whitespacesAndNewlines)
        ModKeychain.save(trimmed)
        curseForgeKeySet = ModKeychain.load() != nil
        message = curseForgeKeySet ? "CurseForge key saved on this device." : "CurseForge key removed."
        lastSearchKey = ""
        if source == .curseforge { Task { await search() } }
    }

    func search(force: Bool = false) async {
        let key = "\(source.rawValue)|\(sort.rawValue)|\(query)"
        if !force && key == lastSearchKey && !results.isEmpty { return }
        lastSearchKey = key
        searching = true
        message = ""
        defer { searching = false }
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines)
        do {
            switch source {
            case .modrinth:
                results = try await ModrinthAPI.search(query: q, sort: sort, gameVersion: Self.gameVersion)
            case .curseforge:
                guard let apiKey = ModKeychain.load() else {
                    results = []
                    return
                }
                results = try await CurseForgeAPI.search(query: q, sort: sort, gameVersion: Self.gameVersion,
                                                         key: apiKey)
            }
            if results.isEmpty {
                message = "No Fabric mods for Minecraft \(Self.gameVersion) match \"\(q)\"."
            }
        } catch {
            results = []
            message = Self.describe(error)
            lastSearchKey = ""
        }
    }

    // MARK: Install

    func install(_ hit: ModHit) async {
        guard !installing.contains(hit.id) else { return }
        installing.insert(hit.id)
        defer { installing.remove(hit.id) }
        message = ""
        var visited: Set<String> = []
        do {
            let names = try await installProject(source: hit.source, projectId: hit.projectId, hit: hit,
                                                 depth: 0, visited: &visited)
            message = names.count > 1
                ? "Installed \(hit.title) with \(names.count - 1) required mod\(names.count == 2 ? "" : "s")."
                : "Installed \(hit.title)."
            changedSinceLaunch = true
            shellLog("mods: installed \(names.joined(separator: ", ")) from \(hit.source.title)")
        } catch {
            message = "\(hit.title): \(Self.describe(error))"
            shellLog("mods: install of \(hit.title) failed: \(Self.describe(error))")
        }
        refreshInstalled()
    }

    /// Install a project and (recursively, max depth 3) its required dependencies.
    private func installProject(source: ModSource, projectId: String, hit: ModHit?, depth: Int,
                                visited: inout Set<String>) async throws -> [String] {
        let key = source.rawValue + ":" + projectId
        if visited.contains(key) || depth > 3 { return [] }
        visited.insert(key)
        if depth > 0 && dependencyAlreadyPresent(source: source, projectId: projectId) { return [] }
        let gameVersion = Self.gameVersion
        let info: ModHit?
        let file: ModFile?
        switch source {
        case .modrinth:
            info = try await (hit != nil ? hit : ModrinthAPI.project(projectId))
            file = try await ModrinthAPI.latestFile(projectId: projectId, gameVersion: gameVersion)
        case .curseforge:
            guard let apiKey = ModKeychain.load() else {
                throw ModError(message: "Add a CurseForge API key first.")
            }
            info = try await (hit != nil ? hit : CurseForgeAPI.project(projectId, key: apiKey))
            file = try await CurseForgeAPI.latestFile(modId: projectId, gameVersion: gameVersion, key: apiKey,
                                                      pageURL: info?.pageURL)
        }
        guard let file else {
            throw ModError(message: "No Fabric build for Minecraft \(gameVersion).")
        }
        guard let url = file.url else {
            throw ModError(message: "The author only allows downloads from the CurseForge website. Open its page to download it in a browser.")
        }
        var installedNames: [String] = []
        for dep in file.requiredDependencies {
            installedNames += try await installProject(source: source, projectId: dep, hit: nil,
                                                       depth: depth + 1, visited: &visited)
        }
        let staged = try await Self.download(url, expectedSHA1: file.sha1, expectedSHA512: file.sha512)
        try Self.place(staged, as: file.fileName, replacing: nil)
        var index = Self.loadIndex()
        index[file.fileName] = InstalledMod(fileName: file.fileName, source: source, projectId: projectId,
                                            versionId: file.versionId, versionName: file.versionName,
                                            title: info?.title, iconURL: info?.iconURL?.absoluteString)
        Self.saveIndex(index)
        installedNames.append(info?.title ?? file.fileName)
        return installedNames
    }

    private func dependencyAlreadyPresent(source: ModSource, projectId: String) -> Bool {
        let fabricAPI = (source == .modrinth && projectId == ModrinthAPI.fabricAPIProject)
            || (source == .curseforge && projectId == CurseForgeAPI.fabricAPIModId)
        if fabricAPI && installed.contains(where: { $0.baseFileName.lowercased().hasPrefix("fabric-api") }) {
            return true
        }
        return installed.contains { $0.source == source && $0.projectId == projectId }
    }

    nonisolated private static func download(_ url: URL, expectedSHA1: String?,
                                             expectedSHA512: String?) async throws -> URL {
        guard url.scheme == "https" else { throw ModError(message: "Refusing a non-HTTPS download.") }
        var request = URLRequest(url: url)
        request.timeoutInterval = 120
        request.setValue(ModHTTP.userAgent, forHTTPHeaderField: "User-Agent")
        let (temp, response) = try await URLSession.shared.download(for: request)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw ModError(message: "Download failed.")
        }
        let staged = modsDirectory().appendingPathComponent(".vrmc-download-\(UUID().uuidString).tmp")
        try FileManager.default.createDirectory(at: modsDirectory(), withIntermediateDirectories: true)
        try FileManager.default.moveItem(at: temp, to: staged)
        let data = try Data(contentsOf: staged, options: .mappedIfSafe)
        if let expectedSHA512 {
            let got = SHA512.hash(data: data).map { String(format: "%02x", $0) }.joined()
            guard got.lowercased() == expectedSHA512.lowercased() else {
                try? FileManager.default.removeItem(at: staged)
                throw ModError(message: "The download did not match its published SHA-512; nothing was installed.")
            }
        } else if let expectedSHA1 {
            let got = Insecure.SHA1.hash(data: data).map { String(format: "%02x", $0) }.joined()
            guard got.lowercased() == expectedSHA1.lowercased() else {
                try? FileManager.default.removeItem(at: staged)
                throw ModError(message: "The download did not match its published hash; nothing was installed.")
            }
        } else {
            try? FileManager.default.removeItem(at: staged)
            throw ModError(message: "The site published no hash for this file, so it cannot be verified.")
        }
        // A Fabric mod is a zip with fabric.mod.json.
        guard let entries = SetupManager.zipEntryNames(of: staged), entries.contains("fabric.mod.json") else {
            try? FileManager.default.removeItem(at: staged)
            throw ModError(message: "This file is not a Fabric mod.")
        }
        return staged
    }

    nonisolated private static func place(_ staged: URL, as fileName: String, replacing old: String?) throws {
        let safe = (fileName as NSString).lastPathComponent
        guard safe.hasSuffix(".jar"), !safe.hasPrefix(".") else {
            try? FileManager.default.removeItem(at: staged)
            throw ModError(message: "Unexpected file name.")
        }
        let fm = FileManager.default
        let dir = modsDirectory()
        if let old, old != safe {
            try? fm.removeItem(at: dir.appendingPathComponent(old))
            try? fm.removeItem(at: dir.appendingPathComponent(old + ".disabled"))
        }
        let destination = dir.appendingPathComponent(safe)
        try? fm.removeItem(at: dir.appendingPathComponent(safe + ".disabled"))
        if fm.fileExists(atPath: destination.path) {
            _ = try fm.replaceItemAt(destination, withItemAt: staged)
        } else {
            try fm.moveItem(at: staged, to: destination)
        }
    }

    // MARK: Manage

    func setEnabled(_ mod: InstalledMod, _ enabled: Bool) {
        guard !mod.isCore, mod.enabled != enabled else { return }
        let dir = Self.modsDirectory()
        let from = dir.appendingPathComponent(mod.fileName)
        let to = dir.appendingPathComponent(enabled ? mod.baseFileName : mod.baseFileName + ".disabled")
        do {
            try FileManager.default.moveItem(at: from, to: to)
            changedSinceLaunch = true
            shellLog("mods: \(enabled ? "enabled" : "disabled") \(mod.baseFileName)")
        } catch {
            message = "Could not \(enabled ? "enable" : "disable") \(mod.displayName): \(error.localizedDescription)"
        }
        refreshInstalled()
    }

    func delete(_ mod: InstalledMod) {
        guard !mod.isCore else { return }
        do {
            try FileManager.default.removeItem(at: Self.modsDirectory().appendingPathComponent(mod.fileName))
            var index = Self.loadIndex()
            index.removeValue(forKey: mod.baseFileName)
            Self.saveIndex(index)
            changedSinceLaunch = true
            message = "Removed \(mod.displayName)."
            shellLog("mods: removed \(mod.baseFileName)")
        } catch {
            message = "Could not remove \(mod.displayName): \(error.localizedDescription)"
        }
        refreshInstalled()
    }

    /// Modrinth recognises any jar it hosts by hash, also ones installed by hand.
    func checkUpdates() async {
        checkingUpdates = true
        defer { checkingUpdates = false }
        let dir = Self.modsDirectory()
        var byHash: [String: InstalledMod] = [:]
        for mod in installed where !mod.isCore && mod.enabled {
            if let data = try? Data(contentsOf: dir.appendingPathComponent(mod.fileName), options: .mappedIfSafe) {
                byHash[Insecure.SHA1.hash(data: data).map { String(format: "%02x", $0) }.joined()] = mod
            }
        }
        do {
            let latest = try await ModrinthAPI.updates(sha1s: Array(byHash.keys), gameVersion: Self.gameVersion)
            var found: [String: ModFile] = [:]
            for (hash, file) in latest {
                guard let mod = byHash[hash], file.sha1?.lowercased() != hash.lowercased() else { continue }
                found[mod.baseFileName] = file
            }
            updates = found
            message = found.isEmpty ? "Everything is up to date." : "\(found.count) update\(found.count == 1 ? "" : "s") available."
        } catch {
            message = Self.describe(error)
        }
    }

    func applyUpdate(_ mod: InstalledMod) async {
        guard let file = updates[mod.baseFileName], let url = file.url else { return }
        installing.insert(mod.id)
        defer { installing.remove(mod.id) }
        do {
            let staged = try await Self.download(url, expectedSHA1: file.sha1, expectedSHA512: file.sha512)
            try Self.place(staged, as: file.fileName, replacing: mod.baseFileName)
            var index = Self.loadIndex()
            index.removeValue(forKey: mod.baseFileName)
            index[file.fileName] = InstalledMod(fileName: file.fileName, source: .modrinth,
                                                projectId: file.projectId, versionId: file.versionId,
                                                versionName: file.versionName, title: mod.title,
                                                iconURL: mod.iconURL)
            Self.saveIndex(index)
            updates.removeValue(forKey: mod.baseFileName)
            changedSinceLaunch = true
            message = "Updated \(mod.displayName) to \(file.versionName)."
            shellLog("mods: updated \(mod.baseFileName) -> \(file.fileName)")
        } catch {
            message = "\(mod.displayName): \(Self.describe(error))"
        }
        refreshInstalled()
    }

    /// Import a jar picked in Files (verified to be a Fabric mod).
    func importJar(from picked: URL) {
        let scoped = picked.startAccessingSecurityScopedResource()
        defer { if scoped { picked.stopAccessingSecurityScopedResource() } }
        let staged = Self.modsDirectory().appendingPathComponent(".vrmc-import-\(UUID().uuidString).tmp")
        do {
            try FileManager.default.createDirectory(at: Self.modsDirectory(), withIntermediateDirectories: true)
            try FileManager.default.copyItem(at: picked, to: staged)
            guard let entries = SetupManager.zipEntryNames(of: staged), entries.contains("fabric.mod.json") else {
                try? FileManager.default.removeItem(at: staged)
                message = "\(picked.lastPathComponent) is not a Fabric mod."
                return
            }
            try Self.place(staged, as: picked.lastPathComponent, replacing: nil)
            changedSinceLaunch = true
            message = "Imported \(picked.lastPathComponent)."
            shellLog("mods: imported \(picked.lastPathComponent)")
        } catch {
            try? FileManager.default.removeItem(at: staged)
            message = "Import failed: \(error.localizedDescription)"
        }
        refreshInstalled()
    }

    nonisolated static func describe(_ error: Error) -> String {
        if let e = error as? ModError { return e.message }
        if let e = error as? URLError {
            switch e.code {
            case .notConnectedToInternet, .networkConnectionLost: return "No internet connection."
            case .timedOut: return "The server took too long to answer."
            default: return e.localizedDescription
            }
        }
        if error is DecodingError { return "The server sent an answer VRMC does not understand." }
        return error.localizedDescription
    }
}

// MARK: - Views

struct ModsView: View {
    @Bindable var shell: ShellCoordinator
    @State private var store = ModStore.shared
    @State private var pane: Pane = .browse
    @State private var selected: ModHit?
    @State private var importing = false
    @State private var pendingDelete: InstalledMod?
    @State private var pendingRiskyInstall: ModHit?

    enum Pane: String, CaseIterable, Identifiable {
        case browse = "Browse"
        case installed = "Installed"
        var id: String { rawValue }
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                header
                if shell.gameRunning && store.changedSinceLaunch {
                    Label("Mod changes load the next time you start the game.", systemImage: "arrow.clockwise.circle")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 24)
                        .padding(.bottom, 8)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                if !store.message.isEmpty {
                    Text(store.message)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 24)
                        .padding(.bottom, 8)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .accessibilityAddTraits(.updatesFrequently)
                }
                switch pane {
                case .browse: browse
                case .installed: installedList
                }
            }
            .navigationTitle("Mods")
            .toolbar { toolbar }
            .sheet(item: $selected) { hit in
                ModDetailSheet(hit: hit, store: store) { requestInstall(hit) }
            }
            .fileImporter(isPresented: $importing,
                          allowedContentTypes: [UTType(filenameExtension: "jar") ?? .data]) { result in
                if case .success(let url) = result { store.importJar(from: url) }
            }
            .confirmationDialog("Remove \(pendingDelete?.displayName ?? "mod")?",
                                isPresented: Binding(get: { pendingDelete != nil },
                                                     set: { if !$0 { pendingDelete = nil } }),
                                titleVisibility: .visible) {
                Button("Remove", role: .destructive) {
                    if let mod = pendingDelete { store.delete(mod) }
                    pendingDelete = nil
                }
            } message: {
                Text("The mod file is deleted from this headset. You can install it again later.")
            }
            .alert("This mod may not work in VR",
                   isPresented: Binding(get: { pendingRiskyInstall != nil },
                                        set: { if !$0 { pendingRiskyInstall = nil } })) {
                Button("Install anyway") {
                    if let hit = pendingRiskyInstall { Task { await store.install(hit) } }
                    pendingRiskyInstall = nil
                }
                Button("Cancel", role: .cancel) { pendingRiskyInstall = nil }
            } message: {
                Text(pendingRiskyInstall?.renderingWarning ?? "")
            }
        }
        .task {
            store.refreshInstalled()
            await store.search()
        }
    }

    private var header: some View {
        VStack(spacing: 12) {
            Picker("View", selection: $pane) {
                ForEach(Pane.allCases) { Text($0.rawValue).tag($0) }
            }
            .pickerStyle(.segmented)
            .frame(maxWidth: 360)
            if pane == .browse {
                HStack(spacing: 12) {
                    Picker("Source", selection: $store.source) {
                        ForEach(ModSource.allCases) { Text($0.title).tag($0) }
                    }
                    .pickerStyle(.segmented)
                    .frame(maxWidth: 300)
                    .onChange(of: store.source) { _, _ in Task { await store.search() } }
                    Picker("Sort", selection: $store.sort) {
                        ForEach(ModSort.allCases) { Text($0.title).tag($0) }
                    }
                    .onChange(of: store.sort) { _, _ in Task { await store.search() } }
                    Spacer()
                    Text("Fabric · Minecraft \(ModStore.gameVersion)")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                HStack {
                    Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                    TextField("Search \(store.source.title)", text: $store.query)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .submitLabel(.search)
                        .onSubmit { Task { await store.search(force: true) } }
                    if store.searching { ProgressView() }
                }
                .padding(12)
                .background(.thinMaterial, in: .rect(cornerRadius: 14))
            }
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 12)
    }

    @ViewBuilder private var browse: some View {
        if store.source == .curseforge && !store.curseForgeKeySet {
            ScrollView { CurseForgeKeyCard(store: store).padding(24) }
        } else if store.results.isEmpty && store.searching {
            ProgressView("Searching \(store.source.title)…").frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            List(store.results) { hit in
                ModRow(hit: hit, installed: store.isInstalled(hit), installing: store.installing.contains(hit.id)) {
                    requestInstall(hit)
                }
                .contentShape(Rectangle())
                .onTapGesture { selected = hit }
            }
            .listStyle(.plain)
            .refreshable { await store.search(force: true) }
        }
    }

    private var installedList: some View {
        List {
            Section {
                ForEach(store.installed) { mod in
                    InstalledRow(mod: mod, update: store.updates[mod.baseFileName],
                                 working: store.installing.contains(mod.id),
                                 setEnabled: { store.setEnabled(mod, $0) },
                                 remove: { pendingDelete = mod },
                                 applyUpdate: { Task { await store.applyUpdate(mod) } })
                }
            } footer: {
                Text("Mods with a lock are needed for VR and are managed by setup. Changes apply the next time the game starts.")
            }
        }
        .refreshable { store.refreshInstalled() }
    }

    @ToolbarContentBuilder private var toolbar: some ToolbarContent {
        ToolbarItemGroup(placement: .primaryAction) {
            if pane == .installed {
                Button {
                    Task { await store.checkUpdates() }
                } label: {
                    if store.checkingUpdates { ProgressView() } else {
                        Label("Check for updates", systemImage: "arrow.triangle.2.circlepath")
                    }
                }
                .disabled(store.checkingUpdates)
                Button { importing = true } label: { Label("Import .jar", systemImage: "square.and.arrow.down") }
            } else {
                Button {
                    Task { await store.search(force: true) }
                } label: { Label("Refresh", systemImage: "arrow.clockwise") }
            }
        }
    }

    private func requestInstall(_ hit: ModHit) {
        if hit.renderingWarning != nil {
            pendingRiskyInstall = hit
        } else {
            Task { await store.install(hit) }
        }
    }
}

private struct ModIcon: View {
    let url: URL?

    var body: some View {
        AsyncImage(url: url) { image in
            image.resizable().scaledToFit()
        } placeholder: {
            Image(systemName: "shippingbox").font(.title2).foregroundStyle(.secondary)
        }
        .frame(width: 52, height: 52)
        .background(.quaternary, in: .rect(cornerRadius: 12))
        .clipShape(.rect(cornerRadius: 12))
        .accessibilityHidden(true)
    }
}

private struct ModRow: View {
    let hit: ModHit
    let installed: Bool
    let installing: Bool
    let install: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            ModIcon(url: hit.iconURL)
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Text(hit.title).font(.headline)
                    if !hit.author.isEmpty {
                        Text("by \(hit.author)").font(.subheadline).foregroundStyle(.secondary)
                    }
                }
                Text(hit.summary)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                HStack(spacing: 10) {
                    Label(Self.count(hit.downloads), systemImage: "arrow.down.circle")
                    if hit.renderingWarning != nil {
                        Label("May not work in VR", systemImage: "exclamationmark.triangle")
                            .foregroundStyle(.orange)
                    }
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }
            Spacer(minLength: 8)
            if installing {
                ProgressView()
            } else if installed {
                Label("Installed", systemImage: "checkmark.circle.fill")
                    .labelStyle(.iconOnly)
                    .foregroundStyle(.green)
                    .font(.title2)
                    .accessibilityLabel("Installed")
            } else {
                Button("Install", action: install)
                    .buttonStyle(.borderedProminent)
                    .buttonBorderShape(.capsule)
            }
        }
        .padding(.vertical, 6)
        .accessibilityElement(children: .combine)
    }

    static func count(_ n: Int) -> String {
        switch n {
        case 1_000_000...: return String(format: "%.1fM", Double(n) / 1_000_000)
        case 1_000...: return String(format: "%.0fK", Double(n) / 1_000)
        default: return "\(n)"
        }
    }
}

private struct ModDetailSheet: View {
    let hit: ModHit
    var store: ModStore
    let install: () -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    HStack(spacing: 16) {
                        ModIcon(url: hit.iconURL)
                        VStack(alignment: .leading) {
                            Text(hit.title).font(.title2.bold())
                            Text("\(hit.source.title)\(hit.author.isEmpty ? "" : " · by \(hit.author)") · \(ModRow.count(hit.downloads)) downloads")
                                .foregroundStyle(.secondary)
                        }
                    }
                    Text(hit.summary)
                    if !hit.categories.isEmpty {
                        Text(hit.categories.joined(separator: " · "))
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                    if let warning = hit.renderingWarning {
                        Label(warning, systemImage: "exclamationmark.triangle")
                            .foregroundStyle(.orange)
                    }
                    HStack(spacing: 12) {
                        if store.isInstalled(hit) {
                            Label("Installed", systemImage: "checkmark.circle.fill").foregroundStyle(.green)
                        } else if store.installing.contains(hit.id) {
                            ProgressView()
                        } else {
                            Button {
                                install()
                            } label: {
                                Label("Install latest for \(ModStore.gameVersion)", systemImage: "arrow.down.circle")
                            }
                            .buttonStyle(.borderedProminent)
                        }
                        if let page = hit.pageURL {
                            Link(destination: page) {
                                Label("Open on \(hit.source.title)", systemImage: "safari")
                            }
                        }
                    }
                    Text("Downloads are checked against the hash \(hit.source.title) publishes before anything is installed. Required mods are installed too.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                .padding(28)
            }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Done") { dismiss() } }
            }
        }
        .frame(minWidth: 560, minHeight: 420)
    }
}

private struct InstalledRow: View {
    let mod: InstalledMod
    let update: ModFile?
    let working: Bool
    let setEnabled: @MainActor @Sendable (Bool) -> Void
    let remove: () -> Void
    let applyUpdate: () -> Void

    var body: some View {
        HStack(spacing: 14) {
            ModIcon(url: mod.iconURL.flatMap(URL.init(string:)))
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(mod.displayName).font(.headline)
                    if mod.isCore {
                        Image(systemName: "lock.fill").font(.caption).foregroundStyle(.secondary)
                            .accessibilityLabel("Needed for VR")
                    }
                }
                Text([mod.source?.title, mod.versionName, mod.baseFileName].compactMap { $0 }.joined(separator: " · "))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                if let update {
                    Text("Update available: \(update.versionName)").font(.caption).foregroundStyle(.blue)
                }
            }
            Spacer(minLength: 8)
            if working {
                ProgressView()
            } else if update != nil {
                Button("Update", action: applyUpdate).buttonStyle(.bordered)
            }
            if !mod.isCore {
                Toggle("Enabled", isOn: Binding(get: { mod.enabled }, set: setEnabled))
                    .labelsHidden()
                Button(role: .destructive, action: remove) {
                    Label("Remove", systemImage: "trash").labelStyle(.iconOnly)
                }
                .buttonStyle(.borderless)
                .accessibilityLabel("Remove \(mod.displayName)")
            }
        }
        .padding(.vertical, 4)
        .opacity(mod.enabled ? 1 : 0.6)
    }
}

private struct CurseForgeKeyCard: View {
    var store: ModStore
    @State private var key = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Label("CurseForge needs an API key", systemImage: "key")
                .font(.title3.bold())
            Text("CurseForge only lets apps use its catalogue with a personal API key. It is free: sign in at console.curseforge.com, create a key, and paste it here. The key is stored in this headset's Keychain and is only sent to api.curseforge.com.")
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            Link(destination: URL(string: "https://console.curseforge.com/")!) {
                Label("Open console.curseforge.com", systemImage: "safari")
            }
            HStack {
                SecureField("CurseForge API key", text: $key)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .padding(12)
                    .background(.thinMaterial, in: .rect(cornerRadius: 12))
                Button("Save") {
                    store.setCurseForgeKey(key)
                    key = ""
                }
                .buttonStyle(.borderedProminent)
                .disabled(key.trimmingCharacters(in: .whitespaces).isEmpty)
            }
            Text("Modrinth works without a key.")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
        .padding(24)
        .background(.regularMaterial, in: .rect(cornerRadius: 24))
    }
}
