import Darwin
import Foundation
import IOKit.ps
import SystemConfiguration

public enum MemoryPressure: Equatable, Sendable { case normal, warning, critical }

public struct MemoryMetrics: Equatable, Sendable {
    public let totalBytes: UInt64
    public let usedBytes: UInt64
    public let pressure: MemoryPressure?

    public init?(totalBytes: UInt64, usedBytes: UInt64, pressure: MemoryPressure?) {
        guard totalBytes > 0, usedBytes <= totalBytes else { return nil }
        self.totalBytes = totalBytes; self.usedBytes = usedBytes; self.pressure = pressure
    }

    public init?(totalBytes: UInt64, pageSize: UInt64, internalPages: UInt64, wiredPages: UInt64,
                 compressedPages: UInt64, purgeablePages: UInt64, pressure: MemoryPressure?) {
        guard pageSize > 0, internalPages >= purgeablePages else { return nil }
        let (resident, residentOverflow) = (internalPages - purgeablePages).addingReportingOverflow(wiredPages)
        let (pages, pagesOverflow) = resident.addingReportingOverflow(compressedPages)
        let (bytes, bytesOverflow) = pages.multipliedReportingOverflow(by: pageSize)
        guard !residentOverflow, !pagesOverflow, !bytesOverflow else { return nil }
        self.init(totalBytes: totalBytes, usedBytes: bytes, pressure: pressure)
    }
}

public struct StorageMetrics: Equatable, Sendable {
    public let totalBytes: UInt64
    /// Root volume capacity available for important usage, including reclaimable/purgeable space.
    public let availableBytes: UInt64

    public init?(totalBytes: UInt64, availableBytes: UInt64) {
        guard totalBytes > 0, availableBytes <= totalBytes else { return nil }
        self.totalBytes = totalBytes; self.availableBytes = availableBytes
    }
}

public struct NetworkInterfaceCounters: Equatable, Sendable {
    public let name: String
    public let index: UInt32
    public let isConnected: Bool
    public let receivedBytes: UInt64
    public let sentBytes: UInt64

    public init(name: String, index: UInt32, isConnected: Bool, receivedBytes: UInt64, sentBytes: UInt64) {
        self.name = name; self.index = index; self.isConnected = isConnected
        self.receivedBytes = receivedBytes; self.sentBytes = sentBytes
    }
}

/// Normalizes the entire native read before any interface totals can be aggregated.
struct PhysicalNetworkInterfaceReading {
    let name: String
    let index: UInt32
    let flags: Int32
    let linkActive: Bool?
    let linkLookupStatus: Int
    let receivedBytes: UInt64
    let sentBytes: UInt64

    static func normalized(_ readings: [Self]) -> [NetworkInterfaceCounters]? {
        var counters: [NetworkInterfaceCounters] = []
        for reading in readings {
            let connected: Bool
            if reading.flags & IFF_UP == 0 || reading.flags & IFF_RUNNING == 0 {
                connected = false
            } else {
                // A missing key (NoKey) is not proof that an up/running physical link is disconnected.
                guard reading.linkLookupStatus == kSCStatusOK, let active = reading.linkActive else { return nil }
                connected = active
            }
            counters.append(.init(name: reading.name, index: reading.index, isConnected: connected,
                receivedBytes: reading.receivedBytes, sentBytes: reading.sentBytes))
        }
        return counters.sorted { $0.name < $1.name }
    }
}

public struct NetworkMetrics: Equatable, Sendable {
    /// Active physical Ethernet/Wi-Fi interfaces. Connectivity does not establish internet reachability.
    public let interfaceNames: [String]
    public let isConnected: Bool
    public let receivedBytesPerSecond: Double?
    public let sentBytesPerSecond: Double?
}

public enum BatteryPresence: Equatable, Sendable { case present, absent }

public struct BatteryMetrics: Equatable, Sendable {
    public let presence: BatteryPresence
    /// Charge percentage (0...100); absent batteries and unavailable readings have no percentage.
    public let percent: Double?
    public let isCharging: Bool?
    public let isExternalPower: Bool?

    public init?(presence: BatteryPresence, percent: Double?, isCharging: Bool?, isExternalPower: Bool?) {
        if let percent { guard percent.isFinite, (0...100).contains(percent) else { return nil } }
        guard presence != .absent || (percent == nil && isCharging == nil) else { return nil }
        self.presence = presence; self.percent = percent; self.isCharging = isCharging; self.isExternalPower = isExternalPower
    }
}

public struct SystemMetricsSnapshot: Equatable, Sendable {
    public let memory: MemoryMetrics?
    public let storage: StorageMetrics?
    public let network: NetworkMetrics?
    /// nil means the power-source read failed; .absent means no internal battery exists.
    public let battery: BatteryMetrics?
    public static let empty = SystemMetricsSnapshot(memory: nil, storage: nil, network: nil, battery: nil)

    public init(memory: MemoryMetrics?, storage: StorageMetrics?, network: NetworkMetrics?, battery: BatteryMetrics?) {
        self.memory = memory; self.storage = storage; self.network = network; self.battery = battery
    }
}

@MainActor
public struct SystemMetricsReaders {
    public var memory: () -> MemoryMetrics?
    public var storage: () -> StorageMetrics?
    public var network: () -> [NetworkInterfaceCounters]?
    public var battery: () -> BatteryMetrics?

    public init(memory: @escaping () -> MemoryMetrics?, storage: @escaping () -> StorageMetrics?,
                network: @escaping () -> [NetworkInterfaceCounters]?, battery: @escaping () -> BatteryMetrics?) {
        self.memory = memory; self.storage = storage; self.network = network; self.battery = battery
    }

    public static var system: Self {
        Self(memory: readMemory, storage: readStorage, network: readNetwork, battery: readBattery)
    }

    private static func readMemory() -> MemoryMetrics? {
        var info = vm_statistics64_data_t()
        var count = mach_msg_type_number_t(MemoryLayout<vm_statistics64_data_t>.size / MemoryLayout<integer_t>.size)
        let host = mach_host_self()
        defer { mach_port_deallocate(mach_task_self_, host) }
        let result = withUnsafeMutablePointer(to: &info) { pointer in
            pointer.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                host_statistics64(host, HOST_VM_INFO64, $0, &count)
            }
        }
        var pageSize: vm_size_t = 0
        guard result == KERN_SUCCESS, host_page_size(host, &pageSize) == KERN_SUCCESS, pageSize > 0 else { return nil }
        var level: Int32 = 0
        var size = MemoryLayout<Int32>.size
        let pressure: MemoryPressure?
        if sysctlbyname("kern.memorystatus_vm_pressure_level", &level, &size, nil, 0) == 0 {
            switch level { case 1: pressure = .normal; case 2: pressure = .warning; case 4: pressure = .critical; default: pressure = nil }
        } else { pressure = nil }
        // Anonymous resident pages exclude file cache; compressed pages count physical compressor storage once.
        return MemoryMetrics(totalBytes: ProcessInfo.processInfo.physicalMemory, pageSize: UInt64(pageSize),
            internalPages: UInt64(info.internal_page_count), wiredPages: UInt64(info.wire_count),
            compressedPages: UInt64(info.compressor_page_count), purgeablePages: UInt64(info.purgeable_count), pressure: pressure)
    }

    private static func readStorage() -> StorageMetrics? {
        guard let values = try? URL(fileURLWithPath: "/").resourceValues(forKeys: [.volumeTotalCapacityKey, .volumeAvailableCapacityForImportantUsageKey]),
              let total = values.volumeTotalCapacity, total > 0,
              let available = values.volumeAvailableCapacityForImportantUsage, available >= 0 else { return nil }
        return StorageMetrics(totalBytes: UInt64(total), availableBytes: UInt64(available))
    }

    private static func readNetwork() -> [NetworkInterfaceCounters]? {
        guard let interfaces = SCNetworkInterfaceCopyAll() as? [SCNetworkInterface],
              let store = SCDynamicStoreCreate(nil, "HappyLulu System Metrics" as CFString, nil, nil) else { return nil }
        var physical: [UInt32: (name: String, active: Bool?, status: Int)] = [:]
        for interface in interfaces {
            let type = SCNetworkInterfaceGetInterfaceType(interface)
            guard type == kSCNetworkInterfaceTypeEthernet || type == kSCNetworkInterfaceTypeIEEE80211,
                  let name = SCNetworkInterfaceGetBSDName(interface) as String? else { continue }
            let index = if_nametoindex(name)
            guard index > 0 else { continue }
            let value = SCDynamicStoreCopyValue(store, "State:/Network/Interface/\(name)/Link" as CFString)
            let status = value == nil ? Int(SCError()) : kSCStatusOK
            let link = value as? [String: Any]
            physical[index] = (name, link?["Active"] as? Bool, status)
        }
        var mib: [Int32] = [CTL_NET, PF_ROUTE, 0, 0, NET_RT_IFLIST2, 0]
        var length = 0
        guard sysctl(&mib, u_int(mib.count), nil, &length, nil, 0) == 0 else { return nil }
        var data = [UInt8](repeating: 0, count: length)
        let result = data.withUnsafeMutableBytes { sysctl(&mib, u_int(mib.count), $0.baseAddress, &length, nil, 0) }
        guard result == 0, length <= data.count else { return nil }
        return data.withUnsafeBytes { bytes -> [NetworkInterfaceCounters]? in
            var offset = 0
            var readings: [PhysicalNetworkInterfaceReading] = []
            while offset < length {
                guard length - offset >= 4 else { return nil }
                let messageLength = Int(bytes.loadUnaligned(fromByteOffset: offset, as: UInt16.self))
                guard messageLength >= 4, messageLength <= length - offset else { return nil }
                if bytes[offset + 3] == UInt8(RTM_IFINFO2) {
                    guard messageLength >= MemoryLayout<if_msghdr2>.size else { return nil }
                    let info = bytes.loadUnaligned(fromByteOffset: offset, as: if_msghdr2.self)
                    if let link = physical[UInt32(info.ifm_index)] {
                        readings.append(.init(name: link.name, index: UInt32(info.ifm_index), flags: info.ifm_flags,
                            linkActive: link.active, linkLookupStatus: link.status,
                            receivedBytes: info.ifm_data.ifi_ibytes, sentBytes: info.ifm_data.ifi_obytes))
                    }
                }
                offset += messageLength
            }
            // A disappearing interface must not become a fabricated zero counter.
            guard readings.count == physical.count else { return nil }
            return PhysicalNetworkInterfaceReading.normalized(readings)
        }
    }

    private static func readBattery() -> BatteryMetrics? {
        guard let info = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
              let sources = IOPSCopyPowerSourcesList(info)?.takeRetainedValue() as? [CFTypeRef] else { return nil }
        let source = IOPSGetProvidingPowerSourceType(info)?.takeUnretainedValue() as String?
        let external = source == kIOPSACPowerValue ? true : source == kIOPSBatteryPowerValue ? false : nil
        for item in sources {
            guard let description = IOPSGetPowerSourceDescription(info, item)?.takeUnretainedValue() as? [String: Any] else { return nil }
            guard description[kIOPSTypeKey] as? String == kIOPSInternalBatteryType else { continue }
            guard let present = description[kIOPSIsPresentKey] as? Bool else { return nil }
            guard present else { continue }
            var percent: Double?
            if let current = description[kIOPSCurrentCapacityKey] as? Double,
               let maximum = description[kIOPSMaxCapacityKey] as? Double, maximum > 0,
               current >= 0, current <= maximum { percent = 100 * current / maximum }
            return BatteryMetrics(presence: .present, percent: percent,
                isCharging: description[kIOPSIsChargingKey] as? Bool, isExternalPower: external)
        }
        return BatteryMetrics(presence: .absent, percent: nil, isCharging: nil, isExternalPower: external)
    }
}

@MainActor
public final class SystemMetricsSampler {
    private let readers: SystemMetricsReaders
    private let now: () -> TimeInterval
    private var previous: (time: TimeInterval, interfaces: [NetworkInterfaceCounters])?
    private var slowReadTime: TimeInterval?
    private var storage: StorageMetrics?
    private var battery: BatteryMetrics?

    public init(readers: SystemMetricsReaders = .system, now: @escaping () -> TimeInterval = { ProcessInfo.processInfo.systemUptime }) {
        self.readers = readers; self.now = now
    }

    public func reset() {
        previous = nil; slowReadTime = nil; storage = nil; battery = nil
    }

    public func sample() -> SystemMetricsSnapshot {
        let time = now()
        if slowReadTime == nil || !time.isFinite || time < slowReadTime! || time - slowReadTime! >= 5 {
            storage = readers.storage(); battery = readers.battery()
            slowReadTime = time.isFinite ? time : nil
        }
        return SystemMetricsSnapshot(memory: readers.memory(), storage: storage, network: sampleNetwork(), battery: battery)
    }

    private func sampleNetwork() -> NetworkMetrics? {
        guard let interfaces = readers.network() else { previous = nil; return nil }
        let time = now()
        let current = interfaces.filter(\.isConnected).sorted { $0.name < $1.name }
        defer { previous = time.isFinite ? (time, current) : nil }
        var received: Double?, sent: Double?
        if let previous, time.isFinite, time > previous.time, !current.isEmpty,
           current.count == previous.interfaces.count {
            var receiveDelta = 0.0, sendDelta = 0.0
            var valid = true
            for (old, new) in zip(previous.interfaces, current) {
                guard old.name == new.name, old.index == new.index,
                      new.receivedBytes >= old.receivedBytes, new.sentBytes >= old.sentBytes else { valid = false; break }
                receiveDelta += Double(new.receivedBytes - old.receivedBytes)
                sendDelta += Double(new.sentBytes - old.sentBytes)
            }
            if valid {
                let elapsed = time - previous.time
                let rx = receiveDelta / elapsed, tx = sendDelta / elapsed
                if rx.isFinite && tx.isFinite { received = rx; sent = tx }
            }
        }
        return NetworkMetrics(interfaceNames: current.map(\.name), isConnected: !current.isEmpty,
            receivedBytesPerSecond: received, sentBytesPerSecond: sent)
    }
}
