import CodexBarCore
import Foundation
import Testing
@testable import CodexBarCLI

struct CLIProviderSelectionTests {
    @Test
    func `help lists retained providers and shared output controls`() {
        for help in [CodexBarCLI.rootHelp(version: "0.0.0"), CodexBarCLI.usageHelp(version: "0.0.0")] {
            #expect(help.contains("--provider codex|claude|both|all"))
            for flag in ["--json", "--json-only", "--json-output", "--log-level", "--verbose"] {
                #expect(help.contains(flag))
            }
        }
    }

    @Test(arguments: ["cursor", "gemini", "fixture-plugin"])
    func `retired provider overrides cannot select a different enabled account`(rawID: String) {
        #expect(ProviderSelection(argument: rawID) == nil)
        #expect(CodexBarCLI.providerSelection(rawOverride: rawID, enabled: [.codex, .claude]).asList.isEmpty)
    }

    @Test
    func `help mentions source flag`() {
        let usage = CodexBarCLI.usageHelp(version: "0.0.0")
        let root = CodexBarCLI.rootHelp(version: "0.0.0")

        func tokens(_ text: String) -> [String] {
            let split = CharacterSet.whitespacesAndNewlines.union(CharacterSet(charactersIn: "[]|,"))
            return text.components(separatedBy: split).filter { !$0.isEmpty }
        }

        #expect(usage.contains("--source"))
        #expect(root.contains("--source"))
        #expect(usage.contains("--web-timeout"))
        #expect(usage.contains("--web-debug-dump-html"))
        #expect(!tokens(usage).contains("--web"))
        #expect(!tokens(root).contains("--web"))
        #expect(!tokens(usage).contains("--claude-source"))
        #expect(!tokens(root).contains("--claude-source"))
    }

    @Test
    func `help advertises the toon output format`() {
        let usage = CodexBarCLI.usageHelp(version: "0.0.0")
        let root = CodexBarCLI.rootHelp(version: "0.0.0")

        #expect(usage.contains("--format text|json|toon"))
        #expect(root.contains("--format text|json|toon"))
        #expect(usage.contains("codexbar usage --format toon"))
        #expect(root.contains("codexbar --format toon"))
    }

    @Test
    func `provider selection respects override`() {
        let selection = CodexBarCLI.providerSelection(rawOverride: "claude", enabled: [.codex, .claude])
        #expect(selection.asList == [.claude])
    }

    @Test
    func `provider selection uses both for codex and claude`() {
        let selection = CodexBarCLI.providerSelection(rawOverride: nil, enabled: [.codex, .claude])
        #expect(selection.asList == [.codex, .claude])
    }

    @Test
    func `provider selection honors empty enabled set`() {
        let selection = CodexBarCLI.providerSelection(rawOverride: nil, enabled: [])
        #expect(selection.asList == [])
    }
}
