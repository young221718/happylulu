import AppPluginCore
import AppPluginHost

public enum KeepAwakeModule: PluginModule {
    public static let id = "keep-awake"
    public static var catalogMetadata: PluginModuleMetadata? {
        PluginModuleMetadata(name: "화면 꺼짐 방지", englishName: "Keep Display Awake", author: PluginAuthors.contributors,
            summary: "사용 중 화면 자동 꺼짐 방지", englishSummary: "Keep the display awake while enabled", symbol: "sun.max")
    }
    @MainActor public static func register(in context: PluginHostContext) throws {
        try registerUtility(id: id, metadata: catalogMetadata!, driver: KeepAwakeDriver(), in: context)
    }
}

public enum ScrollReverseModule: PluginModule {
    public static let id = "scroll-reverse"
    public static var catalogMetadata: PluginModuleMetadata? {
        PluginModuleMetadata(name: "마우스 스크롤 반전", englishName: "Reverse Mouse Scrolling", author: PluginAuthors.contributors,
            summary: "마우스 휠만 반전 · 트랙패드 유지", englishSummary: "Reverse mouse wheels · keep trackpad scrolling", symbol: "computermouse")
    }
    @MainActor public static func register(in context: PluginHostContext) throws {
        try registerUtility(id: id, metadata: catalogMetadata!, driver: ScrollReverseDriver(), in: context)
    }
}

@MainActor
private func registerUtility(id: String, metadata: PluginModuleMetadata, driver: any UtilityDriver,
                             in context: PluginHostContext) throws {
    let controller = UtilityController(id: id, driver: driver)
    let adapter = SnapshotFeatureAdapter(descriptor: FeatureAdapterDescriptor(id: id, name: metadata.englishName, features: []),
        api: context.registry, timeZone: .current)
    try context.register(PluginRegistration(controller: controller, adapter: adapter, symbol: metadata.symbol,
        summary: metadata.summary, englishSummary: metadata.englishSummary, setEnabled: controller.setEnabled))
    try context.presentations.register(id) {
        UtilitySettingsView(model: controller, isScroll: id == ScrollReverseModule.id, localize: context.localize)
    }
}
