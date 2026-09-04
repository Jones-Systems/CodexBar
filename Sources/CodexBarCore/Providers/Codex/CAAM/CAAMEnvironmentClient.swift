import Foundation

public struct CAAMEnvironmentCommand: Sendable, Equatable {
    public let binary: String
    public let arguments: [String]
    public let timeout: TimeInterval
    public let maximumOutputBytes: Int
    public let label: String

    public init(
        binary: String,
        arguments: [String],
        timeout: TimeInterval,
        maximumOutputBytes: Int,
        label: String)
    {
        self.binary = binary
        self.arguments = arguments
        self.timeout = timeout
        self.maximumOutputBytes = maximumOutputBytes
        self.label = label
    }
}

public protocol CAAMEnvironmentCommandRunning: Sendable {
    func run(command: CAAMEnvironmentCommand, environment: [String: String]) async throws -> SubprocessResult
}

public struct DefaultCAAMEnvironmentCommandRunner: CAAMEnvironmentCommandRunning {
    public init() {}

    public func run(
        command: CAAMEnvironmentCommand,
        environment: [String: String]) async throws -> SubprocessResult
    {
        try await SubprocessRunner.run(
            binary: command.binary,
            arguments: command.arguments,
            environment: environment,
            timeout: command.timeout,
            maxOutputBytes: command.maximumOutputBytes,
            label: command.label)
    }
}

public enum CAAMGatewayOperation: Sendable, Equatable {
    case snapshot(environmentID: String)
    case planSwitch(environmentID: String, profile: String, expectedRevision: String)
    case executeSwitch(environmentID: String, planDigest: String, operationID: UUID, idempotencyKey: UUID)
    case operationStatus(environmentID: String, operationID: UUID)
    case recoverSwitch(environmentID: String, operationID: UUID, expectedRevision: String)
    case restoreFallback(
        environmentID: String,
        expectedRevision: String,
        planDigest: String,
        operationID: UUID,
        idempotencyKey: UUID)

    public var environmentID: String {
        switch self {
        case let .snapshot(environmentID),
             let .planSwitch(environmentID, _, _),
             let .executeSwitch(environmentID, _, _, _),
             let .operationStatus(environmentID, _),
             let .recoverSwitch(environmentID, _, _),
             let .restoreFallback(environmentID, _, _, _, _):
            environmentID
        }
    }

    public var mayMutateCredentials: Bool {
        switch self {
        case .executeSwitch, .recoverSwitch, .restoreFallback: true
        case .snapshot, .planSwitch, .operationStatus: false
        }
    }

    func gatewayArguments() throws -> [String] {
        guard CAAMEnvironmentContract.isSafeIdentifier(self.environmentID, maximumLength: 64) else {
            throw CAAMEnvironmentContractError.invalidConfiguration("The CAAM environment ID is invalid.")
        }
        switch self {
        case let .snapshot(environmentID):
            return ["snapshot", "--environment-id", environmentID]
        case let .planSwitch(environmentID, profile, expectedRevision):
            try Self.validateProfile(profile)
            try Self.validateRevision(expectedRevision)
            return [
                "plan-switch",
                "--environment-id", environmentID,
                "--profile", profile,
                "--expected-revision", expectedRevision,
            ]
        case let .executeSwitch(environmentID, planDigest, operationID, idempotencyKey):
            try Self.validatePlanDigest(planDigest)
            return [
                "execute-switch",
                "--environment-id", environmentID,
                "--plan-digest", planDigest,
                "--operation-id", operationID.uuidString.lowercased(),
                "--idempotency-key", idempotencyKey.uuidString.lowercased(),
            ]
        case let .operationStatus(environmentID, operationID):
            return [
                "operation-status",
                "--environment-id", environmentID,
                "--operation-id", operationID.uuidString.lowercased(),
            ]
        case let .recoverSwitch(environmentID, operationID, expectedRevision):
            try Self.validateRevision(expectedRevision)
            return [
                "recover-switch",
                "--environment-id", environmentID,
                "--operation-id", operationID.uuidString.lowercased(),
                "--expected-revision", expectedRevision,
            ]
        case let .restoreFallback(environmentID, expectedRevision, planDigest, operationID, idempotencyKey):
            try Self.validateRevision(expectedRevision)
            try Self.validatePlanDigest(planDigest)
            return [
                "restore-fallback",
                "--environment-id", environmentID,
                "--expected-revision", expectedRevision,
                "--plan-digest", planDigest,
                "--operation-id", operationID.uuidString.lowercased(),
                "--idempotency-key", idempotencyKey.uuidString.lowercased(),
            ]
        }
    }

    private static func validateProfile(_ profile: String) throws {
        guard CAAMEnvironmentContract.isSafeIdentifier(profile, maximumLength: 64) else {
            throw CAAMEnvironmentContractError.invalidConfiguration("The CAAM profile name is invalid.")
        }
    }

    private static func validateRevision(_ revision: String) throws {
        guard !revision.isEmpty, revision.count <= 64, revision.unicodeScalars.allSatisfy({ scalar in
            guard scalar.value < 128 else { return false }
            return switch scalar.value {
            case 45, 46, 48...58, 65...90, 95, 97...122: true
            default: false
            }
        }) else {
            throw CAAMEnvironmentContractError.invalidConfiguration("The CAAM snapshot revision is invalid.")
        }
    }

    private static func validatePlanDigest(_ digest: String) throws {
        guard digest.count == 64, digest.unicodeScalars.allSatisfy({ scalar in
            switch scalar.value {
            case 48...57, 97...102: true
            default: false
            }
        }) else {
            throw CAAMEnvironmentContractError.invalidConfiguration("The CAAM switch plan digest is invalid.")
        }
    }
}

public enum CAAMEnvironmentClientError: LocalizedError, Sendable, Equatable {
    case binaryUnavailable
    case timedOut
    case responseTooLarge
    case commandFailed
    case cancelled

    public var errorDescription: String? {
        switch self {
        case .binaryUnavailable: "CAAM is not available on this environment."
        case .timedOut: "The CAAM environment did not respond in time."
        case .responseTooLarge: "The CAAM environment returned an oversized response."
        case .commandFailed: "The CAAM environment command failed."
        case .cancelled: "The CAAM environment request was cancelled."
        }
    }
}

public struct CAAMEnvironmentClient: Sendable {
    public static let defaultGatewayName = "caam-codexbar"
    public static let defaultSSHBinary = "/usr/bin/ssh"
    public static let defaultTimeout: TimeInterval = 8

    private let runner: any CAAMEnvironmentCommandRunning
    private let environment: [String: String]
    private let resolveLocalGateway: @Sendable (_ configuredPath: String?) -> String?
    private let sshBinary: String

    public init(
        runner: any CAAMEnvironmentCommandRunning = DefaultCAAMEnvironmentCommandRunner(),
        environment: [String: String] = ProcessInfo.processInfo.environment,
        resolveLocalGateway: (@Sendable (_ configuredPath: String?) -> String?)? = nil,
        sshBinary: String = Self.defaultSSHBinary)
    {
        self.runner = runner
        self.environment = environment
        self.resolveLocalGateway = resolveLocalGateway ?? { configuredPath in
            Self.resolveLocalGateway(configuredPath: configuredPath, environment: environment)
        }
        self.sshBinary = sshBinary
    }

    public func fetchSnapshot(for configuration: CAAMEnvironmentConfiguration) async throws
        -> CAAMEnvironmentSnapshot
    {
        let operation = CAAMGatewayOperation.snapshot(environmentID: configuration.id)
        let command = try self.command(for: configuration, operation: operation)
        let result: SubprocessResult
        do {
            result = try await self.runner.run(command: command, environment: self.environment)
        } catch is CancellationError {
            throw CAAMEnvironmentClientError.cancelled
        } catch let error as SubprocessRunnerError {
            switch error {
            case .binaryNotFound: throw CAAMEnvironmentClientError.binaryUnavailable
            case .timedOut: throw CAAMEnvironmentClientError.timedOut
            case .outputTooLarge: throw CAAMEnvironmentClientError.responseTooLarge
            case .launchFailed, .nonZeroExit: throw CAAMEnvironmentClientError.commandFailed
            }
        } catch {
            throw CAAMEnvironmentClientError.commandFailed
        }
        return try CAAMEnvironmentContract.decodeSnapshot(
            Data(result.stdout.utf8),
            expectedEnvironmentID: configuration.id)
    }

    public func command(
        for configuration: CAAMEnvironmentConfiguration,
        operation: CAAMGatewayOperation) throws -> CAAMEnvironmentCommand
    {
        _ = try CAAMEnvironmentContract.validateConfigurations([configuration])
        guard operation.environmentID == configuration.id else {
            throw CAAMEnvironmentContractError.invalidConfiguration(
                "The CAAM operation targeted another environment.")
        }
        let gatewayArguments = try operation.gatewayArguments()
        switch configuration.connection.kind {
        case .local:
            guard let binary = self.resolveLocalGateway(configuration.connection.executablePath) else {
                throw CAAMEnvironmentClientError.binaryUnavailable
            }
            return CAAMEnvironmentCommand(
                binary: binary,
                arguments: gatewayArguments,
                timeout: Self.defaultTimeout,
                maximumOutputBytes: CAAMEnvironmentContract.maximumOutputBytes,
                label: "CAAM environment operation")
        case .ssh:
            guard let destination = configuration.connection.sshDestination else {
                throw CAAMEnvironmentContractError.invalidConfiguration("The CAAM SSH destination is missing.")
            }
            return CAAMEnvironmentCommand(
                binary: self.sshBinary,
                arguments: [
                    "-o", "BatchMode=yes",
                    "-o", "RequestTTY=no",
                    "-o", "ClearAllForwardings=yes",
                    "-o", "ConnectTimeout=5",
                    destination,
                    Self.defaultGatewayName,
                ] + gatewayArguments,
                timeout: Self.defaultTimeout,
                maximumOutputBytes: CAAMEnvironmentContract.maximumOutputBytes,
                label: "CAAM environment operation")
        }
    }

    public static func resolveLocalGateway(
        configuredPath: String?,
        environment: [String: String] = ProcessInfo.processInfo.environment,
        fileManager: FileManager = .default) -> String?
    {
        if let configuredPath {
            return fileManager.isExecutableFile(atPath: configuredPath) ? configuredPath : nil
        }
        let path = environment["PATH"] ?? "/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin"
        return path.split(separator: ":")
            .map { String($0) + "/" + Self.defaultGatewayName }
            .first { fileManager.isExecutableFile(atPath: $0) }
    }
}
