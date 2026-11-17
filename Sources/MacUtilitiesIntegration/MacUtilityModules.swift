import AppPluginCore
import AppPluginHost

public enum KeepAwakeModule: PluginModule {
    public static let id = "keep-awake"
    public static var catalogMetadata: PluginModuleMetadata? {
        PluginModuleMetadata(name: "화면 꺼짐 방지", englishName: "Keep Display Awake", author: PluginAuthors.contributors,
            summary: "시간·유지 범위 선택과 부엉이 상태 제어", englishSummary: "Timed display or system wake requests with owl control", symbol: "sun.max")
    }
    @MainActor public static func register(in context: PluginHostContext) throws {
        let controller = KeepAwakeController(localize: context.localize)
        let adapter = SnapshotFeatureAdapter(descriptor: FeatureAdapterDescriptor(id: id, name: "Keep Awake", features: []),
            api: context.registry, timeZone: .current)
        let metadata = catalogMetadata!
        try context.register(PluginRegistration(controller: controller, adapter: adapter, symbol: metadata.symbol,
            summary: metadata.summary, englishSummary: metadata.englishSummary, setEnabled: controller.setEnabled))
        try context.presentations.register(id) { KeepAwakeSettingsView(model: controller) }
    }
}

public enum ScrollReverseModule: PluginModule {
    public static let id = "scroll-reverse"
    public static var catalogMetadata: PluginModuleMetadata? {
        PluginModuleMetadata(name: "마우스 스크롤 반전", englishName: "Reverse Mouse Scrolling", author: PluginAuthors.contributors,
            summary: "일반 휠 반전 · 연속·관성 스크롤 유지", englishSummary: "Reverse line wheels · preserve continuous and momentum scrolling", symbol: "computermouse")
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
