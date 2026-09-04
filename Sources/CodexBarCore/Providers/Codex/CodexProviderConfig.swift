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

    public var codexCAAMEnvironments: [CAAMEnvironmentConfiguration]? {
        get { self.extensionValue(forKey: "codexCAAMEnvironments") }
        set { self.setExtensionValue(newValue, forKey: "codexCAAMEnvironments") }
    }
}
