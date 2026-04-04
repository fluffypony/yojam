import Foundation

final class Debouncer: @unchecked Sendable {
    private let delay: TimeInterval
    private var workItem: DispatchWorkItem?
    private let queue: DispatchQueue

    init(delay: TimeInterval, queue: DispatchQueue = .main) {
        self.delay = delay; self.queue = queue
    }

    func debounce(action: @escaping () -> Void) {
        workItem?.cancel()
        let item = DispatchWorkItem(block: action); workItem = item
        queue.asyncAfter(deadline: .now() + delay, execute: item)
    }
}
