import CryptoKit
import Foundation
import Security

// The P12 password stays in process memory. The caller supplies only an owned ephemeral keychain.
func importIdentity() throws -> String {
    guard CommandLine.arguments.count == 3,
          let password = ProcessInfo.processInfo.environment["MACOS_SIGNING_CERTIFICATE_PASSWORD"],
          !password.isEmpty
    else { throw NSError(domain: "JonesImport", code: 1) }
    let archive = try Data(contentsOf: URL(fileURLWithPath: CommandLine.arguments[1]))
    var keychain: SecKeychain?
    guard SecKeychainOpen(CommandLine.arguments[2], &keychain) == errSecSuccess, let keychain else {
        throw NSError(domain: "JonesImport", code: 2)
    }
    let options: [String: Any] = [
        kSecImportExportPassphrase as String: password,
        kSecImportExportKeychain as String: keychain,
    ]
    var imported: CFArray?
    guard SecPKCS12Import(archive as CFData, options as CFDictionary, &imported) == errSecSuccess,
          let items = imported as? [[String: Any]], items.count == 1,
          let value = items[0][kSecImportItemIdentity as String],
          CFGetTypeID(value as CFTypeRef) == SecIdentityGetTypeID()
    else { throw NSError(domain: "JonesImport", code: 3) }
    let identity = value as! SecIdentity
    var certificate: SecCertificate?
    guard SecIdentityCopyCertificate(identity, &certificate) == errSecSuccess, let certificate,
          let name = SecCertificateCopySubjectSummary(certificate) as String?,
          name.hasPrefix("Developer ID Application: "), name.hasSuffix(" (2CUPSQS986)")
    else { throw NSError(domain: "JonesImport", code: 4) }
    return Insecure.SHA1.hash(data: SecCertificateCopyData(certificate) as Data)
        .map { String(format: "%02X", $0) }.joined()
}

do {
    print(try importIdentity())
} catch {
    // Security errors may contain protected input; emit no imported objects or descriptions.
    FileHandle.standardError.write(Data("Jones identity import refused.\n".utf8))
    exit(1)
}
