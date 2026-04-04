import Foundation

struct ArcProfileReader {
    func readProfiles(bundleId: String) -> [BrowserProfile] {
        let sidebarPath = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/Arc/StorableSidebar.json")
        guard let data = try? Data(contentsOf: sidebarPath),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else { return [] }
        var profiles: [BrowserProfile] = []
        if let sidebar = json["sidebar"] as? [String: Any],
           let containers = sidebar["containers"] as? [[String: Any]] {
            for (idx, space) in containers.enumerated() {
                let title = space["title"] as? String ?? "Space \(idx + 1)"
                let id = space["id"] as? String ?? "space_\(idx)"
                profiles.append(BrowserProfile(
                    id: id, name: title, browserBundleId: bundleId))
            }
        }
        return profiles
    }
}
