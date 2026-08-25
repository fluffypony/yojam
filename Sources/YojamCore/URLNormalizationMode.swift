import WebURL

public enum URLNormalizationMode: String, Codable, Hashable, Sendable {
    case none
    case whatwg

    public func normalize(_ urlString: String) -> String {
        switch self {
        case .none:
            return urlString
        case .whatwg:
            return WebURL(urlString)?.serialized() ?? urlString
        }
    }
}
