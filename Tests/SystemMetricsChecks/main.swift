import Foundation
import Darwin
import SystemConfiguration
@testable import CPURunnerIntegration

func require(_ condition: @autoclosure () -> Bool, _ message: String) {
    guard condition() else { print("FAIL \(message)"); exit(1) }
}

func checkPhysicalLinkNormalization() {
    func reading(_ name: String = "en0", active: Bool?, status: Int = kSCStatusOK,
                 flags: Int32 = IFF_UP | IFF_RUNNING) -> PhysicalNetworkInterfaceReading {
        .init(name: name, index: name == "en0" ? 4 : 5, flags: flags, linkActive: active,
              linkLookupStatus: status, receivedBytes: 1_000, sentBytes: 2_000)
    }
    let active = reading(active: true)
    require(PhysicalNetworkInterfaceReading.normalized([active])?.first?.isConnected == true, "known active physical link must connect")
    require(PhysicalNetworkInterfaceReading.normalized([reading(active: false)])?.first?.isConnected == false, "Active=false must remain disconnected")
    require(PhysicalNetworkInterfaceReading.normalized([reading(active: nil, status: kSCStatusNoKey)]) == nil, "missing link key on a running interface must remain unknown")
    require(PhysicalNetworkInterfaceReading.normalized([reading(active: nil, status: kSCStatusFailed)]) == nil, "failed active-link lookup must be unavailable, not disconnected")
    require(PhysicalNetworkInterfaceReading.normalized([reading(active: nil)]) == nil, "missing Active in a returned dictionary must be unknown")
    require(PhysicalNetworkInterfaceReading.normalized([reading(active: nil, status: kSCStatusFailed, flags: 0)])?.first?.isConnected == false, "known down interface must not make all network unavailable")
    require(PhysicalNetworkInterfaceReading.normalized([reading(active: nil, status: kSCStatusFailed, flags: IFF_UP)])?.first?.isConnected == false, "non-running interface must remain disconnected")
    require(PhysicalNetworkInterfaceReading.normalized([active, reading("en1", active: nil, status: kSCStatusFailed)]) == nil, "partial link-read failure must reject aggregation instead of undercounting")
    let partiallyInactive = PhysicalNetworkInterfaceReading.normalized([active, reading("en1", active: nil, status: kSCStatusNoKey, flags: 0)])
    require(partiallyInactive?.count == 2 && partiallyInactive?.filter(\.isConnected).count == 1, "inactive interface must preserve active-interface counters")
    print("PASS physical links: active/inactive, missing key, failure, malformed Active, flags and partial-failure aggregation")
}

@MainActor
func checkDeltas() {
    var time = 10.0
    var network: [NetworkInterfaceCounters]? = [.init(name: "en0", index: 4, isConnected: true, receivedBytes: 5_000_000_000, sentBytes: 7_000_000_000)]
    var reads = 0
    let sampler = SystemMetricsSampler(readers: .init(memory: { nil }, storage: { nil }, network: { reads += 1; return network }, battery: { nil }), now: { time })
    require(reads == 0, "initialization must not read or schedule anything")
    require(sampler.sample().network?.receivedBytesPerSecond == nil, "first sample must establish a baseline")
    time += 2
    network = [.init(name: "en0", index: 4, isConnected: true, receivedBytes: 5_000_004_096, sentBytes: 7_000_001_024)]
    let rate = sampler.sample().network
    require(rate?.receivedBytesPerSecond == 2_048 && rate?.sentBytesPerSecond == 512, "rates must use 64-bit deltas and seconds, not bits or lifetime values")
    time += 0.5
    require(sampler.sample().network?.receivedBytesPerSecond == 0, "measured idle must remain zero")
    require(sampler.sample().network?.receivedBytesPerSecond == nil, "zero elapsed time must not divide by zero")
    time += 1
    network = [.init(name: "en0", index: 4, isConnected: true, receivedBytes: 1, sentBytes: 1)]
    require(sampler.sample().network?.receivedBytesPerSecond == nil, "counter decrease must rebaseline")
    time += 1
    network = [.init(name: "en0", index: 4, isConnected: true, receivedBytes: 101, sentBytes: 201)]
    require(sampler.sample().network?.receivedBytesPerSecond == 100, "counter decrease must recover")
    time += 1; network = nil
    require(sampler.sample().network == nil, "failed read must be unavailable")
    time += 1; network = [.init(name: "en0", index: 4, isConnected: true, receivedBytes: 301, sentBytes: 401)]
    require(sampler.sample().network?.receivedBytesPerSecond == nil, "failed read must break the delta interval")
    time += 1
    network = [.init(name: "en0", index: 5, isConnected: true, receivedBytes: 401, sentBytes: 501)]
    require(sampler.sample().network?.receivedBytesPerSecond == nil, "recreated interface must rebaseline even with same name")
    time += 1; network = [.init(name: "en0", index: 5, isConnected: false, receivedBytes: 401, sentBytes: 501)]
    require(sampler.sample().network?.isConnected == false, "disconnection must be explicit")
    time += 1; network = [.init(name: "en0", index: 5, isConnected: true, receivedBytes: 501, sentBytes: 601)]
    require(sampler.sample().network?.receivedBytesPerSecond == nil, "reconnection must rebaseline")
    time += 1
    require(sampler.sample().network?.receivedBytesPerSecond == 0, "reconnected idle must recover")
    sampler.reset(); time += 1
    require(sampler.sample().network?.receivedBytesPerSecond == nil, "reset must clear previous counters")
    time = .nan
    require(sampler.sample().network?.receivedBytesPerSecond == nil, "invalid clock must not create rates")
    time = 30
    network = [
        .init(name: "en1", index: 6, isConnected: true, receivedBytes: 1_000, sentBytes: 2_000),
        .init(name: "en0", index: 5, isConnected: true, receivedBytes: 1_000, sentBytes: 2_000)
    ]
    require(sampler.sample().network?.receivedBytesPerSecond == nil, "clock recovery must establish a baseline")
    time += 2
    network = [
        .init(name: "en0", index: 5, isConnected: true, receivedBytes: 1_200, sentBytes: 2_400),
        .init(name: "en1", index: 6, isConnected: true, receivedBytes: 1_400, sentBytes: 2_800)
    ]
    let aggregated = sampler.sample().network
    require(aggregated?.interfaceNames == ["en0", "en1"] && aggregated?.receivedBytesPerSecond == 300 && aggregated?.sentBytesPerSecond == 600, "physical interfaces must aggregate once regardless of order")
    time += 1; network?.removeLast()
    require(sampler.sample().network?.receivedBytesPerSecond == nil, "interface set changes must rebaseline")
    time -= 2
    require(sampler.sample().network?.receivedBytesPerSecond == nil, "backwards clock must rebaseline")
    time += 3
    require(sampler.sample().network?.receivedBytesPerSecond == 0, "backwards clock must recover")
    print("PASS network: 64-bit elapsed rates, zero, rollback, failure/recovery, interface identity, reconnect, reset and invalid clock")
}

@MainActor
func checkBoundsAndCache() {
    require(MemoryMetrics(totalBytes: 0, usedBytes: 0, pressure: nil) == nil, "zero total memory must be unavailable")
    require(MemoryMetrics(totalBytes: 10, usedBytes: 11, pressure: nil) == nil, "memory cannot exceed total")
    let memory = MemoryMetrics(totalBytes: 100, pageSize: 4, internalPages: 10, wiredPages: 3, compressedPages: 4, purgeablePages: 2, pressure: .warning)
    require(memory?.usedBytes == 60 && memory?.pressure == .warning, "memory must add physical compressed pages and subtract reclaimable purgeable memory")
    require(MemoryMetrics(totalBytes: 100, pageSize: 4, internalPages: 1, wiredPages: 0, compressedPages: 0, purgeablePages: 2, pressure: nil) == nil, "invalid page counters must not underflow")
    require(MemoryMetrics(totalBytes: .max, pageSize: .max, internalPages: 2, wiredPages: 0, compressedPages: 0, purgeablePages: 0, pressure: nil) == nil, "page conversion must not overflow")
    require(StorageMetrics(totalBytes: 100, availableBytes: 101) == nil, "available storage cannot exceed total")
    require(BatteryMetrics(presence: .present, percent: 100.1, isCharging: false, isExternalPower: true) == nil, "battery percent must be bounded")
    require(BatteryMetrics(presence: .present, percent: .nan, isCharging: false, isExternalPower: true) == nil, "battery percent must be finite")
    require(BatteryMetrics(presence: .present, percent: 0, isCharging: false, isExternalPower: false)?.percent == 0, "empty battery must remain measured zero")
    require(BatteryMetrics(presence: .absent, percent: nil, isCharging: nil, isExternalPower: true)?.presence == .absent, "battery absence must differ from read failure")
    var time = 0.0, memoryReads = 0, storageReads = 0, batteryReads = 0
    var storageFails = false
    let sampler = SystemMetricsSampler(readers: .init(memory: { memoryReads += 1; return memory }, storage: { storageReads += 1; return storageFails ? nil : StorageMetrics(totalBytes: 100, availableBytes: 25) }, network: { [] }, battery: { batteryReads += 1; return BatteryMetrics(presence: .absent, percent: nil, isCharging: nil, isExternalPower: true) }), now: { time })
    require(storageReads == 0 && batteryReads == 0, "slow sources must not read on init")
    require(sampler.sample().storage?.availableBytes == 25, "initial storage read missing")
    time = 4.9; _ = sampler.sample()
    require(memoryReads == 2 && storageReads == 1 && batteryReads == 1, "only storage/battery should be cached for five seconds")
    storageFails = true; time = 5
    require(sampler.sample().storage == nil && storageReads == 2, "refresh failure must clear stale storage")
    storageFails = false; time = 10
    require(sampler.sample().storage != nil, "storage must recover at next refresh")
    sampler.reset(); _ = sampler.sample()
    require(storageReads == 4 && batteryReads == 4, "reset must clear slow source caches")
    require(SystemMetricsSnapshot.empty.memory == nil && SystemMetricsSnapshot.empty.network == nil && SystemMetricsSnapshot.empty.storage == nil && SystemMetricsSnapshot.empty.battery == nil, "empty snapshot must contain no fabricated values")
    print("PASS models/cache: units, bounds, overflow, compressed memory, absence, lazy reads, cache, refresh failure/recovery and reset")
}

@MainActor
func liveSmoke() async {
    let sampler = SystemMetricsSampler()
    let first = sampler.sample()
    try? await Task.sleep(for: .milliseconds(250))
    let second = sampler.sample()
    if let memory = second.memory { require(memory.totalBytes > 0 && memory.usedBytes <= memory.totalBytes, "live memory bounds") }
    if let storage = second.storage { require(storage.availableBytes <= storage.totalBytes, "live storage bounds") }
    if let network = second.network {
        for rate in [network.receivedBytesPerSecond, network.sentBytesPerSecond].compactMap({ $0 }) { require(rate.isFinite && rate >= 0, "live network bounds") }
    }
    print("LIVE memory=\(second.memory != nil) storage=\(second.storage != nil) network=\(second.network != nil) battery=\(second.battery?.presence == .present ? "present" : second.battery?.presence == .absent ? "absent" : "unavailable") firstRateUnavailable=\(first.network?.receivedBytesPerSecond == nil)")
}

@MainActor
func measureNativeLatency() {
    let native = SystemMetricsReaders.system
    var time = 0.0, storageReads = 0, batteryReads = 0, unavailableNetworks = 0
    let sampler = SystemMetricsSampler(readers: .init(memory: native.memory, storage: { storageReads += 1; return native.storage() }, network: native.network, battery: { batteryReads += 1; return native.battery() }), now: { time })
    var cached: [Double] = [], refreshed: [Double] = []
    for sampleIndex in 0..<20 {
        time = Double(sampleIndex)
        let start = ContinuousClock.now
        let snapshot = sampler.sample()
        let duration = start.duration(to: .now).components
        let milliseconds = Double(duration.seconds) * 1_000 + Double(duration.attoseconds) / 1e15
        if snapshot.network == nil { unavailableNetworks += 1 }
        if sampleIndex % 5 == 0 { refreshed.append(milliseconds) } else { cached.append(milliseconds) }
    }
    require(storageReads == 4 && batteryReads == 4, "latency run must include four real slow-source refreshes")
    func summary(_ values: [Double]) -> String {
        let sorted = values.sorted()
        return String(format: "count=%d median=%.3fms max=%.3fms", sorted.count, sorted[sorted.count / 2], sorted.last!)
    }
    print("LATENCY cached \(summary(cached)); refreshed \(summary(refreshed)); unavailableNetworks=\(unavailableNetworks)/20")
}

checkPhysicalLinkNormalization()
checkDeltas()
checkBoundsAndCache()
if CommandLine.arguments.contains("--live") { await liveSmoke() }
if CommandLine.arguments.contains("--benchmark") { measureNativeLatency() }
print("PASS SystemMetricsChecks")
