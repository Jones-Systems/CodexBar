import Foundation

extension ProviderConfig {
    public var codexActiveSource: CodexActiveSource? {
        get { self.extensionValue(forKey: "codexActiveSource") }
        set { self.setExtensionValue(newValue, forKey: "codexActiveSource") }
    }

    public var codexProfileHomePaths: [String]? {
        get { self.extensionValue(forKey: "codexProfileHomePaths") }
        set { self.setExtensionValue(newValue, forKey: "codexProfileHomePaths") }
    }

    public var codexAccountOrder: [String]? {
        get { self.extensionValue(forKey: "codexAccountOrder") }
        set { self.setExtensionValue(newValue, forKey: "codexAccountOrder") }
    }
}
