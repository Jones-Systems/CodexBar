import AppKit
import CodexBarCore
import CoreFoundation
import Darwin
import Foundation
import Security

/// This command runs before application construction and never starts provider or CloudKit services.
@MainActor
enum JonesBootstrapCommand {
    static let flag = "--jones-bootstrap"

    static func isRequested(_ arguments: [String]) -> Bool {
        arguments.dropFirst().contains(self.flag)
    }

    static func permitsNormalLaunch(marker: [String: Any]?, target: String) -> Bool {
        guard let marker else { return true }
        return marker["schema"] as? String == "jones-bootstrap-install/v1"
            && marker["target"] as? String == target
            && marker["phase"] as? String == "launch-attempted"
    }

    static func admitNormalLaunch() -> Bool {
        guard Bundle.main.object(forInfoDictionaryKey: "JonesSigningMode") as? String == "developer-id" else {
            return true
        }
        let target = Bundle.main.bundleURL.standardizedFileURL
        let suffix = JonesBootstrapMigration.digest(Data(target.path.utf8)).prefix(16)
        let root = target.deletingLastPathComponent().appendingPathComponent(
            ".codexbar-jones-install-\(suffix).noindex.bootstrap")
        do {
            try JonesBootstrapNativeStorage.checkComponents(root)
            var info = stat()
            if lstat(root.path, &info) != 0 { return errno == ENOENT }
            try JonesBootstrapNativeStorage.privateDirectory(root)
            let data = try JonesBootstrapNativeStorage.privateFile(root.appendingPathComponent("installed.json"))
            guard let marker = try JSONSerialization.jsonObject(with: data) as? [String: Any] else { return false }
            return self.permitsNormalLaunch(marker: marker, target: target.path)
        } catch {
            return false
        }
    }

    static func withKeychainDisabled(
        disable: () -> Void,
        operation: () -> Int32) -> Int32
    {
        disable()
        return operation()
    }

    static func run(_ arguments: [String]) -> Int32 {
        self.withKeychainDisabled(disable: {
            // Set the environment first: the process gate observes its prior policy under its lock.
            setenv("CODEXBAR_DISABLE_KEYCHAIN_ACCESS", "1", 1)
            KeychainAccessGate.forceDisabledForProcess(reason: "jones-bootstrap")
        }, operation: { self.execute(arguments) })
    }

    private static func execute(_ arguments: [String]) -> Int32 {
        do {
            guard arguments.count == 7, arguments[1] == self.flag,
                  ["prepare", "resume", "verify", "verify-installed"].contains(arguments[2]),
                  arguments[3] == "--request", arguments[5] == "--receipt"
            else { throw JonesBootstrapMigration.Failure.invalid }
            let requestURL = URL(fileURLWithPath: arguments[4])
            let receiptURL = URL(fileURLWithPath: arguments[6])
            guard requestURL.deletingLastPathComponent() == receiptURL.deletingLastPathComponent(),
                  requestURL.lastPathComponent == "request.json", receiptURL.lastPathComponent == "receipt.json"
            else { throw JonesBootstrapMigration.Failure.invalid }
            try JonesBootstrapNativeStorage.privateDirectory(receiptURL.deletingLastPathComponent())
            let lockURL = receiptURL.deletingLastPathComponent().appendingPathComponent("data.lock")
            let descriptor = open(lockURL.path, O_CREAT | O_RDWR | O_NOFOLLOW, 0o600)
            guard descriptor >= 0 else { throw JonesBootstrapMigration.Failure.unavailable }
            defer { close(descriptor) }
            var lockInfo = stat()
            guard fstat(descriptor, &lockInfo) == 0, lockInfo.st_uid == getuid(),
                  lockInfo.st_nlink == 1, lockInfo.st_mode & 0o077 == 0,
                  lockInfo.st_mode & S_IFMT == S_IFREG, flock(descriptor, LOCK_EX | LOCK_NB) == 0
            else { throw JonesBootstrapMigration.Failure.unavailable }
            let request = try JSONDecoder().decode(
                JonesBootstrapMigration.Request.self,
                from: JonesBootstrapNativeStorage.privateFile(requestURL))
            try request.validate()
            guard request.uid == getuid(), Bundle.main.bundleIdentifier == JonesBootstrapMigration.bundle,
                  Bundle.main.object(forInfoDictionaryKey: "JonesSourceRevision") as? String == request.revision,
                  Bundle.main.object(forInfoDictionaryKey: "JonesStateKey") as? String == "jones",
                  Bundle.main.object(forInfoDictionaryKey: "JonesSigningMode") as? String == "developer-id",
                  !NSWorkspace.shared.runningApplications.contains(where: {
                      $0.processIdentifier != getpid() && $0.bundleIdentifier == JonesBootstrapMigration.bundle
                  })
            else { throw JonesBootstrapMigration.Failure.invalid }
            try self.checkSignature(Bundle.main.bundleURL, production: true)
            let oldURL = arguments[2] == "verify-installed"
                ? receiptURL.deletingLastPathComponent().appendingPathComponent("legacy.app")
                : URL(fileURLWithPath: request.target)
            try self.checkSignature(oldURL, production: false)
            let storage = try JonesBootstrapNativeStorage(receiptURL: receiptURL)
            switch arguments[2] {
            case "prepare":
                guard try JonesBootstrapNativeStorage.readFile(receiptURL) == nil else {
                    throw JonesBootstrapMigration.Failure.invalid
                }
                _ = try JonesBootstrapMigration.prepare(request, storage: storage)
            case "resume", "verify", "verify-installed":
                let receipt = try JSONDecoder().decode(
                    JonesBootstrapMigration.Receipt.self,
                    from: JonesBootstrapNativeStorage.privateFile(receiptURL))
                guard receipt.plan.request == request else { throw JonesBootstrapMigration.Failure.invalid }
                if arguments[2] == "resume" {
                    _ = try JonesBootstrapMigration.prepare(request, storage: storage, resume: receipt)
                } else if arguments[2] == "verify-installed" {
                    guard receipt.phase == "installed" else { throw JonesBootstrapMigration.Failure.invalid }
                    try JonesBootstrapMigration.verifyData(receipt, storage: storage)
                } else {
                    _ = try JonesBootstrapMigration.verify(receipt, storage: storage)
                }
            default: throw JonesBootstrapMigration.Failure.invalid
            }
            return 0
        } catch {
            // Private payloads and filesystem errors stay out of stdout/stderr and CI artifacts.
            let message = "Jones bootstrap refused; preserve its private journal for exact reconciliation.\n"
            FileHandle.standardError.write(Data(message.utf8))
            return 2
        }
    }

    private static func checkSignature(_ url: URL, production: Bool) throws {
        var requirement: SecRequirement?
        if production {
            let text = "identifier \"com.jonessystems.codexbar\" and anchor apple generic "
                + "and certificate 1[field.1.2.840.113635.100.6.2.6] exists "
                + "and certificate leaf[field.1.2.840.113635.100.6.1.13] exists "
                + "and certificate leaf[subject.OU] = \"2CUPSQS986\""
            guard SecRequirementCreateWithString(text as CFString, [], &requirement) == errSecSuccess else {
                throw JonesBootstrapMigration.Failure.invalid
            }
        }
        var code: SecStaticCode?
        guard SecStaticCodeCreateWithPath(url as CFURL, [], &code) == errSecSuccess, let code,
              SecStaticCodeCheckValidity(
                  code,
                  SecCSFlags(rawValue: kSecCSStrictValidate | kSecCSCheckAllArchitectures | kSecCSCheckNestedCode),
                  requirement) == errSecSuccess
        else { throw JonesBootstrapMigration.Failure.invalid }
        var information: CFDictionary?
        guard SecCodeCopySigningInformation(code, SecCSFlags(rawValue: kSecCSSigningInformation), &information)
            == errSecSuccess,
            let info = information as? [String: Any],
            info[kSecCodeInfoIdentifier as String] as? String == JonesBootstrapMigration.bundle,
            let entitlements = info[kSecCodeInfoEntitlementsDict as String] as? [String: Any]
        else { throw JonesBootstrapMigration.Failure.invalid }
        let group = production ? JonesBootstrapMigration.newGroup : JonesBootstrapMigration.oldGroup
        guard entitlements["com.apple.security.application-groups"] as? [String] == [group],
              let flags = info[kSecCodeInfoFlags as String] as? UInt32,
              production ? (info[kSecCodeInfoTeamIdentifier as String] as? String == "2CUPSQS986"
                  && flags & 0x10000 != 0 && flags & 2 == 0)
              : (info[kSecCodeInfoTeamIdentifier as String] == nil && flags & 2 != 0)
        else { throw JonesBootstrapMigration.Failure.invalid }
    }
}

private struct JonesBootstrapNativeStorage: JonesBootstrapMigration.Storage {
    let receiptURL: URL
    let oldContainer: URL
    let destination: URL
    let fallback: URL
    let standard: URL

    init(receiptURL: URL) throws {
        let manager = FileManager.default
        let home = manager.homeDirectoryForCurrentUser
        guard let destination = manager.containerURL(
            forSecurityApplicationGroupIdentifier: JonesBootstrapMigration.newGroup)
        else { throw JonesBootstrapMigration.Failure.unavailable }
        self.receiptURL = receiptURL
        self.destination = destination
        self.oldContainer = home.appendingPathComponent("Library/Group Containers/" + JonesBootstrapMigration.oldGroup)
        self.fallback = home.appendingPathComponent("Library/Application Support/CodexBar Jones/widget-snapshot.json")
        self.standard = home.appendingPathComponent("Library/Preferences/" + JonesBootstrapMigration.bundle + ".plist")
    }

    static func privateDirectory(_ url: URL) throws {
        try self.checkComponents(url)
        var info = stat()
        guard lstat(url.path, &info) == 0, info.st_mode & S_IFMT == S_IFDIR,
              info.st_uid == getuid(), info.st_mode & 0o077 == 0
        else { throw JonesBootstrapMigration.Failure.unavailable }
    }

    static func privateFile(_ url: URL) throws -> Data {
        var info = stat()
        guard lstat(url.path, &info) == 0, info.st_uid == getuid(), info.st_mode & 0o077 == 0,
              info.st_nlink == 1, let data = try self.readFile(url)
        else { throw JonesBootstrapMigration.Failure.unavailable }
        return data
    }

    static func checkComponents(_ url: URL) throws {
        guard url.path == url.standardizedFileURL.path else { throw JonesBootstrapMigration.Failure.invalid }
        var path = URL(fileURLWithPath: "/")
        for component in url.pathComponents.dropFirst() {
            path.appendPathComponent(component)
            var info = stat()
            if lstat(path.path, &info) != 0 {
                guard errno == ENOENT else { throw JonesBootstrapMigration.Failure.unavailable }
                // Listing the nearest existing parent proves that absence was observable, not denied.
                _ = try FileManager.default.contentsOfDirectory(atPath: path.deletingLastPathComponent().path)
                return
            }
            guard info.st_mode & S_IFMT != S_IFLNK else { throw JonesBootstrapMigration.Failure.invalid }
        }
    }

    static func readFile(_ url: URL) throws -> Data? {
        try self.checkComponents(url)
        let descriptor = open(url.path, O_RDONLY | O_NOFOLLOW)
        if descriptor < 0 {
            guard errno == ENOENT else { throw JonesBootstrapMigration.Failure.unavailable }
            return nil
        }
        let handle = FileHandle(fileDescriptor: descriptor, closeOnDealloc: true)
        defer { try? handle.close() }
        var info = stat()
        guard fstat(descriptor, &info) == 0, info.st_mode & S_IFMT == S_IFREG,
              info.st_uid == getuid(), info.st_nlink == 1, info.st_size <= 16 * 1024 * 1024
        else { throw JonesBootstrapMigration.Failure.unavailable }
        return try handle.readToEnd() ?? Data()
    }

    private func domain(_ name: String, file: URL) throws -> [String: Any] {
        let disk = try Self.readFile(file)
        var persisted: [String: Any] = [:]
        if let disk {
            guard let decoded = try PropertyListSerialization.propertyList(from: disk, format: nil) as? [String: Any]
            else {
                throw JonesBootstrapMigration.Failure.invalid
            }
            persisted = decoded
        }
        // persistentDomain excludes registered, argument, global and other-suite search domains.
        guard let defaults = UserDefaults(suiteName: name) else {
            throw JonesBootstrapMigration.Failure.unavailable
        }
        let values = defaults.persistentDomain(forName: name)
        guard NSDictionary(dictionary: values ?? [:]).isEqual(to: persisted) else {
            throw JonesBootstrapMigration.Failure.unavailable
        }
        return values ?? [:]
    }

    private func preference(_ value: Any?, key: String) throws -> Data? {
        guard let value else { return nil }
        let valid: Bool = switch key {
        case "debugDisableKeychainAccess":
            (value as? NSNumber).map { CFGetTypeID($0) == CFBooleanGetTypeID() } ?? false
        case "widgetSelectedProvider": value is String
        case "providerAccentColors": value is [String: String]
        default: false
        }
        guard valid else { throw JonesBootstrapMigration.Failure.invalid }
        return try JSONSerialization.data(withJSONObject: value, options: [.sortedKeys, .fragmentsAllowed])
    }

    private func snapshot(_ url: URL) throws -> Data? {
        guard let data = try Self.readFile(url) else { return nil }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        _ = try decoder.decode(WidgetSnapshot.self, from: data)
        return data
    }

    func read() throws -> JonesBootstrapMigration.Inventory {
        let oldFile = self.oldContainer.appendingPathComponent(
            "Library/Preferences/" + JonesBootstrapMigration.oldGroup + ".plist")
        let newFile = self.destination.appendingPathComponent(
            "Library/Preferences/" + JonesBootstrapMigration.newGroup + ".plist")
        let old = try self.domain(JonesBootstrapMigration.oldGroup, file: oldFile)
        let new = try self.domain(JonesBootstrapMigration.newGroup, file: newFile)
        let local = try self.domain(JonesBootstrapMigration.bundle, file: self.standard)
        var sources: [String: Data] = [:]
        var target: [String: Data] = [:]
        for key in JonesBootstrapMigration.preferences {
            sources[key] = try self.preference(old[key], key: key)
            target[key] = try self.preference(new[key], key: key)
        }
        sources["localPolicy"] = try self.preference(
            local["debugDisableKeychainAccess"],
            key: "debugDisableKeychainAccess")
        sources["oldSnapshot"] = try self
            .snapshot(self.oldContainer.appendingPathComponent(JonesBootstrapMigration.snapshot))
        sources["fallbackSnapshot"] = try self.snapshot(self.fallback)
        target[JonesBootstrapMigration.snapshot] = try self.snapshot(
            self.destination.appendingPathComponent(JonesBootstrapMigration.snapshot))
        return .init(
            locations: [
                "old": self.oldContainer.path,
                "destination": self.destination.path,
                "fallback": self.fallback.path,
                "standard": self.standard.path,
            ],
            sources: sources,
            destination: target)
    }

    func write(_ value: Data, key: String) throws {
        if key == JonesBootstrapMigration.snapshot {
            let url = self.destination.appendingPathComponent(key)
            guard try Self.readFile(url) == nil else { throw JonesBootstrapMigration.Failure.drift }
            try value.write(to: url, options: [.withoutOverwriting])
            let handle = try FileHandle(forWritingTo: url)
            defer { try? handle.close() }
            try handle.synchronize()
            try Self.synchronizeDirectory(self.destination)
        } else {
            guard JonesBootstrapMigration.preferences.contains(key)
            else { throw JonesBootstrapMigration.Failure.invalid }
            let object = try JSONSerialization.jsonObject(with: value, options: [.fragmentsAllowed])
            CFPreferencesSetValue(
                key as CFString,
                object as CFPropertyList,
                JonesBootstrapMigration.newGroup as CFString,
                kCFPreferencesCurrentUser,
                kCFPreferencesAnyHost)
            guard CFPreferencesAppSynchronize(JonesBootstrapMigration.newGroup as CFString) else {
                throw JonesBootstrapMigration.Failure.unavailable
            }
        }
    }

    func save(_ receipt: JonesBootstrapMigration.Receipt) throws {
        try Self.privateDirectory(self.receiptURL.deletingLastPathComponent())
        if try Self.readFile(self.receiptURL) != nil { _ = try Self.privateFile(self.receiptURL) }
        let data = try JonesBootstrapMigration.encode(receipt)
        try data.write(to: self.receiptURL, options: [.atomic])
        guard chmod(self.receiptURL.path, 0o600) == 0 else { throw JonesBootstrapMigration.Failure.unavailable }
        let handle = try FileHandle(forWritingTo: self.receiptURL)
        defer { try? handle.close() }
        try handle.synchronize()
        try Self.synchronizeDirectory(self.receiptURL.deletingLastPathComponent())
    }

    private static func synchronizeDirectory(_ url: URL) throws {
        let directory = open(url.path, O_RDONLY)
        guard directory >= 0 else { throw JonesBootstrapMigration.Failure.unavailable }
        defer { close(directory) }
        guard fsync(directory) == 0 else { throw JonesBootstrapMigration.Failure.unavailable }
    }
}
