//
//  TaskAccentStore.swift
//  FruitcakeAi
//
//  Local-only per-task accent color cache. The backend now persists
//  presentation.accentHex (see tasks_redesign_coordination_note.md) and
//  TaskRow PATCHes it on every color pick, so this is no longer the
//  primary persistence path — it's an optimistic latency mask: the swatch
//  tap shows the new color instantly via this store while the network
//  round-trip confirms it server-side, and a failed PATCH still leaves the
//  picked color showing locally rather than snapping back.
//

import Foundation

@MainActor
final class TaskAccentStore {
    static let shared = TaskAccentStore()

    private let defaults = UserDefaults.standard
    private func key(for taskId: Int) -> String { "task_accent_override_\(taskId)" }

    private init() {}

    func accentHex(for taskId: Int) -> String? {
        defaults.string(forKey: key(for: taskId))
    }

    func setAccentHex(_ hex: String?, for taskId: Int) {
        let key = key(for: taskId)
        if let hex {
            defaults.set(hex, forKey: key)
        } else {
            defaults.removeObject(forKey: key)
        }
    }
}
