import Foundation

/// Lookup works in both a packaged app and a SwiftPM executable, without the
/// generated Bundle.module accessor's fatalError when its build folder is gone.
public enum VPResources {
    public static func url(_ name: String, withExtension ext: String, bundle: Bundle = .main) -> URL? {
        if let url = bundle.url(forResource: name, withExtension: ext) { return url }
        let resourceBundle = "VP2xMac_VP2xCore.bundle"
        let candidates = [bundle.resourceURL, bundle.bundleURL,
                          bundle.executableURL?.deletingLastPathComponent()]
        for root in candidates.compactMap({ $0 }) {
            if let resources = Bundle(url: root.appendingPathComponent(resourceBundle)),
               let url = resources.url(forResource: name, withExtension: ext) { return url }
        }
        return nil
    }
}
