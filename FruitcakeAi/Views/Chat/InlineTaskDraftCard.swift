//
//  InlineTaskDraftCard.swift
//  FruitcakeAi
//
//  Inline (non-modal) presentation of a TaskDraft, rendered in the message
//  thread alongside the assistant message that proposed it. Replaces the
//  old auto-presented .sheet(item: $pendingTaskDraft) flow.
//
//  The card now renders directly from persisted assistant-message metadata,
//  including draft resolution states such as accepted and denied.
//

import SwiftUI

struct InlineTaskDraftCard: View {
    let draft: TaskDraft
    let personaKey: String
    let personaDisplayName: String
    var taskDraftStatus: String? = nil
    var isCreating: Bool = false
    var isDenying: Bool = false
    var canResolve: Bool = true
    var createdTaskId: Int? = nil
    var errorMessage: String? = nil
    var onEdit: () -> Void
    var onCreate: () -> Void
    var onDeny: () -> Void

    private var accent: Color { PersonaAccent.color(for: personaKey) }
    private var normalizedStatus: String {
        switch (taskDraftStatus ?? "").lowercased() {
        case "accepted", "denied", "draft":
            return (taskDraftStatus ?? "").lowercased()
        case "created":
            return "accepted"
        default:
            return createdTaskId != nil ? "accepted" : "draft"
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            header

            VStack(alignment: .leading, spacing: 8) {
                Text(draft.title)
                    .font(.system(size: 14.5, weight: .semibold))
                    .foregroundStyle(Theme.text)

                if !draft.detailSummary.isEmpty {
                    Text(draft.detailSummary)
                        .font(.system(size: 12.5))
                        .foregroundStyle(Theme.textDim)
                        .lineSpacing(2)
                }

                if let dueSummary = draft.dueSummary {
                    Label(dueSummary, systemImage: "calendar")
                        .font(Theme.mono(11))
                        .foregroundStyle(Theme.textDim)
                }

                if let errorMessage {
                    Text(errorMessage)
                        .font(.caption)
                        .foregroundStyle(.red)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(14)

            footer
        }
        .background(Theme.card)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(accent.opacity(0.26), lineWidth: 1))
        .frame(maxWidth: 560, alignment: .leading)
    }

    private var header: some View {
        HStack(spacing: 8) {
            Image(systemName: "checkmark")
                .font(.system(size: 9, weight: .heavy))
                .foregroundStyle(Theme.bg)
                .frame(width: 13, height: 13)
                .background(accent, in: RoundedRectangle(cornerRadius: 3))
            Text("TASK DRAFT")
                .font(Theme.mono(10, weight: .semibold))
                .kerning(1.2)
                .foregroundStyle(accent)
            Spacer()
            Text(personaDisplayName)
                .font(Theme.mono(10))
                .foregroundStyle(Theme.textDim)
        }
        .padding(.horizontal, 13)
        .padding(.vertical, 8)
        .background(accent.opacity(0.09))
    }

    @ViewBuilder
    private var footer: some View {
        if normalizedStatus == "denied" {
            HStack(spacing: 6) {
                Image(systemName: "xmark.circle.fill")
                    .foregroundStyle(Theme.textMid)
                Text("Denied")
                    .font(Theme.mono(11))
                    .foregroundStyle(Theme.textDim)
                Spacer()
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .overlay(Rectangle().fill(Theme.stroke).frame(height: 1), alignment: .top)
        } else if normalizedStatus == "accepted", let createdTaskId {
            HStack(spacing: 6) {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(accent)
                Text("Accepted · Task #\(createdTaskId)")
                    .font(Theme.mono(11))
                    .foregroundStyle(Theme.textDim)
                Spacer()
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .overlay(Rectangle().fill(Theme.stroke).frame(height: 1), alignment: .top)
        } else {
            VStack(alignment: .leading, spacing: 10) {
                if !canResolve {
                    Text("Syncing draft…")
                        .font(Theme.mono(11))
                        .foregroundStyle(Theme.textDim)
                }

                HStack(spacing: 9) {
                    Spacer()
                    Button("Edit", action: onEdit)
                        .buttonStyle(.plain)
                        .foregroundStyle(Theme.textMid)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 7)
                        .overlay(RoundedRectangle(cornerRadius: 8).stroke(Theme.strokeUp, lineWidth: 1))
                        .disabled(isCreating || isDenying)

                    Button(action: onDeny) {
                        if isDenying {
                            ProgressView()
                                .controlSize(.small)
                                .frame(width: 44)
                        } else {
                            Text("Deny")
                                .padding(.horizontal, 12)
                        }
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(Theme.textMid)
                    .padding(.vertical, 7)
                    .overlay(RoundedRectangle(cornerRadius: 8).stroke(Theme.strokeUp, lineWidth: 1))
                    .disabled(!canResolve || isCreating || isDenying)

                    Button(action: onCreate) {
                        if isCreating {
                            ProgressView()
                                .controlSize(.small)
                                .frame(width: 60)
                        } else {
                            Text("Create task")
                                .padding(.horizontal, 16)
                        }
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(Theme.bg)
                    .padding(.vertical, 7)
                    .background(accent, in: RoundedRectangle(cornerRadius: 8))
                    .disabled(!canResolve || isCreating || isDenying)
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .overlay(Rectangle().fill(Theme.stroke).frame(height: 1), alignment: .top)
        }
    }
}

#Preview {
    ScrollView {
        VStack(spacing: 16) {
            InlineTaskDraftCard(
                draft: try! JSONDecoder.fruitcakeDecoder().decode(TaskDraft.self, from: Data("""
                {"title":"Pack school lunches","instruction":"Remind me every weekday morning to pack lunches.","taskSummary":"Daily reminder before school drop-off.","taskType":"recurring","schedule":"every:1d","deliver":true,"requiresApproval":false}
                """.utf8)),
                personaKey: "family_assistant",
                personaDisplayName: "Family Assistant",
                onEdit: {},
                onCreate: {},
                onDeny: {}
            )
            InlineTaskDraftCard(
                draft: try! JSONDecoder.fruitcakeDecoder().decode(TaskDraft.self, from: Data("""
                {"title":"Skip duplicate research","instruction":"Do not create this task.","taskType":"one_shot","deliver":true,"requiresApproval":true}
                """.utf8)),
                personaKey: "family_assistant",
                personaDisplayName: "Family Assistant",
                taskDraftStatus: "denied",
                onEdit: {},
                onCreate: {},
                onDeny: {}
            )
            InlineTaskDraftCard(
                draft: try! JSONDecoder.fruitcakeDecoder().decode(TaskDraft.self, from: Data("""
                {"title":"Research weekend trip options","instruction":"Find weekend getaway ideas within driving distance.","taskType":"one_shot","deliver":true,"requiresApproval":true}
                """.utf8)),
                personaKey: "news_researcher",
                personaDisplayName: "News Researcher",
                taskDraftStatus: "accepted",
                createdTaskId: 42,
                onEdit: {},
                onCreate: {},
                onDeny: {}
            )
        }
        .padding()
    }
    .background(Theme.bg)
}

private extension JSONDecoder {
    static func fruitcakeDecoder() -> JSONDecoder {
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }
}
