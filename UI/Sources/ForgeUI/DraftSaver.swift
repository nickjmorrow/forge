import ForgeCore
import Foundation

/// Writes the in-progress workout to disk off the main thread. Typing is debounced (a burst of keystrokes is one write);
/// anything structural is written promptly. Clearing wins over a write that has not happened yet.
final class DraftSaver: @unchecked Sendable {
    private let store: DraftStore
    private let queue = DispatchQueue(label: "forge.draft-saver", qos: .utility)
    private let lock = NSLock()
    private var pending: WorkoutDraft?
    private var delayedWriteScheduled = false
    private let typingDelay: TimeInterval

    init(store: DraftStore, typingDelay: TimeInterval = 0.35) {
        self.store = store
        self.typingDelay = typingDelay
    }

    /// For edits that arrive in bursts (typing): the latest state is written after a short pause.
    func saveSoon(_ draft: WorkoutDraft) {
        lock.lock()
        pending = draft
        let schedule = !delayedWriteScheduled
        delayedWriteScheduled = true
        lock.unlock()
        if schedule { queue.asyncAfter(deadline: .now() + typingDelay) { [self] in writePending() } }
    }

    /// For edits that must not be lost (a set ticked off, an exercise added): written as soon as the queue is free.
    func saveNow(_ draft: WorkoutDraft) {
        lock.lock()
        pending = draft
        lock.unlock()
        queue.async { [self] in writePending() }
    }

    func clear() {
        lock.lock()
        pending = nil
        lock.unlock()
        queue.async { [store] in store.clear() }
    }

    /// Waits until everything asked for so far is on disk (used when the app is leaving the foreground, and by tests).
    func flush() { queue.sync { writePending() } }

    private func writePending() {
        lock.lock()
        let draft = pending
        pending = nil
        delayedWriteScheduled = false
        lock.unlock()
        if let draft { store.save(draft) }
    }
}
