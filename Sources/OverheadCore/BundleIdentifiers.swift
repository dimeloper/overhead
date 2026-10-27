import Foundation

/// Links a simulator to a project through the app it runs: the app's bundle identifier against the ones the repo
/// declares.
public enum BundleIdentifiers {
    /// Identifiers a checkout declares: Expo `app.json` and `app.config.*`, Xcode projects at the root or in `ios/`,
    /// and XcodeGen's `project.yml`. Build-setting variables like `$(PRODUCT_NAME)` are skipped.
    public static func declared(in projectPath: String, fileManager: FileManager = .default) -> Set<String> {
        let root = URL(fileURLWithPath: projectPath)
        var found = Set<String>()

        if let data = try? Data(contentsOf: root.appendingPathComponent("app.json")),
           let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            let expo = json["expo"] as? [String: Any] ?? json
            if let id = (expo["ios"] as? [String: Any])?["bundleIdentifier"] as? String { found.insert(id) }
        }
        for name in ["app.config.ts", "app.config.js", "app.config.mjs"] {
            found.formUnion(matches(in: root.appendingPathComponent(name), pattern: #"bundleIdentifier\s*:\s*['"]([^'"]+)['"]"#))
        }
        found.formUnion(matches(in: root.appendingPathComponent("project.yml"), pattern: #"PRODUCT_BUNDLE_IDENTIFIER:\s*"?([A-Za-z0-9.\-]+)"?"#))
        for folder in [root, root.appendingPathComponent("ios")] {
            let entries = (try? fileManager.contentsOfDirectory(atPath: folder.path)) ?? []
            for entry in entries where entry.hasSuffix(".xcodeproj") {
                let pbxproj = folder.appendingPathComponent(entry).appendingPathComponent("project.pbxproj")
                found.formUnion(matches(in: pbxproj, pattern: #"PRODUCT_BUNDLE_IDENTIFIER = "?([^";$]+)"?;"#))
            }
        }
        return found
    }

    /// A simulator app matches a project that declares its identifier, or one of its extensions'
    /// (`com.acme.app.widget` belongs to `com.acme.app`).
    public static func matches(app: String, declared: Set<String>) -> Bool {
        declared.contains { $0 == app || $0.hasPrefix(app + ".") || app.hasPrefix($0 + ".") }
    }

    static func matches(in file: URL, pattern: String) -> Set<String> {
        guard let text = try? String(contentsOf: file, encoding: .utf8),
              let regex = try? NSRegularExpression(pattern: pattern) else { return [] }
        let range = NSRange(text.startIndex..., in: text)
        return Set(regex.matches(in: text, range: range).compactMap { match in
            Range(match.range(at: 1), in: text).map { String(text[$0]).trimmingCharacters(in: .whitespaces) }
        })
    }

    /// Bundle identifiers of the apps a simulator is running, from each app's `Info.plist`.
    public static func runningApps(in simulator: BootedSimulator, samples: [ProcessSample]) -> Set<String> {
        let marker = "/Devices/\(simulator.udid)/data/Containers/Bundle/Application/"
        var ids = Set<String>()
        for sample in samples {
            guard let path = ProcessSampler.executablePath(sample.pid), path.contains(marker),
                  let app = path.range(of: ".app/") else { continue }
            let plist = URL(fileURLWithPath: String(path[..<app.lowerBound]) + ".app/Info.plist")
            if let data = try? Data(contentsOf: plist),
               let info = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any],
               let id = info["CFBundleIdentifier"] as? String {
                ids.insert(id)
            }
        }
        return ids
    }
}
