import Foundation

enum ThrawnResources {
    private static let bundleName = "ThrawnConsole_ThrawnApp.bundle"

    static func url(forResource name: String, withExtension fileExtension: String) -> URL? {
        if let resourceURL = Bundle.main.resourceURL {
            let packagedURL = resourceURL
                .appendingPathComponent(bundleName, isDirectory: true)
                .appendingPathComponent(name)
                .appendingPathExtension(fileExtension)
            if FileManager.default.fileExists(atPath: packagedURL.path) {
                return packagedURL
            }
        }

        // SwiftPM test and command-line builds keep the generated resource
        // bundle beside the build product, where Bundle.module is valid.
        return Bundle.module.url(forResource: name, withExtension: fileExtension)
    }
}
