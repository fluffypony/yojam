import Foundation

/// Shared rule ordering semantics for every routing surface.
///
/// Priority is the user-visible execution order. Rules with the same priority
/// keep their stored array order so older settings remain stable after decode.
public enum RuleOrdering {
    public static func sorted(_ rules: [Rule]) -> [Rule] {
        rules.enumerated()
            .sorted { lhs, rhs in
                if lhs.element.priority != rhs.element.priority {
                    return lhs.element.priority < rhs.element.priority
                }
                return lhs.offset < rhs.offset
            }
            .map(\.element)
    }

    public static func enabled(_ rules: [Rule]) -> [Rule] {
        sorted(rules).filter(\.enabled)
    }
}
