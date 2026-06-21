//
//  TaskAccentStore.swift
//  FruitcakeAi
//
//  Local-only per-task accent color override. The backend doesn't persist
//  presentation.accentHex yet (see tasks_redesign_coordination_note.md), so
//  a user's color choice is stored device-local here until that lands —
//  it won't sync across devices or survive a backend refresh in the
//  meantime. Once the backend field exists, TaskSummary.accent already
//  prefers it over this store, so this whole file can be deleted without
//  touching call sites.
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
