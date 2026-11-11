import Foundation
import UserNotifications
import AVFoundation

/// Told whenever the rest timer starts, changes or stops, so something outside the app (a notification, a Live Activity) can follow it.
public protocol RestAlerting {
    func update(rest: RestTimer)
}

/// Rings the ring bell (`RestBell.wav` in the app bundle) when a rest ends, whatever the phone is doing.
/// While a rest runs the app plays inaudible audio so iOS keeps it awake (the `audio` background mode), then rings the bell
/// itself, which sounds with the screen locked and on the silent switch. A silent local notification covers the lock screen.
public final class LocalNotificationRestAlerts: NSObject, RestAlerting, UNUserNotificationCenterDelegate, AVAudioPlayerDelegate {
    private let center = UNUserNotificationCenter.current()
    private let identifier = "forge.rest.end"
    private var bellPlayer: AVAudioPlayer?
    private var keepAlive: AVAudioPlayer?
    private var ringTask: Task<Void, Never>?

    public override init() {
        super.init()
        center.delegate = self
        // Ask up front so the prompt isn't left unanswered behind a workout screen.
        center.requestAuthorization(options: [.alert]) { _, _ in }
    }

    public func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification) async -> UNNotificationPresentationOptions {
        notification.request.identifier == identifier ? [] : [.banner, .sound]
    }

    public func update(rest: RestTimer) {
        center.removePendingNotificationRequests(withIdentifiers: [identifier])
        ringTask?.cancel()
        guard let end = rest.endsAt, end.timeIntervalSinceNow > 0 else {
            Task { @MainActor [weak self] in self?.stopKeepAlive(); self?.releaseSession() }
            return
        }
        ringTask = Task { @MainActor [weak self] in
            self?.startKeepAlive()
            try? await Task.sleep(for: .seconds(max(0, end.timeIntervalSinceNow)))
            guard !Task.isCancelled else { return }
            self?.ring()
        }
        guard end.timeIntervalSinceNow > 1 else { return }
        center.requestAuthorization(options: [.alert]) { [center, identifier] granted, _ in
            guard granted else { return }
            let content = UNMutableNotificationContent()
            content.title = "Rest over"
            content.body = "Time for your next set."
            let trigger = UNTimeIntervalNotificationTrigger(timeInterval: max(1, end.timeIntervalSinceNow), repeats: false)
            center.add(UNNotificationRequest(identifier: identifier, content: content, trigger: trigger))
        }
    }

    @MainActor private func startKeepAlive() {
        guard keepAlive?.isPlaying != true else { return }
        #if os(iOS)
        try? AVAudioSession.sharedInstance().setCategory(.playback, options: [.mixWithOthers])
        try? AVAudioSession.sharedInstance().setActive(true)
        #endif
        keepAlive = try? AVAudioPlayer(data: Self.silence)
        keepAlive?.numberOfLoops = -1
        keepAlive?.volume = 0
        keepAlive?.play()
    }

    @MainActor private func stopKeepAlive() {
        keepAlive?.stop()
        keepAlive = nil
    }

    @MainActor private func ring() {
        stopKeepAlive()
        guard let url = Bundle.main.url(forResource: "RestBell", withExtension: "wav") else { return releaseSession() }
        #if os(iOS)
        try? AVAudioSession.sharedInstance().setCategory(.playback, options: [.duckOthers])
        try? AVAudioSession.sharedInstance().setActive(true)
        #endif
        bellPlayer = try? AVAudioPlayer(contentsOf: url)
        bellPlayer?.delegate = self
        if bellPlayer?.play() != true { releaseSession() }
    }

    public func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        center.removeDeliveredNotifications(withIdentifiers: [identifier])     // the banner has done its job once the bell has rung
        Task { @MainActor [weak self] in self?.bellPlayer = nil; self?.releaseSession() }
    }

    /// Hands the audio back to whatever was playing before the bell.
    @MainActor private func releaseSession() {
        #if os(iOS)
        guard bellPlayer == nil, keepAlive == nil else { return }
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
        #endif
    }

    /// One second of silence as a WAV (8 kHz, 16-bit mono).
    private static let silence: Data = {
        let samples = 8000, bytes = samples * 2
        var d = Data()
        func u32(_ v: Int) { withUnsafeBytes(of: UInt32(v).littleEndian) { d.append(contentsOf: $0) } }
        func u16(_ v: Int) { withUnsafeBytes(of: UInt16(v).littleEndian) { d.append(contentsOf: $0) } }
        d.append(contentsOf: Array("RIFF".utf8)); u32(36 + bytes); d.append(contentsOf: Array("WAVEfmt ".utf8))
        u32(16); u16(1); u16(1); u32(8000); u32(16000); u16(2); u16(16)
        d.append(contentsOf: Array("data".utf8)); u32(bytes); d.append(Data(count: bytes))
        return d
    }()
}

/// Fans one update out to several listeners.
public struct CombinedRestAlerts: RestAlerting {
    let parts: [RestAlerting]
    public init(_ parts: [RestAlerting]) { self.parts = parts }
    public func update(rest: RestTimer) { parts.forEach { $0.update(rest: rest) } }
}
