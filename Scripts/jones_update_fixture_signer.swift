import CryptoKit
import Foundation

// CI-only fixture signer. The throwaway private key exists only in this process's memory.
// Production signing and Keychain APIs are deliberately outside this executable.
struct Request: Decodable {
    let path: String
    let wrongKey: Bool
}

func emit(_ value: [String: String]) throws {
    let data = try JSONSerialization.data(withJSONObject: value, options: [.sortedKeys])
    FileHandle.standardOutput.write(data + Data([10]))
}

do {
    guard ProcessInfo.processInfo.environment["GITHUB_ACTIONS"] == "true",
          ProcessInfo.processInfo.environment["RUNNER_ENVIRONMENT"] == "github-hosted",
          CommandLine.arguments.count == 2
    else { exit(78) }
    let root = URL(fileURLWithPath: CommandLine.arguments[1]).resolvingSymlinksInPath()
    let key = Curve25519.Signing.PrivateKey()
    let wrongKey = Curve25519.Signing.PrivateKey()
    try emit(["publicKey": key.publicKey.rawRepresentation.base64EncodedString()])
    while let line = readLine() {
        guard let encoded = line.data(using: .utf8), encoded.count <= 4096 else { exit(78) }
        let request = try JSONDecoder().decode(Request.self, from: encoded)
        let url = URL(fileURLWithPath: request.path).resolvingSymlinksInPath()
        guard url.path.hasPrefix(root.path + "/"),
              let size = try url.resourceValues(forKeys: [.fileSizeKey]).fileSize,
              size > 0, size <= 256 * 1024 * 1024
        else { exit(78) }
        let data = try Data(contentsOf: url, options: .mappedIfSafe)
        let signature = try (request.wrongKey ? wrongKey : key).signature(for: data)
        try emit(["signature": signature.base64EncodedString()])
    }
} catch {
    FileHandle.standardError.write(Data("Fixture signing failed.\n".utf8))
    exit(1)
}
