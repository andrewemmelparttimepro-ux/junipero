import Foundation

struct ProductSpec: Codable, Identifiable, Equatable {
    let id: String
    var name: String
    var rootPath: String
    var repoRemote: String
    var devCommand: String
    var buildCommand: String
    var testCommand: String
    var clarity: ClaritySpec?
    var userFlows: [ProductUserFlow]
    var enabled: Bool
}

struct ClaritySpec: Codable, Equatable {
    var expected: Bool
    var projectId: String
    var dashboardUrl: String
    var notes: String
}

struct ProductUserFlow: Codable, Identifiable, Equatable {
    var id: String
    var name: String
    var url: String
    var notes: String
}

struct ProofRun: Codable, Identifiable, Equatable {
    enum Status: String, Codable {
        case pending
        case passed
        case failed
        case warning
    }

    let id: String
    let productId: String
    let startedAt: Date
    var completedAt: Date?
    var status: Status
    var screenshots: [String]
    var logs: [String]
    var summaryPath: String
    var wikiUpdated: Bool
}

enum ProductRegistryBootstrap {
    private static let fm = FileManager.default

    static var registryPath: URL {
        ThrawnPaths.appSupportDir
            .appendingPathComponent("workspace/product-registry/products.json")
    }

    static var schedulePath: URL {
        ThrawnPaths.appSupportDir
            .appendingPathComponent("workspace/product-registry/schedule.json")
    }

    static var proofsRoot: URL {
        ThrawnPaths.appSupportDir.appendingPathComponent("workspace/proofs")
    }

    static var wikiRoot: URL {
        ThrawnPaths.appSupportDir.appendingPathComponent("workspace/citadel")
    }

    private static var legacyWikiRoot: URL {
        ThrawnPaths.appSupportDir.appendingPathComponent("workspace/wiki")
    }

    static func bootstrap(overwrite: Bool = false) {
        do {
            try fm.createDirectory(at: registryPath.deletingLastPathComponent(), withIntermediateDirectories: true)
            try fm.createDirectory(at: proofsRoot, withIntermediateDirectories: true)
            try migrateLegacyWikiToCitadel()
            try fm.createDirectory(at: wikiRoot.appendingPathComponent("products"), withIntermediateDirectories: true)

            if overwrite || !fm.fileExists(atPath: registryPath.path) {
                let data = try JSONEncoder.pretty.encode(defaultProducts)
                try data.write(to: registryPath, options: .atomic)
            } else {
                try migrateRegistryForClarity()
            }

            if overwrite || !fm.fileExists(atPath: schedulePath.path) {
                let data = try JSONSerialization.data(
                    withJSONObject: defaultSchedule,
                    options: [.prettyPrinted, .sortedKeys]
                )
                try data.write(to: schedulePath, options: .atomic)
            }

            for product in defaultProducts {
                try fm.createDirectory(
                    at: proofsRoot.appendingPathComponent(product.id),
                    withIntermediateDirectories: true
                )
                let citadelPage = wikiRoot.appendingPathComponent("products/\(product.id).md")
                if overwrite || !fm.fileExists(atPath: citadelPage.path) {
                    try productCitadelTemplate(product).write(to: citadelPage, atomically: true, encoding: .utf8)
                }
            }

            let rolling = wikiRoot.appendingPathComponent("rolling-72h.md")
            if overwrite || !fm.fileExists(atPath: rolling.path) {
                try rollingTemplate.write(to: rolling, atomically: true, encoding: .utf8)
            }
        } catch {
            FlightRecorder.logError(
                source: "product-registry:bootstrap",
                message: error.localizedDescription
            )
        }
    }

    static let defaultProducts: [ProductSpec] = [
        ProductSpec(
            id: "vaultage",
            name: "Vaultage",
            rootPath: "/Users/andrewemmel/Downloads/Vaultage",
            repoRemote: "https://github.com/andrewemmelparttimepro-ux/vaultage.git",
            devCommand: "npm run dev",
            buildCommand: "",
            testCommand: "npm run test:e2e",
            clarity: ClaritySpec(
                expected: true,
                projectId: "",
                dashboardUrl: "",
                notes: "Thrawn should confirm Microsoft Clarity is installed or flag setup work."
            ),
            userFlows: [
                ProductUserFlow(id: "home", name: "Home loads", url: "http://127.0.0.1:4173", notes: "Open the local Vaultage surface and capture first paint.")
            ],
            enabled: true
        ),
        ProductSpec(
            id: "hit-zero",
            name: "Hit Zero",
            rootPath: "/Users/andrewemmel/Desktop/apps/hitzero/hit_zero_client",
            repoRemote: "https://github.com/andrewemmelparttimepro-ux/Hit-Zero.git",
            devCommand: "npm run dev -- --host=127.0.0.1",
            buildCommand: "npm run build",
            testCommand: "npm run test",
            clarity: ClaritySpec(
                expected: true,
                projectId: "",
                dashboardUrl: "https://clarity.microsoft.com/",
                notes: "Known Clarity project in use: Hit Zero / MCA. Treat rage clicks, dead clicks, recordings, heatmaps, and smart events as primary change signals."
            ),
            userFlows: [
                ProductUserFlow(id: "home", name: "App shell loads", url: "http://127.0.0.1:5173", notes: "Open app shell and verify no immediate blank-screen failure.")
            ],
            enabled: true
        ),
        ProductSpec(
            id: "cyclops",
            name: "Cyclops",
            rootPath: "/Users/andrewemmel/Desktop/apps/cyclops",
            repoRemote: "",
            devCommand: "npm run dev",
            buildCommand: "npm run build",
            testCommand: "npm run lint",
            clarity: ClaritySpec(
                expected: true,
                projectId: "",
                dashboardUrl: "",
                notes: "Thrawn should confirm Microsoft Clarity is installed or flag setup work."
            ),
            userFlows: [
                ProductUserFlow(id: "home", name: "Command display loads", url: "http://127.0.0.1:3000", notes: "Open the Cyclops command surface and capture visible state.")
            ],
            enabled: true
        ),
        ProductSpec(
            id: "sandpro-omp",
            name: "Sandpro OMP",
            rootPath: "/Users/andrewemmel/Documents/New project/sandpro-omp",
            repoRemote: "https://github.com/andrewemmelparttimepro-ux/sandpro-omp.git",
            devCommand: "npm run dev -- --host=127.0.0.1",
            buildCommand: "npm run build",
            testCommand: "npm run test:unit",
            clarity: ClaritySpec(
                expected: true,
                projectId: "",
                dashboardUrl: "",
                notes: "Thrawn should confirm Microsoft Clarity is installed or flag setup work."
            ),
            userFlows: [
                ProductUserFlow(id: "home", name: "Dashboard loads", url: "http://127.0.0.1:5173", notes: "Open the OMP surface and capture the primary dashboard.")
            ],
            enabled: true
        ),
    ]

    private static let defaultSchedule: [String: Any] = [
        "cadence": "three_daily",
        "windows": [
            ["id": "morning", "hour": 8, "minute": 10],
            ["id": "afternoon", "hour": 13, "minute": 10],
            ["id": "evening", "hour": 18, "minute": 10],
        ],
        "timezone": TimeZone.current.identifier,
        "dedupe_key": "productId + yyyy-MM-dd + window",
    ]

    private static func productCitadelTemplate(_ product: ProductSpec) -> String {
        """
        # \(product.name)

        ## Current Read
        No v2 proof runs recorded yet.

        ## Recent Proofs
        _Thrawn appends reviewed proof links here._

        ## Clarity Signals
        Microsoft Clarity is a primary product-improvement source for this product when available.
        Track rage clicks, dead clicks, quick backs, excessive scrolling, recordings, heatmaps, funnels, and smart events before recommending UX or conversion changes.

        ## Open Questions
        - Confirm production URL and highest-value user flows.
        - Confirm Microsoft Clarity project ID and dashboard URL.

        ## Registry
        - Product ID: `\(product.id)`
        - Root: `\(product.rootPath)`
        - Remote: `\(product.repoRemote.isEmpty ? "not recorded" : product.repoRemote)`
        - Clarity expected: `\(product.clarity?.expected == true ? "true" : "false")`
        - Clarity dashboard: `\(product.clarity?.dashboardUrl.isEmpty == false ? product.clarity!.dashboardUrl : "not recorded")`
        """
    }

    private static func migrateRegistryForClarity() throws {
        guard let data = try? Data(contentsOf: registryPath),
              var rawProducts = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]]
        else { return }

        var changed = false
        for index in rawProducts.indices {
            let id = rawProducts[index]["id"] as? String ?? ""
            if rawProducts[index]["clarity"] == nil {
                rawProducts[index]["clarity"] = clarityDictionary(for: id)
                changed = true
            }
        }

        guard changed else { return }
        let migrated = try JSONSerialization.data(withJSONObject: rawProducts, options: [.prettyPrinted, .sortedKeys])
        try migrated.write(to: registryPath, options: .atomic)
    }

    private static func migrateLegacyWikiToCitadel() throws {
        guard fm.fileExists(atPath: legacyWikiRoot.path) else { return }
        try fm.createDirectory(at: wikiRoot, withIntermediateDirectories: true)

        let legacyProducts = legacyWikiRoot.appendingPathComponent("products", isDirectory: true)
        let citadelProducts = wikiRoot.appendingPathComponent("products", isDirectory: true)
        if fm.fileExists(atPath: legacyProducts.path) {
            try fm.createDirectory(at: citadelProducts, withIntermediateDirectories: true)
            let productPages = try fm.contentsOfDirectory(at: legacyProducts, includingPropertiesForKeys: nil)
            for page in productPages where page.pathExtension == "md" {
                let destination = citadelProducts.appendingPathComponent(page.lastPathComponent)
                if !fm.fileExists(atPath: destination.path) {
                    try fm.copyItem(at: page, to: destination)
                }
            }
        }

        let legacyRolling = legacyWikiRoot.appendingPathComponent("rolling-72h.md")
        let citadelRolling = wikiRoot.appendingPathComponent("rolling-72h.md")
        if fm.fileExists(atPath: legacyRolling.path), !fm.fileExists(atPath: citadelRolling.path) {
            try fm.copyItem(at: legacyRolling, to: citadelRolling)
        }
    }

    private static func clarityDictionary(for productId: String) -> [String: Any] {
        if productId == "hit-zero" {
            return [
                "expected": true,
                "projectId": "",
                "dashboardUrl": "https://clarity.microsoft.com/",
                "notes": "Known Clarity project in use: Hit Zero / MCA. Treat rage clicks, dead clicks, recordings, heatmaps, and smart events as primary change signals.",
            ]
        }
        return [
            "expected": true,
            "projectId": "",
            "dashboardUrl": "",
            "notes": "Thrawn should confirm Microsoft Clarity is installed or flag setup work.",
        ]
    }

    private static let rollingTemplate = """
    # NDAI Rolling 72-Hour Operating Brief

    No v2 proof runs recorded yet.

    ## Product Health
    _Thrawn summarizes the last 72 hours here._

    ## Patterns
    _Recurring failures, regressions, and opportunities._

    ## Next Checks
    _What the next proof review should pay attention to._
    """
}

private extension JSONEncoder {
    static var pretty: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }
}
