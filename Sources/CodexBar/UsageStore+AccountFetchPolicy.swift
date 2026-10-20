import CodexBarCore

extension UsageStore {
    static let maxConcurrentAccountFetches = 3

    static func accountMenuDisplayLimit(for provider: UsageProvider) -> Int? {
        switch provider {
        case .codex, .claude: nil
        default: 6
        }
    }

    nonisolated static func boundedOrderedTaskGroup<Request: Sendable, Result: Sendable>(
        limit: Int,
        requests: [Request],
        operation: @escaping @Sendable (Request) async -> Result) async -> [Result]
    {
        precondition(limit > 0)
        return await withTaskGroup(of: (Int, Result).self) { group in
            var nextIndex = 0
            func enqueueNext() {
                guard !Task.isCancelled, nextIndex < requests.count else { return }
                let index = nextIndex
                let request = requests[index]
                if group.addTaskUnlessCancelled(operation: { await (index, operation(request)) }) {
                    nextIndex += 1
                }
            }
            for _ in 0..<min(limit, requests.count) {
                enqueueNext()
            }
            var results: [(Int, Result)] = []
            results.reserveCapacity(requests.count)
            while let result = await group.next() {
                results.append(result)
                if Task.isCancelled {
                    group.cancelAll()
                } else {
                    enqueueNext()
                }
            }
            return results.sorted { $0.0 < $1.0 }.map(\.1)
        }
    }
}
