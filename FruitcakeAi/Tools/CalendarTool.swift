//
//  CalendarTool.swift
//  FruitcakeAi
//
//  On-device FoundationModels tool for reading Apple Calendar events.
//  Used by OnDeviceAgent when the backend is unreachable.
//  Requires NSCalendarsFullAccessUsageDescription in Info.plist.
//

import Foundation
import FoundationModels
import EventKit

@available(macOS 26.0, iOS 26.0, *)
struct CalendarTool: Tool {

    let name = "checkCalendar"
    let description = "Look up upcoming Apple Calendar events for the user. Use this when asked about schedule, appointments, events, or what's happening soon."

    @Generable
    struct Arguments {
        @Guide(description: "How many days ahead to look for events (1–14)")
        var daysAhead: Int

        @Guide(description: "Optional keyword to filter events by title (leave empty to return all)")
        var keyword: String
    }

    func call(arguments: Arguments) async throws -> String {
        let store = EKEventStore()

        // Request permission (no-op if already granted)
        let granted = try await store.requestFullAccessToEvents()
        guard granted else {
            return "Calendar access was denied. Please grant access in Settings > Privacy & Security > Calendars."
        }

        let days = max(1, min(arguments.daysAhead, 14))
        let start = Date.now
        let end = Calendar.current.date(byAdding: .day, value: days, to: start) ?? start

        let predicate = store.predicateForEvents(withStart: start, end: end, calendars: nil)
        let events = store.events(matching: predicate)
            .sorted { $0.startDate < $1.startDate }

        let keyword = arguments.keyword.trimmingCharacters(in: .whitespaces).lowercased()
        let filtered = keyword.isEmpty
            ? events
            : events.filter { ($0.title ?? "").lowercased().contains(keyword) }

        if filtered.isEmpty {
            let range = days == 1 ? "today" : "the next \(days) days"
            return "No events found for \(range)\(keyword.isEmpty ? "" : " matching '\(keyword)'")"
        }

        let lines = filtered.map { event -> String in
            let date = event.startDate.formatted(date: .abbreviated, time: .shortened)
            let cal  = event.calendar?.title ?? ""
            let loc  = event.location.map { " — \($0)" } ?? ""
            return "• \(event.title ?? "Untitled")  [\(date)]\(loc)\(cal.isEmpty ? "" : "  (\(cal))")"
        }

        return "Upcoming events:\n" + lines.joined(separator: "\n")
    }
}
