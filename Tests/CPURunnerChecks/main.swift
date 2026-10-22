import Foundation
import Combine
import AppKit
import SwiftUI
import CPURunnerIntegration
import AppPluginHost
import AppPluginCore

func require(_ condition: @autoclosure () -> Bool, _ message: String) {
    guard condition() else { print("FAIL \(message)"); exit(1) }
}

@MainActor
func checkCPUUsage() {
    var values: [CPUUsageTicks?] = [
        .init(user: 100, system: 100, nice: 0, idle: 800),
        .init(user: 150, system: 150, nice: 0, idle: 900),
        .init(user: 150, system: 150, nice: 0, idle: 900),
        .init(user: 5, system: 5, nice: 0, idle: 10),
        .init(user: 10, system: 10, nice: 0, idle: 20),
        nil,
        .init(user: 500, system: 500, nice: 0, idle: 1000),
        .init(user: 500, system: 500, nice: 0, idle: 1100)
    ]
    let sampler = CPUUsageSampler(readTicks: { values.removeFirst() })
    require(sampler.sample() == nil, "first CPU sample must establish a baseline")
    require(sampler.sample() == 0.5, "CPU must use elapsed deltas, not lifetime totals")
    require(sampler.sample() == nil, "zero total delta must be unavailable")
    require(sampler.sample() == nil, "counter reset must establish a fresh baseline")
    require(sampler.sample() == 0.5, "counter reset did not recover")
    require(sampler.sample() == nil, "failed reads must be unavailable")
    require(sampler.sample() == nil, "read recovery must not include an unknown time interval")
    require(sampler.sample() == 0, "measured zero usage was lost")
    sampler.reset()
    values = [.init(user: 1, system: 1, nice: 1, idle: 1), .init(user: 1, system: 1, nice: 2, idle: 1)]
    require(sampler.sample() == nil && sampler.sample() == 1, "reset or nice CPU time was lost")
    require(RunnerAnimationPolicy.frameInterval(usage: 0, reduceMotion: false, lowPower: false) == 0.5, "idle rate is not 2 fps")
    require(RunnerAnimationPolicy.frameInterval(usage: 1, reduceMotion: false, lowPower: false) == 0.0625, "busy rate exceeds 16 fps")
    require(RunnerAnimationPolicy.frameInterval(usage: 1, reduceMotion: false, lowPower: true) == 0.25, "low power rate exceeds 4 fps")
    for value in [Double?.none, .some(.nan), .some(.infinity), .some(-0.1), .some(1.1)] {
        require(RunnerAnimationPolicy.frameInterval(usage: value, reduceMotion: false, lowPower: false) == nil, "invalid CPU value animated")
    }
    require(RunnerAnimationPolicy.frameInterval(usage: 0.5, reduceMotion: true, lowPower: false) == nil, "Reduce Motion did not stop animation")
    print("PASS CPU: elapsed deltas, first/zero/reset/failed samples, recovery, nice time and animation bounds")
}

@MainActor
func checkSettings() {
    let name = "happylulu-runner-check-" + UUID().uuidString
    let defaults = UserDefaults(suiteName: name)!
    defer { defaults.removePersistentDomain(forName: name) }
    let settings = RunnerSettings(defaults: defaults)
    require(settings.palette == .standard, "default orbit palette changed")
    require(defaults.object(forKey: RunnerSettings.orbitStartColorKey) == nil
            && defaults.object(forKey: RunnerSettings.orbitEndColorKey) == nil, "reading palette wrote preferences")
    for invalid in ["112233", "#12345", "#1234567", "#GG1122", " #112233", "#112233\n"] {
        defaults.set(invalid, forKey: RunnerSettings.orbitStartColorKey)
        require(settings.palette.startRGB == PluginOrbitPalette.standard.startRGB, "invalid RGB string did not fall back")
        require(defaults.string(forKey: RunnerSettings.orbitStartColorKey) == invalid, "invalid RGB string was overwritten on read")
    }
    defaults.set("#aBcD09", forKey: RunnerSettings.orbitEndColorKey)
    require(settings.palette.endRGB == 0xABCD09, "valid lowercase RGB was rejected")
    let invalidStart = defaults.string(forKey: RunnerSettings.orbitStartColorKey)
    settings.palette = PluginOrbitPalette(startRGB: settings.palette.startRGB, endRGB: 0x001122)
    require(defaults.string(forKey: RunnerSettings.orbitStartColorKey) == invalidStart,
            "editing the other color overwrote an invalid saved value")
    defaults.set("not-a-color", forKey: RunnerSettings.orbitEndColorKey)
    require(settings.palette.endRGB == PluginOrbitPalette.standard.endRGB
            && defaults.string(forKey: RunnerSettings.orbitEndColorKey) == "not-a-color",
            "invalid end color did not fall back without overwriting")
    let palette = PluginOrbitPalette(startRGB: 0xFE7124, endRGB: 0x003AFF)
    settings.palette = palette
    require(RunnerSettings(defaults: defaults).palette == palette, "orbit palette did not persist")
    require(defaults.string(forKey: RunnerSettings.orbitStartColorKey) == "#FE7124"
            && defaults.string(forKey: RunnerSettings.orbitEndColorKey) == "#003AFF", "palette was not stored as strict #RRGGBB")
    settings.palette = .standard
    require(RunnerSettings(defaults: defaults).palette == .standard, "restoring standard palette did not persist")
    require(settings.presentation == .owlOrbit, "default presentation must use the existing owl")
    require(defaults.object(forKey: RunnerSettings.presentationKey) == nil, "reading presentation wrote a preference")
    defaults.set("future-presentation", forKey: RunnerSettings.presentationKey)
    require(settings.presentation == .owlOrbit, "unknown presentation must safely fall back")
    require(defaults.string(forKey: RunnerSettings.presentationKey) == "future-presentation", "unknown presentation was overwritten")
    require(settings.animal == .hamster, "default animal changed")
    require(defaults.object(forKey: RunnerSettings.animalKey) == nil, "reading defaults wrote a preference")
    defaults.set("future-animal", forKey: RunnerSettings.animalKey)
    require(settings.animal == .hamster, "unknown animal must safely fall back")
    require(defaults.string(forKey: RunnerSettings.animalKey) == "future-animal", "unknown saved preference was overwritten")
    for animal in RunnerAnimal.allCases {
        settings.animal = animal
        require(RunnerSettings(defaults: defaults).animal == animal, "animal selection did not survive a new settings instance")
    }
    for presentation in RunnerPresentation.allCases {
        settings.presentation = presentation
        require(RunnerSettings(defaults: defaults).presentation == presentation, "presentation did not persist")
        require(settings.animal == .cat, "changing presentation cleared the saved animal")
    }
    print("PASS settings: all three choices persist, absent/unknown settings remain preserved")
}

@MainActor
final class FixtureTimer: RunnerScheduledTask {
    let interval: TimeInterval
    let action: @MainActor () -> Void
    var cancelled = false
    init(interval: TimeInterval, action: @escaping @MainActor () -> Void) { self.interval = interval; self.action = action }
    func cancel() { cancelled = true }
    func fireEvenIfCancelled() { action() }
}

@MainActor
final class FixtureDisplay: RunnerStatusDisplaying {
    var frames: [Int] = []
    var animals: [RunnerAnimal] = []
    var labels: [String] = []
    var removals = 0
    func render(animal: RunnerAnimal, frame: Int, usageText: String, accessibilityLabel: String) {
        frames.append(frame); animals.append(animal); labels.append(accessibilityLabel)
    }
    func remove() { removals += 1 }
}

@MainActor
final class FixtureMotionPreferences {
    var reduceMotion = false
    var lowPower = false
}

@MainActor
final class FixtureSystemMetrics {
    var time: TimeInterval = 0
    var received: UInt64 = 1_000
    var sent: UInt64 = 2_000
    var memoryUsed: UInt64 = 12 * 1_024 * 1_024 * 1_024
    var unavailable = false
    var memoryReads = 0, storageReads = 0, networkReads = 0, batteryReads = 0
    var readCounts: [Int] { [memoryReads, storageReads, networkReads, batteryReads] }

    func sampler() -> SystemMetricsSampler {
        SystemMetricsSampler(readers: SystemMetricsReaders(memory: {
            self.memoryReads += 1
            return self.unavailable ? nil : MemoryMetrics(totalBytes: 32 * 1_024 * 1_024 * 1_024,
                usedBytes: self.memoryUsed, pressure: .normal)
        }, storage: {
            self.storageReads += 1
            return self.unavailable ? nil : StorageMetrics(totalBytes: 1_000_000_000_000, availableBytes: 640_000_000_000)
        }, network: {
            self.networkReads += 1
            return self.unavailable ? nil : [NetworkInterfaceCounters(name: "en0", index: 4, isConnected: true,
                receivedBytes: self.received, sentBytes: self.sent)]
        }, battery: {
            self.batteryReads += 1
            return self.unavailable ? nil : BatteryMetrics(presence: .present, percent: 76,
                isCharging: true, isExternalPower: true)
        }), now: { self.time })
    }
}

@MainActor
func checkLifecycle() {
    let name = "happylulu-runner-lifecycle-" + UUID().uuidString
    let defaults = UserDefaults(suiteName: name)!
    defer { defaults.removePersistentDomain(forName: name) }
    RunnerSettings(defaults: defaults).presentation = .animal
    var ticks = CPUUsageTicks(user: 100, system: 100, nice: 0, idle: 800)
    var readFails = false, reads = 0
    let motion = FixtureMotionPreferences()
    let metrics = FixtureSystemMetrics()
    var timers: [FixtureTimer] = [], displays: [FixtureDisplay] = []
    let controller = CPURunnerController(settings: RunnerSettings(defaults: defaults),
        sampler: CPUUsageSampler(readTicks: { reads += 1; return readFails ? nil : ticks }),
        metricsSampler: metrics.sampler(),
        displayFactory: { _ in let value = FixtureDisplay(); displays.append(value); return value },
        schedule: { interval, action in
            let timer = FixtureTimer(interval: interval, action: action); timers.append(timer); return timer
        }, reduceMotion: { motion.reduceMotion }, lowPower: { motion.lowPower }, observeSystemChanges: false)
    controller.start()
    require(displays.isEmpty && timers.isEmpty && reads == 0, "disabled plugin created runtime resources")
    controller.setModuleEnabled(true); controller.start(); controller.start()
    require(displays.count == 1 && timers.count == 1 && reads == 1, "start is not idempotent")
    require(controller.isActive && !controller.isRunning, "ongoing monitoring must not block app updates")
    let sample = timers[0]
    let output = controller as AnyObject as? any PluginMenuBarImageProviding
    require(output?.menuBarImage != nil, "runner must provide its image to the shared owl status item")
    ticks = .init(user: 150, system: 150, nice: 0, idle: 900); sample.fireEvenIfCancelled()
    require(controller.usage == 0.5 && timers.count == 2, "sample did not start CPU animation")
    let animation = timers[1], display = displays[0]
    var changes = 0
    let subscription = controller.changes.sink { changes += 1 }
    var imageChanges = 0
    let imageSubscription = output!.imageChanges.sink { imageChanges += 1 }
    for _ in 0..<RunnerArtwork.frameCount { animation.fireEvenIfCancelled() }
    require(Set(display.frames.suffix(RunnerArtwork.frameCount)).count == RunnerArtwork.frameCount, "animation did not cycle all frames")
    require(changes == 0, "animation frames published whole-app settings changes")
    require(imageChanges == RunnerArtwork.frameCount, "animation must update the host through its image-only channel")
    for animal in RunnerAnimal.allCases {
        controller.selectAnimal(animal)
        require(controller.animal == animal && display.animals.last == animal, "selection did not update live display")
        require(RunnerSettings(defaults: defaults).animal == animal, "live selection was not persisted")
        let cycle = animal == .cat ? [1, 2, 3, 4, 0] : [1, 2, 3, 4, 5, 6, 7, 0]
        for _ in 0..<(cycle.count * 2) { animation.fireEvenIfCancelled() }
        require(Array(display.frames.suffix(cycle.count * 2)) == cycle + cycle,
                "\(animal.rawValue) animation did not wrap its complete frame sequence")
    }
    require(display.labels.last?.contains("CPU 50%") == true, "accessible label lost measured CPU value")
    for (next, expected) in [
        (CPUUsageTicks(user: 175, system: 150, nice: 0, idle: 975), 0.25),
        (CPUUsageTicks(user: 250, system: 150, nice: 0, idle: 1000), 0.75),
        (CPUUsageTicks(user: 300, system: 150, nice: 0, idle: 1050), 0.5)
    ] {
        ticks = next; sample.fireEvenIfCancelled()
        require(controller.usage == expected, "normal CPU values stopped updating presentation")
    }
    require(changes == 0, "normal CPU samples must not invalidate host calendar/agenda data")
    let beforeSleep = reads
    controller.suspendForSleep()
    require(changes == 1, "CPU becoming unavailable must notify host connection state once")
    require(sample.cancelled && animation.cancelled && controller.usage == nil, "sleep did not stop both timers")
    let sleepFrames = display.frames.count
    sample.fireEvenIfCancelled(); animation.fireEvenIfCancelled()
    require(reads == beforeSleep && display.frames.count == sleepFrames, "cancelled callbacks ran during sleep")
    ticks = .init(user: 1000, system: 1000, nice: 0, idle: 2000)
    controller.resumeAfterSleep(); controller.resumeAfterSleep()
    require(controller.usage == nil && displays.count == 1, "wake did not rebaseline or duplicated status item")
    let wakeSample = timers.last!
    ticks = .init(user: 1050, system: 1050, nice: 0, idle: 2100); wakeSample.fireEvenIfCancelled()
    require(controller.usage == 0.5, "wake sample used CPU time from before sleep")
    require(changes == 2, "CPU recovery must notify host connection state once")
    let wakeAnimation = timers.last!
    motion.reduceMotion = true; controller.refreshDisplayPreferences()
    require(wakeAnimation.cancelled && !wakeSample.cancelled, "Reduce Motion must keep CPU sampling active")
    let reducedFrames = display.frames.count
    wakeAnimation.fireEvenIfCancelled()
    require(display.frames.count == reducedFrames, "cancelled animation callback escaped Reduce Motion")
    motion.reduceMotion = false; motion.lowPower = true; controller.refreshDisplayPreferences()
    require(timers.last!.interval >= 0.25, "low power mode exceeded frame cap")
    readFails = true; wakeSample.fireEvenIfCancelled()
    require(controller.usage == nil && !controller.usageText.contains("0%"), "failed sampling fabricated zero usage")
    require(changes == 3, "CPU failure must notify host connection state once")
    readFails = false; wakeSample.fireEvenIfCancelled()
    require(controller.usage == nil, "CPU read recovery failed to rebaseline")
    require(changes == 3, "pending recovery repeated a host notification")
    ticks = .init(user: 1100, system: 1100, nice: 0, idle: 2200); wakeSample.fireEvenIfCancelled()
    require(controller.usage == 0.5, "CPU sampling did not recover")
    require(changes == 4, "successful recovery did not notify host")
    controller.setModuleEnabled(false)
    require(output?.menuBarImage == nil, "disabled runner left its image beside the owl")
    require(changes == 6, "disable and availability transitions did not reach host")
    let stoppedReads = reads, stoppedFrames = display.frames.count
    for timer in timers { timer.fireEvenIfCancelled() }
    require(!controller.isActive && timers.allSatisfy(\.cancelled) && display.removals == 1, "disable leaked timers or status item")
    require(reads == stoppedReads && display.frames.count == stoppedFrames, "callbacks published after stop")
    controller.setModuleEnabled(true); controller.start(); controller.stop(); controller.stop()
    require(displays.count == 2 && displays[1].removals == 1 && timers.allSatisfy(\.cancelled), "restart/stop leaked a status item or timer")
    require(RunnerSettings(defaults: defaults).animal == .cat, "disable cleared saved animal")
    controller.selectAnimal(.hamster)
    require(output?.menuBarImage == nil, "changing a stopped runner must not restore its menu-bar image")
    withExtendedLifetime((subscription, imageSubscription)) {}
    print("PASS lifecycle: opt-in, idempotence, hamster/rabbit 8-frame and cat 5-frame cycles, live choices, AX CPU, bounded host notifications, sleep/wake, power/motion, failure recovery and cleanup")
}

@MainActor
func checkOwlOrbit() {
    let name = "happylulu-owl-orbit-" + UUID().uuidString
    let defaults = UserDefaults(suiteName: name)!
    defer { defaults.removePersistentDomain(forName: name) }
    var ticks = CPUUsageTicks(user: 0, system: 0, nice: 0, idle: 0)
    var fails = false
    var uptime: TimeInterval = 0
    var timers: [FixtureTimer] = []
    let motion = FixtureMotionPreferences()
    let controller = CPURunnerController(settings: RunnerSettings(defaults: defaults),
        sampler: CPUUsageSampler(readTicks: { fails ? nil : ticks }), metricsSampler: FixtureSystemMetrics().sampler(),
        schedule: { interval, action in
            let timer = FixtureTimer(interval: interval, action: action); timers.append(timer); return timer
        }, reduceMotion: { motion.reduceMotion }, lowPower: { motion.lowPower }, observeSystemChanges: false,
        now: { uptime })
    func fire(_ timer: FixtureTimer) { uptime += timer.interval; timer.fireEvenIfCancelled() }
    func phase() -> Double? {
        guard case let .orbit(phase, _)? = controller.baseIconEffect else { return nil }
        return phase
    }
    require(RunnerOrbitAnimationPolicy.frameCount == 48, "owl orbit lost its 48 phase positions")
    require(RunnerOrbitAnimationPolicy.rotationPeriod(usage: 0) == 4.8, "idle orbit period changed")
    require(abs(RunnerOrbitAnimationPolicy.rotationPeriod(usage: 1)! - 0.9) < 0.0001, "busy orbit must complete in 0.9 seconds")
    for usage in [Double?.none, .some(.nan), .some(.infinity), .some(-1), .some(2)] {
        require(RunnerOrbitAnimationPolicy.rotationPeriod(usage: usage) == nil, "invalid CPU animated the owl")
    }
    controller.setModuleEnabled(true); controller.start()
    require(phase() == 0 && controller.menuBarImage == nil && timers.count == 1,
            "unknown CPU must show a static owl effect without an extra animal image")
    require(controller.baseIconAccessibilityLabel?.contains("CPU") == true, "owl effect lost accessible CPU state")
    let sample = timers[0]
    ticks = .init(user: 0, system: 0, nice: 0, idle: 100); sample.fireEvenIfCancelled()
    let idleAnimation = timers.last!
    for _ in 0..<48 { fire(idleAnimation) }
    require((phase() ?? 1) < 1.0 / 48, "48 idle phase steps did not complete one orbit")
    ticks = .init(user: 100, system: 0, nice: 0, idle: 100); sample.fireEvenIfCancelled()
    let busyAnimation = timers.last!
    require(busyAnimation.interval >= 1.0 / 24 && busyAnimation.interval < idleAnimation.interval,
            "busy owl did not accelerate within the 24 fps cap")
    fire(busyAnimation)
    require(abs((phase() ?? 0) - 2.0 / 48) < 0.0001, "busy orbit incorrectly uses one phase per capped tick")
    let selectedPalette = PluginOrbitPalette(startRGB: 0xFFAA00, endRGB: 0x00AA44)
    let unchangedPhase = phase()!
    let timerCount = timers.count
    var paletteUpdates = 0
    let paletteSubscription = controller.imageChanges.sink { paletteUpdates += 1 }
    controller.setOrbitPalette(selectedPalette)
    require(controller.palette == selectedPalette && RunnerSettings(defaults: defaults).palette == selectedPalette,
            "live palette selection was not persisted")
    require(controller.baseIconEffect == .orbit(phase: unchangedPhase, palette: selectedPalette)
            && paletteUpdates == 1, "palette did not update the active output immediately")
    require(timers.count == timerCount && !busyAnimation.cancelled && phase() == unchangedPhase,
            "palette change altered animation timers or phase")
    controller.setOrbitPalette(selectedPalette)
    require(paletteUpdates == 1, "same palette selection republished output")
    var hostChanges = 0
    let subscription = controller.changes.sink { hostChanges += 1 }
    for _ in 0..<24 { fire(busyAnimation) }
    require(hostChanges == 0, "owl animation invalidated whole-app feature data")
    let phaseBeforeDelay = phase()!
    uptime += 0.45; busyAnimation.fireEvenIfCancelled()
    let expectedAfterDelay = (phaseBeforeDelay + 0.5).truncatingRemainder(dividingBy: 1)
    require(abs(phase()! - expectedAfterDelay) <= 1.0 / 48 + 0.0001,
            "delayed callback slowed orbit instead of advancing by actual monotonic time")
    let phaseBeforeSpeedChange = phase()!
    uptime += 20
    ticks = .init(user: 175, system: 0, nice: 0, idle: 125); sample.fireEvenIfCancelled()
    require(phase() == phaseBeforeSpeedChange, "CPU speed change jumped the visible phase")
    fire(busyAnimation)
    require(abs(phase()! - phaseBeforeSpeedChange) <= 2.0 / 48,
            "same-fps speed change did not reset the monotonic time baseline")
    motion.reduceMotion = true; controller.refreshDisplayPreferences()
    require(busyAnimation.cancelled && !sample.cancelled && phase() == 0, "Reduce Motion must reset the light and retain sampling")
    busyAnimation.fireEvenIfCancelled()
    require(phase() == 0, "cancelled owl callback escaped Reduce Motion")
    let reducedTimerCount = timers.count
    controller.setOrbitPalette(.standard)
    require(controller.baseIconEffect == .orbit(phase: 0, palette: .standard)
            && controller.palette == .standard && timers.count == reducedTimerCount,
            "Reduce Motion blocked a static palette update or restarted animation")
    motion.reduceMotion = false; motion.lowPower = true; controller.refreshDisplayPreferences()
    let lowPowerAnimation = timers.last!
    require(lowPowerAnimation.interval >= 1.0 / 12, "low power orbit exceeded 12 fps")
    fire(lowPowerAnimation)
    controller.suspendForSleep()
    require(controller.baseIconEffect == nil && controller.baseIconAccessibilityLabel == nil,
            "sleep retained an owl light or accessible state")
    lowPowerAnimation.fireEvenIfCancelled(); sample.fireEvenIfCancelled()
    require(controller.baseIconEffect == nil, "cancelled callback restored sleeping light")
    controller.resumeAfterSleep()
    require(phase() == 0 && controller.usage == nil, "wake did not reset orbit and CPU baseline")
    fails = true; controller.refreshData()
    require(phase() == 0 && controller.usage == nil, "failed CPU must use a static phase")
    controller.selectAnimal(.rabbit); controller.selectPresentation(.animal)
    require(controller.menuBarImage != nil && controller.baseIconEffect == nil, "animal mode retained owl overlay")
    controller.selectPresentation(.owlOrbit)
    require(controller.menuBarImage == nil && phase() == 0 && controller.animal == .rabbit,
            "switching to owl lost saved animal or retained duplicate image")
    require(RunnerSettings(defaults: defaults).presentation == .owlOrbit, "live presentation selection did not persist")
    controller.stop(); controller.stop()
    for timer in timers { timer.fireEvenIfCancelled() }
    require(controller.baseIconEffect == nil && controller.baseIconAccessibilityLabel == nil
            && controller.menuBarImage == nil && timers.allSatisfy(\.cancelled), "stop leaked owl animation or light")
    controller.setOrbitPalette(selectedPalette)
    require(controller.baseIconEffect == nil && controller.menuBarImage == nil,
            "changing a stopped palette restored menu bar output")
    withExtendedLifetime((subscription, paletteSubscription)) {}
    print("PASS owl orbit: default/persisted mode, 48 phases, 4.8–0.9s periods, 24/12 fps caps, CPU AX, motion/sleep/stop reset and animal compatibility")
}

@MainActor
func checkControllerMetricsLifecycle() {
    let name = "happylulu-runner-metrics-" + UUID().uuidString
    let defaults = UserDefaults(suiteName: name)!
    defer { defaults.removePersistentDomain(forName: name) }
    let metrics = FixtureSystemMetrics()
    var ticks: UInt64 = 0
    var timers: [FixtureTimer] = []
    let controller = CPURunnerController(settings: RunnerSettings(defaults: defaults),
        sampler: CPUUsageSampler(readTicks: {
            ticks += 100
            return CPUUsageTicks(user: ticks, system: 0, nice: 0, idle: ticks)
        }), metricsSampler: metrics.sampler(),
        schedule: { interval, action in
            let timer = FixtureTimer(interval: interval, action: action); timers.append(timer); return timer
        }, reduceMotion: { false }, lowPower: { false }, observeSystemChanges: false)
    controller.start(); controller.refreshData()
    require(metrics.readCounts == [0, 0, 0, 0] && controller.metrics == .empty,
            "disabled controller sampled system metrics")
    controller.setModuleEnabled(true); controller.start(); controller.start()
    require(metrics.readCounts == [1, 1, 1, 1], "initial metrics sampling was missing or duplicated")
    require(controller.metrics.memory?.usedBytes == 12_884_901_888
        && controller.metrics.storage?.availableBytes == 640_000_000_000
        && controller.metrics.battery?.percent == 76,
            "controller did not expose injected memory, storage and battery")
    require(controller.metrics.network?.isConnected == true
        && controller.metrics.network?.receivedBytesPerSecond == nil,
            "initial network snapshot must show connectivity without fabricating a rate")
    let sample = timers[0]
    metrics.time = 1; metrics.received = 1_100; metrics.sent = 2_200
    sample.fireEvenIfCancelled()
    require(controller.metrics.network?.receivedBytesPerSecond == 100
        && controller.metrics.network?.sentBytesPerSecond == 200, "controller lost sampled network deltas")
    var hostChanges = 0, publishedMetrics: [SystemMetricsSnapshot] = []
    let hostObservation = controller.changes.sink { hostChanges += 1 }
    let metricsObservation = controller.$metrics.dropFirst().sink { publishedMetrics.append($0) }
    metrics.time = 2; metrics.received = 1_400; metrics.sent = 2_400
    metrics.memoryUsed = 9 * 1_024 * 1_024 * 1_024
    sample.fireEvenIfCancelled()
    require(controller.metrics.network?.receivedBytesPerSecond == 300
        && controller.metrics.memory?.usedBytes == 9_663_676_416
        && publishedMetrics.last?.memory?.usedBytes == 9_663_676_416,
            "later metrics samples did not reach the observed controller snapshot")
    require(metrics.readCounts == [3, 1, 3, 1], "fast and slow metrics did not retain their sampling cadence")
    let animation = timers.last!, counts = metrics.readCounts
    let publicationCount = publishedMetrics.count
    for _ in 0..<16 { animation.fireEvenIfCancelled() }
    controller.refreshDisplayPreferences(); controller.selectAnimal(.cat)
    require(metrics.readCounts == counts && publishedMetrics.count == publicationCount,
            "animation or presentation preferences resampled system metrics")
    require(hostChanges == 0, "metrics updates invalidated host feature/calendar state")
    controller.suspendForSleep()
    require(controller.metrics == .empty, "sleep retained stale metrics")
    for timer in timers { timer.fireEvenIfCancelled() }
    controller.refreshData()
    require(metrics.readCounts == counts && controller.metrics == .empty, "sleep allowed a stale sample callback")
    metrics.time = 100; metrics.received = 100_000; metrics.sent = 200_000
    controller.resumeAfterSleep(); controller.resumeAfterSleep()
    require(metrics.readCounts == [4, 2, 4, 2]
        && controller.metrics.network?.receivedBytesPerSecond == nil
        && controller.metrics.network?.sentBytesPerSecond == nil,
            "wake did not reset slow caches and network baselines exactly once")
    let wakeSample = timers.last!
    metrics.time = 101; metrics.received = 100_500; metrics.sent = 200_250
    wakeSample.fireEvenIfCancelled()
    require(controller.metrics.network?.receivedBytesPerSecond == 500
        && controller.metrics.network?.sentBytesPerSecond == 250, "wake network rate included sleeping traffic")
    require(hostChanges == 2, "only CPU availability transitions should reach the host across sleep/wake")
    controller.stop()
    require(controller.metrics == .empty, "stop retained stale metrics")
    let stoppedCounts = metrics.readCounts
    for timer in timers { timer.fireEvenIfCancelled() }
    controller.refreshData(); controller.resumeAfterSleep()
    require(metrics.readCounts == stoppedCounts && controller.metrics == .empty, "stopped controller read or republished metrics")
    metrics.time = 200; metrics.received = 1_000_000; metrics.sent = 2_000_000
    controller.start()
    require(controller.metrics.network?.receivedBytesPerSecond == nil
        && controller.metrics.network?.sentBytesPerSecond == nil,
            "restart reused the stopped network delta")
    controller.stop()
    metrics.unavailable = true
    controller.start()
    require(controller.metrics == .empty, "unavailable metric readers fabricated values")
    controller.stop()
    withExtendedLifetime((hostObservation, metricsObservation)) {}
    print("PASS controller metrics: injected reads, opt-in, published samples, bounded cadence, frame isolation, sleep/wake baselines, stop/restart and unavailable values")
}

@MainActor
final class FixtureImageProvider: PluginMenuBarImageProviding {
    let descriptor = PluginDescriptor(id: "image-fixture", name: "Image fixture")
    let updates = PassthroughSubject<Void, Never>()
    var changes: AnyPublisher<Void, Never> { Empty().eraseToAnyPublisher() }
    var imageChanges: AnyPublisher<Void, Never> { updates.eraseToAnyPublisher() }
    let enabled = true
    let isRunning = false
    let connectionState = PluginConnectionState.ready
    var menuBarImage: PluginMenuBarImage?
    func start() {}
    func stop() { menuBarImage = nil; updates.send() }
    func refreshData() {}
}

@MainActor
func checkGroupedRendering() {
    func rectangle(width: CGFloat) -> NSImage {
        let image = NSImage(size: NSSize(width: width, height: 18), flipped: false) { rect in
            NSColor.black.setFill(); rect.fill(); return true
        }
        image.isTemplate = true
        return image
    }
    let owl = rectangle(width: 8), runner = rectangle(width: 6)
    let provider = FixtureImageProvider()
    let group = PluginMenuBarImageGroup()
    require(group.image(base: owl) === owl, "absent runner must preserve the owl image")
    provider.menuBarImage = PluginMenuBarImage(image: runner, accessibilityLabel: "Runner CPU 50%")
    group.setProviders([provider])
    group.setProviders([provider])
    var updates = 0
    let observation = group.changes.sink { updates += 1 }
    let image = group.image(base: owl)
    require(image.size == NSSize(width: 18, height: 18) && image.isTemplate,
            "group must keep owl then gap then runner in one template canvas")
    for scale in [1, 2] {
        let rep = image.representations.compactMap { $0 as? NSBitmapImageRep }.first { $0.pixelsWide == 18 * scale }!
        require((rep.colorAt(x: 4 * scale, y: 9 * scale)?.alphaComponent ?? 0) > 0.9, "owl missing from grouped native render")
        require((rep.colorAt(x: 9 * scale, y: 9 * scale)?.alphaComponent ?? 1) < 0.1, "gap between owl and runner missing")
        require((rep.colorAt(x: 14 * scale, y: 9 * scale)?.alphaComponent ?? 0) > 0.9, "runner missing from grouped native render")
    }
    require(group.accessibilityLabels == ["Runner CPU 50%"], "group dropped runner accessibility")
    provider.updates.send()
    require(updates == 1, "provider reconciliation duplicated animation subscriptions")
    provider.stop()
    require(group.image(base: owl) === owl && group.accessibilityLabels.isEmpty,
            "stopping runner must clear only its image and accessibility")
    group.setProviders([])
    provider.updates.send()
    require(updates == 2, "removed plugin still invalidates grouped image")
    withExtendedLifetime(observation) {}

    let icon = rectangle(width: 14)
    let png = NSBitmapImageRep(data: icon.tiffRepresentation!)!.representation(using: .png, properties: [:])!
    let title = PluginMenuBarTitle.attributed(base: "Leave 18:00", items: [
        PluginMenuBarItem(id: "text", title: "Claude 30%", accessibilityLabel: "Claude 30%"),
        PluginMenuBarItem(id: "icon", title: "42%", accessibilityLabel: "Codex 42%", iconPNG: png)
    ], font: .systemFont(ofSize: 12))
    require(title.string == " Leave 18:00 · Claude 30% · \u{fffc} 42%", "inline icon reordered time, provider or percentage")
    var attachments = 0
    title.enumerateAttribute(.attachment, in: NSRange(location: 0, length: title.length)) { value, _, _ in
        if let attachment = value as? NSTextAttachment {
            attachments += 1
            require(attachment.image != nil && attachment.bounds.size == NSSize(width: 14, height: 14),
                    "inline provider icon lost native image or menu-bar sizing")
        }
    }
    require(attachments == 1, "inline icon was not rendered as native attributed title content")
    let fallback = PluginMenuBarTitle.attributed(base: "Ready", items: [
        PluginMenuBarItem(id: "invalid", title: "Codex 42%", accessibilityLabel: "Codex 42%", iconPNG: Data([0]))
    ], font: .systemFont(ofSize: 12))
    require(fallback.string == " Ready · Codex 42%", "invalid optional icon hid readable provider text")
    print("PASS grouped native render: owl/gap/runner at 1x/2x, AX, stop/removal, unique subscriptions and inline icon/percentage title")
}

@MainActor
func renderView<V: View>(_ view: V, size: NSSize, dark: Bool, to url: URL) throws {
    let hosting = NSHostingView(rootView: view)
    let window = NSWindow(contentRect: NSRect(origin: NSPoint(x: -2000, y: -2000), size: size),
        styleMask: [.borderless], backing: .buffered, defer: false)
    window.isReleasedWhenClosed = false
    window.appearance = NSAppearance(named: dark ? .darkAqua : .aqua)
    window.contentView = hosting
    hosting.frame = NSRect(origin: .zero, size: size)
    hosting.layoutSubtreeIfNeeded(); hosting.displayIfNeeded()
    guard let bitmap = hosting.bitmapImageRepForCachingDisplay(in: hosting.bounds) else {
        throw NSError(domain: "RunnerRender", code: 1)
    }
    hosting.cacheDisplay(in: hosting.bounds, to: bitmap)
    guard let png = bitmap.representation(using: .png, properties: [:]) else {
        throw NSError(domain: "RunnerRender", code: 2)
    }
    try png.write(to: url)
    window.close()
}

@MainActor
func renderSettings(to folder: URL) throws {
    _ = NSApplication.shared
    try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    let name = "happylulu-runner-render-" + UUID().uuidString
    let defaults = UserDefaults(suiteName: name)!
    defer { defaults.removePersistentDomain(forName: name) }
    RunnerSettings(defaults: defaults).presentation = .animal
    for language in ["ko", "en"] {
        var reads = 0
        let metrics = FixtureSystemMetrics()
        let localize: PluginLocalizer = { korean, english in language == "ko" ? korean : english }
        let controller = CPURunnerController(settings: RunnerSettings(defaults: defaults),
            sampler: CPUUsageSampler(readTicks: {
                reads += 1
                return reads == 1 ? .init(user: 0, system: 0, nice: 0, idle: 0)
                    : .init(user: 35, system: 0, nice: 0, idle: 65)
            }), metricsSampler: metrics.sampler(), displayFactory: { _ in FixtureDisplay() },
            schedule: { FixtureTimer(interval: $0, action: $1) }, reduceMotion: { false }, lowPower: { false },
            observeSystemChanges: false, localize: localize)
        for dark in [false, true] {
            controller.stop(); reads = 0
            metrics.unavailable = false; metrics.time = 0; metrics.received = 1_000; metrics.sent = 2_000
            controller.setModuleEnabled(true); controller.start()
            metrics.time = 1; metrics.received = 8_501_000; metrics.sent = 1_202_000
            controller.refreshData()
            require(controller.usage == 0.35 && controller.metrics.network?.receivedBytesPerSecond == 8_500_000,
                    "render lost synthetic CPU or system metrics fixture")
            controller.selectPresentation(.owlOrbit)
            let owlSettings = CPURunnerSettingsView(model: controller, localize: localize)
                .padding(16).frame(width: 500, height: 580, alignment: .topLeading)
                .background(dark ? Color(NSColor.windowBackgroundColor) : Color.white)
                .environment(\.colorScheme, dark ? .dark : .light)
            try renderView(owlSettings, size: NSSize(width: 500, height: 580), dark: dark,
                to: folder.appendingPathComponent("runner-settings-\(language)-\(dark ? "dark" : "light")-owl-orbit.png"))
            controller.selectPresentation(.animal)
            for animal in RunnerAnimal.allCases {
                controller.selectAnimal(animal)
                let view = CPURunnerSettingsView(model: controller, localize: localize)
                    .padding(16).frame(width: 500, height: 580, alignment: .topLeading)
                    .background(dark ? Color(NSColor.windowBackgroundColor) : Color.white)
                    .environment(\.colorScheme, dark ? .dark : .light)
                let filename = "runner-settings-\(language)-\(dark ? "dark" : "light")-\(animal.rawValue).png"
                try renderView(view, size: NSSize(width: 500, height: 580), dark: dark,
                    to: folder.appendingPathComponent(filename))
            }
            for unavailable in [false, true] {
                if unavailable {
                    controller.stop(); metrics.unavailable = true; controller.start()
                    require(controller.usage == nil && controller.metrics == .empty,
                            "unavailable summary render retained measured values")
                }
                let summary = RunnerMetricsSummaryView(model: controller, localize: localize)
                    .frame(width: 332, height: 172)
                    .background(dark ? Color(NSColor.windowBackgroundColor) : Color.white)
                    .environment(\.colorScheme, dark ? .dark : .light)
                let filename = "runner-summary-\(language)-\(dark ? "dark" : "light")-\(unavailable ? "unavailable" : "measured").png"
                try renderView(summary, size: NSSize(width: 332, height: 172), dark: dark,
                    to: folder.appendingPathComponent(filename))
            }
        }
        controller.stop()
    }
    print("PASS settings render: 16 files at 500x580pt, owl orbit/all animals, Korean/English, light/dark, injected CPU/memory/storage/network/battery")
    print("PASS summary render: 8 files at 332x172pt, Korean/English, light/dark, measured and unavailable metrics")
}

await MainActor.run {
    checkCPUUsage()
    checkSettings()
    checkLifecycle()
    checkOwlOrbit()
    checkGroupedRendering()
    checkControllerMetricsLifecycle()
}
if CommandLine.arguments.count == 3, CommandLine.arguments[1] == "--render-dir" {
    try await MainActor.run { try renderSettings(to: URL(fileURLWithPath: CommandLine.arguments[2], isDirectory: true)) }
}
