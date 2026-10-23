import Foundation
import AppPluginCore
import AppPluginHost

public enum CPURunnerModule: PluginModule {
    public static let id = "cpu-runner"

    @MainActor
    public static func register(in context: PluginHostContext) throws {
        let controller = CPURunnerController(localize: context.localize)
        try context.register(PluginRegistration(controller: controller, adapter: RunnerFeatureAdapter(),
            symbol: "pawprint", summary: "부엉이 눈빛과 CPU · 메모리 · 디스크 · 네트워크 · 배터리",
            englishSummary: "An owl orbit with CPU, memory, disk, network and battery metrics", setEnabled: controller.setModuleEnabled))
        let localize = context.localize
        try context.presentations.register(id) { CPURunnerSettingsView(model: controller, localize: localize) }
    }
}

@MainActor
private final class RunnerFeatureAdapter: FeatureAdapter {
    let descriptor = FeatureAdapterDescriptor(id: CPURunnerModule.id, name: "System Runner", features: [])
    func calendarEvents(in interval: DateInterval) async throws -> [FeatureCalendarEvent] { [] }
    func leaveSnapshot() -> PluginSnapshot? { nil }
    func requestHalfDayAccess() async throws { throw FeatureAdapterFailure.unsupported }
    func halfDayTitles(on day: Date, timeZone: TimeZone) async throws -> [String] { [] }
}
