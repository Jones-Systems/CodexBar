import CodexBarCore

extension SettingsStore {
    var codexAccountOrder: [String] {
        self.providerConfig(for: .codex)?.codexAccountOrder ?? []
    }

    func orderedCodexAccounts(_ accounts: [CodexVisibleAccount]) -> [CodexVisibleAccount] {
        CodexAccountOrder.ordered(accounts, savedOrder: self.codexAccountOrder)
    }

    func moveCodexAccount(_ account: CodexVisibleAccount, by offset: Int, in accounts: [CodexVisibleAccount]) {
        guard let order = CodexAccountOrder.moving(
            account, by: offset, in: accounts, savedOrder: self.codexAccountOrder) else { return }
        self.updateProviderConfig(provider: .codex, affectsBackgroundWork: false) { entry in
            entry.codexAccountOrder = order
        }
    }
}

enum CodexAccountOrder {
    /// Visible row IDs change when same-email siblings appear; source identity keeps saved positions stable.
    static func key(for account: CodexVisibleAccount) -> String {
        if let id = account.storedAccountID { return "managed:\(id.uuidString.lowercased())" }
        switch account.selectionSource {
        case let .managedAccount(id): return "managed:\(id.uuidString.lowercased())"
        case let .profileHome(path): return "profile:\(CodexHomeScope.normalizedHomePath(path) ?? path)"
        case .liveSystem: return "live:\(account.email.lowercased()):\(account.workspaceAccountID ?? "")"
        }
    }

    static func ordered(_ accounts: [CodexVisibleAccount], savedOrder: [String]) -> [CodexVisibleAccount] {
        var ranks: [String: Int] = [:]
        for (index, key) in savedOrder.enumerated() where ranks[key] == nil {
            ranks[key] = index
        }
        return accounts.enumerated().sorted { lhs, rhs in
            let left = ranks[self.key(for: lhs.element)] ?? Int.max
            let right = ranks[self.key(for: rhs.element)] ?? Int.max
            return left == right ? lhs.offset < rhs.offset : left < right
        }.map(\.element)
    }

    static func moving(
        _ account: CodexVisibleAccount,
        by offset: Int,
        in accounts: [CodexVisibleAccount],
        savedOrder: [String]) -> [String]?
    {
        guard offset == -1 || offset == 1 else { return nil }
        let visible = self.ordered(accounts, savedOrder: savedOrder).map { self.key(for: $0) }
        guard let source = visible.firstIndex(of: self.key(for: account)),
              visible.indices.contains(source + offset) else { return nil }
        var seen: Set<String> = []
        var result = (savedOrder + visible).filter { seen.insert($0).inserted }
        guard let first = result.firstIndex(of: visible[source]),
              let second = result.firstIndex(of: visible[source + offset]) else { return nil }
        result.swapAt(first, second)
        return result
    }
}
