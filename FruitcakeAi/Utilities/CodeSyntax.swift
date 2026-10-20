import Foundation

enum CodeLanguage: String, CaseIterable, Sendable {
    case swift, python, javascript, typescript, json, shell, plain

    static func resolve(hint: String = "", path: String = "") -> Self {
        let hint = hint.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let name = hint.isEmpty ? (path as NSString).pathExtension.lowercased() : hint
        switch name {
        case "swift": return .swift
        case "python", "python3", "py", "pyi": return .python
        case "javascript", "js", "mjs", "cjs": return .javascript
        case "typescript", "ts", "mts", "cts": return .typescript
        case "json": return .json
        case "shell", "bash", "sh", "zsh": return .shell
        default: return .plain
        }
    }

    var keywords: Set<String> {
        let words: String
        switch self {
        case .swift:
            words = "actor any as associatedtype async await break case catch class continue convenience default defer deinit didSet do else enum extension fallthrough false fileprivate final for func get guard if import in indirect init inout internal is isolated lazy let mutating nil nonisolated open operator override private protocol public repeat required rethrows return self Self set some static struct subscript super switch throw throws true try typealias var weak where while willSet"
        case .python:
            words = "False None True and as assert async await break case class continue def del elif else except finally for from global if import in is lambda match nonlocal not or pass raise return try while with yield"
        case .javascript, .typescript:
            words = "abstract any as async await boolean break case catch class const constructor continue debugger declare default delete do else enum export extends false finally for from function get if implements import in infer instanceof interface is keyof let module namespace never new null number of override private protected public readonly return satisfies set static string super switch symbol this throw true try type typeof undefined unknown var void while with yield"
        case .json: words = "true false null"
        case .shell: words = "case do done elif else esac export fi for function if in local readonly return select then time until while"
        case .plain: words = ""
        }
        return Set(words.split(separator: " ").map(String.init))
    }
}

enum CodeTokenKind: String, CaseIterable, Sendable { case keyword, string, comment, number, type, function, property, operation }
struct CodeToken: Equatable, Sendable {
    let range: NSRange
    let kind: CodeTokenKind
}

/// Bounded lexical coloring, not semantic analysis or a full language grammar.
/// UTF-16 offsets match AppKit attributes; source bytes are never rewritten.
enum CodeSyntax {
    static let byteLimit = 262_144
    static let lineLimit = 12_000
    static let tokenLimit = 50_000

    static func tokens(_ text: String, language: CodeLanguage) -> [CodeToken] {
        guard language != .plain, text.utf8.count <= byteLimit else { return [] }
        let units = Array(text.utf16)
        guard units.reduce(1, { $0 + ($1 == 10 ? 1 : 0) }) <= lineLimit else { return [] }
        let source = text as NSString, keywords = language.keywords
        var result: [CodeToken] = [], i = 0
        let hashComments = language == .python || language == .shell
        let slashComments = [.swift, .javascript, .typescript].contains(language)
        func has(_ value: [UInt16], at index: Int) -> Bool {
            index + value.count <= units.count && units[index..<(index + value.count)].elementsEqual(value)
        }
        func digit(_ value: UInt16) -> Bool { (48...57).contains(value) }
        func letter(_ value: UInt16) -> Bool {
            (65...90).contains(value) || (97...122).contains(value) || value == 95 || value >= 128
        }
        func word(_ value: UInt16) -> Bool { letter(value) || digit(value) || value == 36 }
        func emit(_ start: Int, _ kind: CodeTokenKind) { result.append(.init(range: NSRange(location: start, length: i - start), kind: kind)) }
        while i < units.count {
            if result.count >= tokenLimit { return [] }
            let start = i, value = units[i]
            if (hashComments && value == 35) || (slashComments && has([47, 47], at: i)) {
                while i < units.count && units[i] != 10 && units[i] != 13 { i += 1 }
                emit(start, .comment)
            } else if slashComments && has([47, 42], at: i) {
                i += 2
                var depth = 1
                while i < units.count && depth > 0 {
                    if language == .swift && has([47, 42], at: i) { depth += 1; i += 2 }
                    else if has([42, 47], at: i) { depth -= 1; i += 2 }
                    else { i += 1 }
                }
                emit(start, .comment)
            } else if value == 34 || (value == 39 && language != .json && language != .swift)
                        || (value == 96 && [.javascript, .typescript, .shell].contains(language))
                        || (language == .swift && value == 35 && has([35, 34], at: i)) {
                var hashes = 0
                if language == .swift {
                    while i < units.count && units[i] == 35 { hashes += 1; i += 1 }
                }
                let quote = units[i]
                let triple = (language == .python || language == .swift) && has([quote, quote, quote], at: i)
                let delimiter = Array(repeating: quote, count: triple ? 3 : 1) + Array(repeating: UInt16(35), count: hashes)
                i += triple ? 3 : 1
                while i < units.count {
                    if has(delimiter, at: i) { i += delimiter.count; break }
                    if units[i] == 92 && hashes == 0 && !(language == .shell && quote == 39) {
                        i = min(i + 2, units.count)
                    } else if !triple && quote != 96 && (units[i] == 10 || units[i] == 13) { break }
                    else { i += 1 }
                }
                let isKey = language == .json && units[i...].first(where: { ![9, 10, 13, 32].contains($0) }) == 58
                emit(start, isKey ? .property : .string)
            } else if digit(value) {
                i += 1
                if value == 48 && i < units.count && [88, 120, 79, 111, 66, 98].contains(units[i]) {
                    let base = units[i]; i += 1
                    while i < units.count {
                        let next = units[i]
                        let valid = [88, 120].contains(base) ? (digit(next) || (65...70).contains(next) || (97...102).contains(next))
                            : [79, 111].contains(base) ? (48...55).contains(next) : (48...49).contains(next)
                        if valid || next == 95 { i += 1 } else { break }
                    }
                } else {
                    while i < units.count && (digit(units[i]) || units[i] == 95) { i += 1 }
                    if i + 1 < units.count && units[i] == 46 && digit(units[i + 1]) {
                        i += 1
                        while i < units.count && (digit(units[i]) || units[i] == 95) { i += 1 }
                    }
                    if i < units.count && [69, 101].contains(units[i]) {
                        var exponent = i + 1
                        if exponent < units.count && [43, 45].contains(units[exponent]) { exponent += 1 }
                        if exponent < units.count && digit(units[exponent]) {
                            i = exponent + 1
                            while i < units.count && (digit(units[i]) || units[i] == 95) { i += 1 }
                        }
                    }
                }
                emit(start, .number)
            } else if letter(value) || value == 36 {
                i += 1
                while i < units.count && word(units[i]) { i += 1 }
                let name = source.substring(with: NSRange(location: start, length: i - start))
                if keywords.contains(name) { emit(start, .keyword) }
                else if language != .json && language != .shell && (65...90).contains(value) { emit(start, .type) }
                else if language != .json && units[i...].first(where: { $0 != 32 && $0 != 9 }) == 40 { emit(start, .function) }
            } else if [43, 45, 42, 47, 61, 60, 62, 33, 38, 124, 63, 37, 94, 126].contains(value) {
                i += 1; emit(start, .operation)
            } else { i += 1 }
        }
        return result
    }
}
