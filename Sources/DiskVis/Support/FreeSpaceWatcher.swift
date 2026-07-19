import Foundation
import Observation
import UserNotifications

/// Polls volume free space for the menu-bar extra, keeps a 30-day history of
/// the startup disk, and fires a low-space notification at most once per day.
@MainActor
@Observable
final class FreeSpaceWatcher {
    static let sampleDefaultsKey = "freeSpaceSamples"
    static let alertsEnabledKey = "lowSpaceAlertsEnabled"
    static let thresholdKey = "lowSpaceThresholdGB"
    static let lastAlertDayKey = "lowSpaceLastAlertDay"

    var volumes: [VolumeInfo] = []
    /// "yyyy-MM-dd" → free bytes on the startup volume.
    var samples: [String: Int64] = [:]

    private var timer: Timer?

    var startupFree: Int64 {
        volumes.first { $0.url.path == "/" }?.free ?? 0
    }

    var sortedSamples: [(day: String, free: Int64)] {
        samples.sorted { $0.key < $1.key }.map { ($0.key, $0.value) }
    }

    init() {
        samples = (UserDefaults.standard.dictionary(forKey: Self.sampleDefaultsKey) ?? [:])
            .compactMapValues { ($0 as? NSNumber)?.int64Value }
        refresh()
        timer = Timer.scheduledTimer(withTimeInterval: 300, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.refresh() }
        }
    }

    func refresh() {
        volumes = VolumeInfo.mounted()
        recordSample()
        checkLowSpace()
    }

    private static let dayFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        return f
    }()

    private func recordSample() {
        guard startupFree > 0 else { return }
        let today = Self.dayFormatter.string(from: Date())
        samples[today] = startupFree
        // Keep the newest 30 days
        if samples.count > 30 {
            for key in samples.keys.sorted().dropLast(30) {
                samples.removeValue(forKey: key)
            }
        }
        UserDefaults.standard.set(samples.mapValues { NSNumber(value: $0) }, forKey: Self.sampleDefaultsKey)
    }

    private func checkLowSpace() {
        let defaults = UserDefaults.standard
        guard defaults.bool(forKey: Self.alertsEnabledKey), Bundle.main.bundleIdentifier != nil else { return }
        let thresholdGB = defaults.double(forKey: Self.thresholdKey)
        // Clamp before the multiply: an absurd user-entered value (e.g. a
        // fat-fingered extra digit) must never overflow Int64 and crash.
        let clampedGB = min(max(thresholdGB > 0 ? thresholdGB : 20, 0), 1_000_000)
        let threshold = Int64(clampedGB * 1_000_000_000)
        guard startupFree > 0, startupFree < threshold else { return }

        let today = Self.dayFormatter.string(from: Date())
        guard defaults.string(forKey: Self.lastAlertDayKey) != today else { return }
        defaults.set(today, forKey: Self.lastAlertDayKey)

        let content = UNMutableNotificationContent()
        content.title = "Disk space is low"
        content.body = "Only \(Format.bytes(startupFree)) free on your startup disk. Open DiskVis to free some up."
        content.sound = .default
        let request = UNNotificationRequest(
            identifier: "diskvis-low-space-\(today)",
            content: content,
            trigger: nil
        )
        UNUserNotificationCenter.current().add(request)
    }

    static func requestNotificationPermission() {
        guard Bundle.main.bundleIdentifier != nil else { return }
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { _, _ in }
    }
}
