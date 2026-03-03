//
//  ReminderTool.swift
//  FruitcakeAi
//
//  On-device FoundationModels tool for reading and creating Reminders.
//  Used by OnDeviceAgent when the backend is unreachable.
//  Requires NSRemindersFullAccessUsageDescription in Info.plist.
//

import Foundation
import FoundationModels
import EventKit

@available(macOS 26.0, iOS 26.0, *)
struct ReminderTool: Tool {

    let name = "manageReminders"
    let description = "Read or create Apple Reminders. Use 'list' to show pending reminders, 'create' to add a new one."

    @Generable
    struct Arguments {
        @Guide(description: "Action to perform: 'list' to show reminders, 'create' to add one")
        var action: String

        @Guide(description: "Title of the reminder to create (only used when action is 'create')")
        var title: String

        @Guide(description: "Due date for the new reminder in plain English, e.g. 'tomorrow at 9am' (optional)")
        var dueDate: String
    }

    // Shared event store — reusing avoids repeated permission prompts
    private static let store = EKEventStore()

    func call(arguments: Arguments) async throws -> String {
        let store = ReminderTool.store

        let granted = try await store.requestFullAccessToReminders()
        guard granted else {
            return "Reminders access was denied. Please grant access in Settings > Privacy & Security > Reminders."
        }

        switch arguments.action.lowercased() {
        case "list":
            return try await listReminders(store: store)
        case "create":
            return try await createReminder(
                store: store,
                title: arguments.title,
                dueDateString: arguments.dueDate
            )
        default:
            return "Unknown action '\(arguments.action)'. Use 'list' or 'create'."
        }
    }

    // MARK: - List

    private func listReminders(store: EKEventStore) async throws -> String {
        let predicate = store.predicateForReminders(in: nil)

        return try await withCheckedThrowingContinuation { continuation in
            store.fetchReminders(matching: predicate) { reminders in
                guard let reminders else {
                    continuation.resume(returning: "Could not fetch reminders.")
                    return
                }
                let pending = reminders
                    .filter { !$0.isCompleted }
                    .sorted { lhs, rhs in
                        (lhs.dueDateComponents?.date ?? .distantFuture) <
                        (rhs.dueDateComponents?.date ?? .distantFuture)
                    }

                if pending.isEmpty {
                    continuation.resume(returning: "No pending reminders.")
                    return
                }

                let lines = pending.map { reminder -> String in
                    let list = reminder.calendar.title
                    if let due = reminder.dueDateComponents?.date {
                        return "• \(reminder.title ?? "Untitled")  (due \(due.formatted(date: .abbreviated, time: .shortened)))  [\(list)]"
                    }
                    return "• \(reminder.title ?? "Untitled")  [\(list)]"
                }
                continuation.resume(returning: "Pending reminders:\n" + lines.joined(separator: "\n"))
            }
        }
    }

    // MARK: - Create

    private func createReminder(store: EKEventStore, title: String, dueDateString: String) async throws -> String {
        let trimmedTitle = title.trimmingCharacters(in: .whitespaces)
        guard !trimmedTitle.isEmpty else {
            return "A title is required to create a reminder."
        }

        let reminder = EKReminder(eventStore: store)
        reminder.title = trimmedTitle
        reminder.calendar = store.defaultCalendarForNewReminders()

        // Basic due date parsing from natural language
        if !dueDateString.isEmpty {
            let parsed = parseNaturalDate(dueDateString)
            if let date = parsed {
                let components = Calendar.current.dateComponents(
                    [.year, .month, .day, .hour, .minute],
                    from: date
                )
                reminder.dueDateComponents = components
                reminder.addAlarm(EKAlarm(absoluteDate: date))
            }
        }

        try store.save(reminder, commit: true)

        if let due = reminder.dueDateComponents?.date {
            return "Created reminder: \"\(trimmedTitle)\" due \(due.formatted(date: .abbreviated, time: .shortened))"
        }
        return "Created reminder: \"\(trimmedTitle)\""
    }

    // MARK: - Natural date helper

    private func parseNaturalDate(_ string: String) -> Date? {
        let lower = string.lowercased()
        let now = Date.now
        let cal = Calendar.current

        if lower.contains("tomorrow") {
            var result = cal.date(byAdding: .day, value: 1, to: now) ?? now
            if lower.contains("morning") || lower.contains("9am") {
                result = cal.date(bySettingHour: 9, minute: 0, second: 0, of: result) ?? result
            } else if lower.contains("noon") || lower.contains("12pm") {
                result = cal.date(bySettingHour: 12, minute: 0, second: 0, of: result) ?? result
            } else if lower.contains("evening") || lower.contains("6pm") {
                result = cal.date(bySettingHour: 18, minute: 0, second: 0, of: result) ?? result
            }
            return result
        }

        if lower.contains("tonight") || lower.contains("this evening") {
            return cal.date(bySettingHour: 20, minute: 0, second: 0, of: now)
        }

        if lower.contains("this afternoon") {
            return cal.date(bySettingHour: 14, minute: 0, second: 0, of: now)
        }

        // Fallback: try NSDataDetector
        let detector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.date.rawValue)
        let range = NSRange(string.startIndex..., in: string)
        if let match = detector?.firstMatch(in: string, range: range) {
            return match.date
        }

        return nil
    }
}
