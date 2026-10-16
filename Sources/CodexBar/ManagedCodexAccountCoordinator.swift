import CodexBarCore
import Foundation
import Observation

enum ManagedCodexAccountCoordinatorError: Error, Equatable {
    case authenticationInProgress
}

@MainActor
@Observable
final class ManagedCodexAccountCoordinator {
    let service: ManagedCodexAccountService
    private(set) var isAuthenticatingManagedAccount: Bool = false
    private(set) var authenticatingManagedAccountID: UUID?
    private(set) var isRemovingManagedAccount: Bool = false
    private(set) var removingManagedAccountID: UUID?
    private var authenticationID: UUID?
    private var authenticationTask: Task<ManagedCodexAccount, Error>?
    var onManagedAccountsDidChange: (@MainActor () -> Void)?

    var hasConflictingManagedAccountOperationInFlight: Bool {
        self.isAuthenticatingManagedAccount || self.isRemovingManagedAccount
    }

    init(service: ManagedCodexAccountService = ManagedCodexAccountService()) {
        self.service = service
    }

    func authenticateManagedAccount(
        existingAccountID: UUID? = nil,
        timeout: TimeInterval = 120)
        async throws -> ManagedCodexAccount
    {
        guard self.isAuthenticatingManagedAccount == false else {
            throw ManagedCodexAccountCoordinatorError.authenticationInProgress
        }

        try Task.checkCancellation()
        let authenticationID = UUID()
        self.authenticationID = authenticationID
        self.isAuthenticatingManagedAccount = true
        self.authenticatingManagedAccountID = existingAccountID
        defer {
            if self.authenticationID == authenticationID {
                self.clearAuthentication()
            }
        }

        let task = Task {
            try await self.service.authenticateManagedAccount(
                existingAccountID: existingAccountID,
                timeout: timeout)
        }
        self.authenticationTask = task
        let account = try await withTaskCancellationHandler {
            try await task.value
        } onCancel: {
            task.cancel()
        }
        try Task.checkCancellation()
        guard self.authenticationID == authenticationID else { throw CancellationError() }
        self.onManagedAccountsDidChange?()
        return account
    }

    func cancelAuthentication() {
        self.authenticationTask?.cancel()
        self.clearAuthentication()
    }

    private func clearAuthentication() {
        self.authenticationID = nil
        self.authenticationTask = nil
        self.isAuthenticatingManagedAccount = false
        self.authenticatingManagedAccountID = nil
    }

    func removeManagedAccount(id: UUID) async throws {
        self.isRemovingManagedAccount = true
        self.removingManagedAccountID = id
        defer {
            self.isRemovingManagedAccount = false
            self.removingManagedAccountID = nil
        }

        try await self.service.removeManagedAccount(id: id)
        self.onManagedAccountsDidChange?()
    }
}
