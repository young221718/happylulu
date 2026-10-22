import AppKit
import SwiftUI
import Combine
import AppPluginCore
import AppPluginHost

@MainActor
public protocol RunnerScheduledTask: AnyObject { func cancel() }

@MainActor
public protocol RunnerStatusDisplaying: AnyObject {
    func render(animal: RunnerAnimal, frame: Int, usageText: String, accessibilityLabel: String)
    func remove()
}

public typealias RunnerScheduler = @MainActor (TimeInterval, @escaping @MainActor () -> Void) -> any RunnerScheduledTask
public typealias RunnerDisplayFactory = @MainActor (@escaping @MainActor (RunnerAnimal) -> Void) -> any RunnerStatusDisplaying

public enum RunnerOrbitAnimationPolicy {
    public static let frameCount = 48

    public static func rotationPeriod(usage: Double?) -> TimeInterval? {
        guard let usage, usage.isFinite, (0...1).contains(usage) else { return nil }
        return 4.8 - 3.9 * usage
    }

    public static func frameInterval(usage: Double?, reduceMotion: Bool, lowPower: Bool) -> TimeInterval? {
        guard !reduceMotion, let period = rotationPeriod(usage: usage) else { return nil }
        return 1 / min(lowPower ? 12 : 24, Double(frameCount) / period)
    }
}

@MainActor
private final class RunnerTimer: RunnerScheduledTask {
    private let timer: Timer
    init(interval: TimeInterval, action: @escaping @MainActor () -> Void) {
        timer = Timer(timeInterval: interval, repeats: true) { _ in
            Task { @MainActor in action() }
        }
        timer.tolerance = min(0.1, interval * 0.15)
        RunLoop.main.add(timer, forMode: .common)
    }
    func cancel() { timer.invalidate() }
}

@MainActor
public final class CPURunnerController: ObservableObject, PluginMenuBarImageProviding, PluginPanelProviding {
    public let descriptor: PluginDescriptor
    public private(set) var menuBarImage: PluginMenuBarImage?
    public private(set) var baseIconEffect: PluginBaseIconEffect?
    public private(set) var baseIconAccessibilityLabel: String?
    private let imageUpdates = PassthroughSubject<Void, Never>()
    public var imageChanges: AnyPublisher<Void, Never> { imageUpdates.eraseToAnyPublisher() }
    @Published public private(set) var enabled = false
    @Published public private(set) var animal: RunnerAnimal
    @Published public private(set) var presentation: RunnerPresentation
    @Published public private(set) var palette: PluginOrbitPalette
    @Published public private(set) var usage: Double?
    @Published public private(set) var metrics = SystemMetricsSnapshot.empty
    public var panelView: AnyView { AnyView(RunnerMetricsSummaryView(model: self, localize: localize)) }
    public var panelHeight: CGFloat { 184 }
    public private(set) var isActive = false
    public var isRunning: Bool { false }
    public var connectionState: PluginConnectionState {
        !enabled || !isActive ? .off : usage == nil ? .connecting : .ready
    }
    public var changes: AnyPublisher<Void, Never> {
        // CPU presentation updates must not invalidate calendar/agenda data in the host.
        $enabled.removeDuplicates()
            .combineLatest($usage.map { $0 != nil }.removeDuplicates())
            .dropFirst().map { _ in () }.eraseToAnyPublisher()
    }
    public var usageText: String {
        guard let usage else { return localize("CPU · 확인 중/사용 불가", "CPU · pending/unavailable") }
        return "CPU \(Int((usage * 100).rounded()))%"
    }
    private let settings: RunnerSettings
    private let sampler: CPUUsageSampler
    private let metricsSampler: SystemMetricsSampler
    private let displayFactory: RunnerDisplayFactory?
    private let schedule: RunnerScheduler
    private let reduceMotion: @MainActor () -> Bool
    private let lowPower: @MainActor () -> Bool
    private let observeSystemChanges: Bool
    private let localize: PluginLocalizer
    private let now: @MainActor () -> TimeInterval
    private var display: (any RunnerStatusDisplaying)?
    private var sampleTimer: (any RunnerScheduledTask)?
    private var frameTimer: (any RunnerScheduledTask)?
    private var observers: [(NotificationCenter, NSObjectProtocol)] = []
    private var asleep = false
    private var frame = 0
    private var generation = 0
    private var animationGeneration = 0
    private var frameInterval: TimeInterval?
    private var orbitProgress = 0.0
    private var orbitTimestamp: TimeInterval?
    private var orbitPeriod: TimeInterval?

    public convenience init(defaults: UserDefaults = .standard,
                            localize: @escaping PluginLocalizer = { korean, _ in korean }) {
        self.init(settings: RunnerSettings(defaults: defaults), sampler: CPUUsageSampler(),
            schedule: { RunnerTimer(interval: $0, action: $1) },
            reduceMotion: { NSWorkspace.shared.accessibilityDisplayShouldReduceMotion },
            lowPower: { ProcessInfo.processInfo.isLowPowerModeEnabled }, localize: localize)
    }

    public init(settings: RunnerSettings, sampler: CPUUsageSampler,
                metricsSampler: SystemMetricsSampler = SystemMetricsSampler(),
                displayFactory: RunnerDisplayFactory? = nil, schedule: @escaping RunnerScheduler,
                reduceMotion: @escaping @MainActor () -> Bool, lowPower: @escaping @MainActor () -> Bool,
                observeSystemChanges: Bool = true,
                now: @escaping @MainActor () -> TimeInterval = { ProcessInfo.processInfo.systemUptime },
                localize: @escaping PluginLocalizer = { korean, _ in korean }) {
        self.settings = settings; self.sampler = sampler; self.metricsSampler = metricsSampler; self.displayFactory = displayFactory
        self.schedule = schedule; self.reduceMotion = reduceMotion; self.lowPower = lowPower
        self.observeSystemChanges = observeSystemChanges; self.localize = localize
        self.now = now
        animal = settings.animal; presentation = settings.presentation; palette = settings.palette
        descriptor = PluginDescriptor(id: CPURunnerModule.id, name: localize("시스템 러너", "System Runner"))
    }

    public func setModuleEnabled(_ value: Bool) {
        guard enabled != value else { return }
        enabled = value
        if !value { stop() }
    }

    public func selectAnimal(_ value: RunnerAnimal) {
        guard animal != value else { return }
        settings.animal = value; animal = value; frame = 0; render()
    }

    public func selectPresentation(_ value: RunnerPresentation) {
        guard presentation != value else { return }
        settings.presentation = value; presentation = value; frame = 0; orbitProgress = 0
        if value == .owlOrbit { display?.remove(); display = nil }
        guard enabled, isActive, !asleep else { return }
        updateAnimation(); render()
    }

    public func setOrbitPalette(_ value: PluginOrbitPalette) {
        guard palette != value else { return }
        settings.palette = value; palette = value
        if presentation == .owlOrbit { render() }
    }

    public func start() {
        guard enabled, !isActive else { return }
        isActive = true; asleep = false; generation += 1
        if observeSystemChanges { installObservers() }
        resumeMonitoring()
    }

    public func stop() {
        generation += 1; isActive = false; asleep = false
        cancelTimers(); sampler.reset(); usage = nil; frame = 0
        metricsSampler.reset(); metrics = .empty
        display?.remove(); display = nil
        clearPresentation()
        for (center, observer) in observers { center.removeObserver(observer) }
        observers.removeAll()
    }

    public func refreshData() {
        guard enabled, isActive, !asleep else { return }
        sampleCPU()
    }

    public func suspendForSleep() {
        guard isActive, !asleep else { return }
        asleep = true; generation += 1
        cancelTimers(); sampler.reset(); usage = nil; frame = 0; render()
        metricsSampler.reset(); metrics = .empty
    }

    public func resumeAfterSleep() {
        guard enabled, isActive, asleep else { return }
        asleep = false; generation += 1; resumeMonitoring()
    }

    public func refreshDisplayPreferences() {
        guard enabled, isActive, !asleep else { return }
        updateAnimation(); render()
    }

    private func resumeMonitoring() {
        sampler.reset()
        metricsSampler.reset()
        sampleCPU()
        let current = generation
        sampleTimer = schedule(1) { [weak self] in
            guard let self, self.generation == current, self.isActive, !self.asleep else { return }
            self.sampleCPU()
        }
    }

    private func sampleCPU() {
        usage = sampler.sample()
        metrics = metricsSampler.sample()
        updateAnimation(); render()
    }

    private func updateAnimation() {
        let reduced = reduceMotion(), power = lowPower()
        let next = presentation == .owlOrbit
            ? RunnerOrbitAnimationPolicy.frameInterval(usage: usage, reduceMotion: reduced, lowPower: power)
            : RunnerAnimationPolicy.frameInterval(usage: usage, reduceMotion: reduced, lowPower: power)
        let period = presentation == .owlOrbit && next != nil ? RunnerOrbitAnimationPolicy.rotationPeriod(usage: usage) : nil
        if orbitPeriod != period { orbitTimestamp = period == nil ? nil : now(); orbitPeriod = period }
        if next == nil { frame = 0; orbitProgress = 0; orbitTimestamp = nil }
        guard frameInterval != next else { return }
        frameTimer?.cancel(); frameTimer = nil; animationGeneration += 1; frameInterval = next
        guard let next else { frame = 0; return }
        let current = generation, animation = animationGeneration
        frameTimer = schedule(next) { [weak self] in
            guard let self, self.generation == current, self.animationGeneration == animation,
                  self.isActive, !self.asleep else { return }
            if self.presentation == .owlOrbit, let period = self.orbitPeriod {
                let timestamp = self.now()
                if let previous = self.orbitTimestamp, timestamp.isFinite, previous.isFinite, timestamp >= previous {
                    self.orbitProgress = (self.orbitProgress + (timestamp - previous) / period).truncatingRemainder(dividingBy: 1)
                }
                self.orbitTimestamp = timestamp
            } else {
                self.frame = (self.frame + 1) % RunnerArtwork.frameCount(for: self.animal)
            }
            self.render()
        }
    }

    private func cancelTimers() {
        sampleTimer?.cancel(); sampleTimer = nil
        frameTimer?.cancel(); frameTimer = nil
        animationGeneration += 1; frameInterval = nil
        orbitProgress = 0; orbitTimestamp = nil; orbitPeriod = nil
    }

    private func render() {
        guard enabled, isActive else { return }
        guard !asleep else { clearPresentation(); return }
        if presentation == .owlOrbit {
            // A completed cycle stays at phase zero despite floating-point rounding.
            let phase = Double(Int((orbitProgress * Double(RunnerOrbitAnimationPolicy.frameCount) + 1e-9).rounded(.down))
                % RunnerOrbitAnimationPolicy.frameCount) / Double(RunnerOrbitAnimationPolicy.frameCount)
            menuBarImage = nil
            baseIconEffect = .orbit(phase: phase, palette: palette)
            baseIconAccessibilityLabel = localize("happylulu 부엉이 눈빛, \(usageText)", "happylulu owl orbit, \(usageText)")
            imageUpdates.send()
            return
        }
        baseIconEffect = nil; baseIconAccessibilityLabel = nil
        if display == nil { display = displayFactory? { [weak self] in self?.selectAnimal($0) } }
        let name = localize(animal.koreanName, animal.englishName)
        let label = localize("happylulu 러너, \(name), \(usageText)", "happylulu runner, \(name), \(usageText)")
        menuBarImage = PluginMenuBarImage(image: RunnerArtwork.image(for: animal, frame: frame), accessibilityLabel: label)
        imageUpdates.send()
        display?.render(animal: animal, frame: frame, usageText: usageText, accessibilityLabel: label)
    }

    private func clearPresentation() {
        guard menuBarImage != nil || baseIconEffect != nil || baseIconAccessibilityLabel != nil else { return }
        menuBarImage = nil; baseIconEffect = nil; baseIconAccessibilityLabel = nil
        imageUpdates.send()
    }

    private func installObservers() {
        let workspace = NSWorkspace.shared.notificationCenter
        observers.append((workspace, workspace.addObserver(forName: NSWorkspace.willSleepNotification, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in self?.suspendForSleep() }
        }))
        observers.append((workspace, workspace.addObserver(forName: NSWorkspace.didWakeNotification, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in self?.resumeAfterSleep() }
        }))
        for name in [NSWorkspace.accessibilityDisplayOptionsDidChangeNotification, Notification.Name.NSProcessInfoPowerStateDidChange] {
            let center = name == NSWorkspace.accessibilityDisplayOptionsDidChangeNotification ? workspace : NotificationCenter.default
            observers.append((center, center.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                Task { @MainActor in self?.refreshDisplayPreferences() }
            }))
        }
    }
}
