import Foundation
public enum VPArtwork {
    public static func url(_ name: String) -> URL? {
        let base = (name as NSString).deletingPathExtension
        let ext = (name as NSString).pathExtension
        return VPResources.url(base, withExtension: ext)
    }
}
