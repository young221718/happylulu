import SwiftUI
import AppPluginHost

public enum RunnerMetricsFormatter {
    public static func bytes(_ value: UInt64, memory: Bool = false) -> String {
        let formatter = ByteCountFormatter()
        formatter.countStyle = memory ? .memory : .file
        formatter.allowsNonnumericFormatting = false
        return formatter.string(fromByteCount: Int64(clamping: value))
    }

    public static func rate(_ value: Double?) -> String {
        guard let value, value.isFinite, value >= 0, value < Double(Int64.max) else { return "—" }
        return bytes(UInt64(value.rounded())) + "/s"
    }

    @MainActor
    public static func pressure(_ value: MemoryPressure?, localize: PluginLocalizer) -> String {
        switch value {
        case .normal: return localize("정상", "Normal")
        case .warning: return localize("주의", "Warning")
        case .critical: return localize("위험", "Critical")
        case nil: return "—"
        }
    }

    @MainActor
    public static func batteryState(_ value: BatteryMetrics?, localize: PluginLocalizer) -> String {
        guard let value else { return "—" }
        guard value.presence == .present else { return localize("배터리 없음", "No battery") }
        if value.isCharging == true { return localize("충전 중", "Charging") }
        if value.isExternalPower == true { return localize("외부 전원", "External power") }
        if value.isExternalPower == false { return localize("배터리 사용", "On battery") }
        return "—"
    }

    public static func batteryCharge(_ value: BatteryMetrics?) -> String {
        guard let value, value.presence == .present, let percent = value.percent,
              percent.isFinite, (0...100).contains(percent) else { return "—" }
        return "\(Int(percent.rounded()))%"
    }

    @MainActor
    public static func networkState(_ value: NetworkMetrics?, localize: PluginLocalizer) -> String {
        guard let value else { return "—" }
        guard value.isConnected else { return localize("연결 안 됨", "Disconnected") }
        return value.interfaceNames.joined(separator: ", ")
    }
}

public struct RunnerMetricsSummaryView: View {
    @ObservedObject private var model: CPURunnerController
    private let localize: PluginLocalizer

    public init(model: CPURunnerController, localize: @escaping PluginLocalizer) {
        self.model = model; self.localize = localize
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            Text(localize("시스템 러너", "System Runner"))
                .font(.system(size: 11, weight: .semibold)).foregroundStyle(.secondary)
            row("CPU", value: model.usageText)
            row(localize("메모리", "Memory"), value: memoryText)
            row(localize("시동 디스크", "Startup disk"), value: storageText)
            row(localize("네트워크", "Network"), value: networkText)
                .help(localize("물리 인터페이스: ", "Physical interfaces: ")
                    + RunnerMetricsFormatter.networkState(model.metrics.network, localize: localize)
                    + localize(" · 인터넷 접속 확인 아님", " · Internet access is not verified"))
            row(localize("배터리", "Battery"), value: batteryText)
        }
        .padding(10).frame(maxWidth: .infinity, minHeight: 172, maxHeight: 172, alignment: .topLeading)
        .background(Color.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: 10))
    }

    private func row(_ label: String, value: String) -> some View {
        HStack(spacing: 8) {
            Text(label).foregroundStyle(.secondary).frame(width: 68, alignment: .leading)
            Text(value).monospacedDigit().frame(maxWidth: .infinity, alignment: .trailing)
        }
        .font(.system(size: 11)).lineLimit(1).frame(height: 20)
        .accessibilityElement(children: .combine)
    }

    private var memoryText: String {
        guard let memory = model.metrics.memory else { return "—" }
        let capacity = RunnerMetricsFormatter.bytes(memory.usedBytes, memory: true)
            + " / " + RunnerMetricsFormatter.bytes(memory.totalBytes, memory: true)
        guard memory.pressure != nil else { return capacity }
        return capacity + " · " + RunnerMetricsFormatter.pressure(memory.pressure, localize: localize)
    }
    private var storageText: String {
        guard let storage = model.metrics.storage else { return "—" }
        return RunnerMetricsFormatter.bytes(storage.availableBytes)
            + localize(" 여유 / ", " free / ") + RunnerMetricsFormatter.bytes(storage.totalBytes)
    }
    private var networkText: String {
        guard let network = model.metrics.network else { return "—" }
        guard network.isConnected else { return RunnerMetricsFormatter.networkState(network, localize: localize) }
        return network.interfaceNames.joined(separator: ", ") + " · ↓ " + RunnerMetricsFormatter.rate(network.receivedBytesPerSecond)
            + "  ↑ " + RunnerMetricsFormatter.rate(network.sentBytesPerSecond)
    }
    private var batteryText: String {
        let state = RunnerMetricsFormatter.batteryState(model.metrics.battery, localize: localize)
        guard model.metrics.battery?.presence == .present else { return state }
        return RunnerMetricsFormatter.batteryCharge(model.metrics.battery) + " · " + state
    }
}

struct RunnerMetricsDetailView: View {
    @ObservedObject var model: CPURunnerController
    let localize: PluginLocalizer

    var body: some View {
        VStack(spacing: 14) {
            row(localize("CPU 사용량", "CPU usage"), value: model.usageText,
                detail: localize("1초마다 갱신", "Updates every second"))
            Divider()
            row(localize("메모리", "Memory"), value: memoryCapacity,
                detail: localize("메모리 압력: ", "Memory pressure: ")
                    + RunnerMetricsFormatter.pressure(model.metrics.memory?.pressure, localize: localize))
            Divider()
            row(localize("시동 디스크", "Startup disk"), value: storageCapacity,
                detail: localize("정리 가능한 공간 포함", "Includes purgeable space"))
            Divider()
            row(localize("네트워크", "Network"), value: networkRates,
                detail: RunnerMetricsFormatter.networkState(model.metrics.network, localize: localize))
            Divider()
            row(localize("배터리", "Battery"), value: RunnerMetricsFormatter.batteryCharge(model.metrics.battery),
                detail: RunnerMetricsFormatter.batteryState(model.metrics.battery, localize: localize))
        }
    }

    private func row(_ label: String, value: String, detail: String) -> some View {
        HStack(spacing: 12) {
            Text(label).frame(width: 112, alignment: .leading)
            Text(value).font(.caption).monospacedDigit().multilineTextAlignment(.center)
                .frame(maxWidth: .infinity)
            Text(detail).font(.caption).foregroundStyle(.secondary).multilineTextAlignment(.trailing)
                .frame(width: 132, alignment: .trailing)
        }.fixedSize(horizontal: false, vertical: true)
            .accessibilityElement(children: .combine)
    }

    private var memoryCapacity: String {
        guard let memory = model.metrics.memory else { return "—" }
        return RunnerMetricsFormatter.bytes(memory.usedBytes, memory: true)
            + " / " + RunnerMetricsFormatter.bytes(memory.totalBytes, memory: true)
    }
    private var storageCapacity: String {
        guard let storage = model.metrics.storage else { return "—" }
        return localize("총 ", "Total ") + RunnerMetricsFormatter.bytes(storage.totalBytes)
            + "\n" + localize("사용 가능 ", "Available ") + RunnerMetricsFormatter.bytes(storage.availableBytes)
    }
    private var networkRates: String {
        guard let network = model.metrics.network, network.isConnected else { return "—" }
        return "↓ " + RunnerMetricsFormatter.rate(network.receivedBytesPerSecond)
            + "\n↑ " + RunnerMetricsFormatter.rate(network.sentBytesPerSecond)
    }
}
