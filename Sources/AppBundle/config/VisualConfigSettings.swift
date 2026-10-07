import AppKit
import Combine
import Common
import Foundation
import TOMLDecoder

struct VisualConfigPair: Identifiable, Equatable, Sendable {
    var id = UUID()
    var key: String
    var value: String
}

struct VisualWorkspaceAssignment: Identifiable, Equatable, Sendable {
    var id = UUID()
    var workspace: String
    var monitors: [String]
}

struct VisualWindowRule: Identifiable, Equatable, Sendable {
    var id = UUID()
    var condition: String
    var commands: [String]
    var checkFurtherCallbacks = false

    init(
        id: UUID = UUID(),
        condition: String,
        commands: [String],
        checkFurtherCallbacks: Bool = false,
    ) {
        self.id = id
        self.condition = condition
        self.commands = commands
        self.checkFurtherCallbacks = checkFurtherCallbacks
    }

    init(applicationBundleIdentifier: String, layout: VisualApplicationWindowLayout) {
        self.init(applicationRule: VisualApplicationRule(
            bundleIdentifier: applicationBundleIdentifier,
            titleContains: "",
            layout: layout,
            workspace: "",
        ))
    }

    init(
        id: UUID = UUID(),
        applicationRule: VisualApplicationRule,
        checkFurtherCallbacks: Bool = true,
    ) {
        var matchers = ["test %{app-bundle-id} = \(applicationRule.bundleIdentifier)"]
        if !applicationRule.titleContains.isEmpty {
            let literalPattern = Self.literalRegex(for: applicationRule.titleContains)
            matchers.append("test %{window-title} ~= \(Self.shellQuote(literalPattern))")
        }
        var commands = [String]()
        if let layout = applicationRule.layout { commands.append(layout.command) }
        if !applicationRule.workspace.isEmpty {
            commands.append("move-node-to-workspace -- \(Self.shellQuote(applicationRule.workspace))")
        }
        if let scratchpadSlot = applicationRule.scratchpadSlot {
            commands.append("scratchpad assign \(scratchpadSlot)")
        }
        self.init(
            id: id,
            condition: matchers.joined(separator: " && "),
            commands: commands,
            checkFurtherCallbacks: checkFurtherCallbacks,
        )
    }

    var visualApplicationRule: VisualApplicationRule? {
        guard let matcher = condition.lexAndParseShell().getIgnoringErrorsOrNil() else { return nil }
        let matcherCommands: [[String]] = switch matcher {
            case .cmd(let command): [command]
            case .and(let clauses): clauses.compactMap {
                    if case .cmd(let command) = $0 { command } else { nil }
                }
            case .empty, .pipe, .or, .seq: []
        }
        guard !matcherCommands.isEmpty else { return nil }

        var bundleIdentifier: String?
        var titlePattern: String?
        for command in matcherCommands {
            guard command.count == 4, command[0] == "test" else { return nil }
            switch (command[1], command[2]) {
                case ("%{app-bundle-id}", "=") where bundleIdentifier == nil:
                    bundleIdentifier = command[3]
                case ("%{window-title}", "~=") where titlePattern == nil:
                    titlePattern = command[3]
                default:
                    return nil
            }
        }
        guard let bundleIdentifier,
              !bundleIdentifier.isEmpty,
              bundleIdentifier.allSatisfy({ $0.isLetter || $0.isNumber || ".-_".contains($0) })
        else { return nil }

        var layout: VisualApplicationWindowLayout?
        var workspace = ""
        var scratchpadSlot: Int?
        for commandText in commands {
            guard let command = commandText.lexAndParseShell().getIgnoringErrorsOrNil(), case .cmd(let words) = command else { return nil }
            if words.count == 2, words[0] == "layout", let parsedLayout = VisualApplicationWindowLayout(rawValue: words[1]), layout == nil {
                layout = parsedLayout
            } else if words.count == 3, words[0] == "move-node-to-workspace", words[1] == "--", workspace.isEmpty {
                workspace = words[2]
            } else if words.count == 2, words[0] == "move-node-to-workspace", workspace.isEmpty {
                workspace = words[1]
            } else if words.count == 3,
                      words[0] == "scratchpad",
                      words[1] == "assign",
                      let slot = Int(words[2]),
                      (1 ... smoothWorkspaceSlotCount).contains(slot),
                      scratchpadSlot == nil
            {
                scratchpadSlot = slot
            } else {
                return nil
            }
        }
        guard layout != nil || !workspace.isEmpty || scratchpadSlot != nil else { return nil }

        let titleContains: String
        if let titlePattern {
            titleContains = Self.literalText(fromEscapedRegex: titlePattern) ?? ""
            guard !titleContains.isEmpty else { return nil }
        } else {
            titleContains = ""
        }
        return VisualApplicationRule(
            bundleIdentifier: bundleIdentifier,
            titleContains: titleContains,
            layout: layout,
            workspace: workspace,
            scratchpadSlot: scratchpadSlot,
        )
    }

    private static func shellQuote(_ value: String) -> String {
        if !value.contains("'") { return "'\(value)'" }
        let escaped = value.replacingOccurrences(of: "\"", with: "\"\"")
        return "\"\(escaped)\""
    }

    private static func literalText(fromEscapedRegex pattern: String) -> String? {
        var result = ""
        var index = pattern.startIndex
        while index < pattern.endIndex {
            if pattern[index...].hasPrefix("\\x{27}") {
                result.append("'")
                index = pattern.index(index, offsetBy: 6)
            } else if pattern[index] == "\\" {
                let next = pattern.index(after: index)
                guard next < pattern.endIndex else { return nil }
                result.append(pattern[next])
                index = pattern.index(after: next)
            } else {
                result.append(pattern[index])
                index = pattern.index(after: index)
            }
        }
        return result
    }

    private static func literalRegex(for text: String) -> String {
        let metacharacters = "\\.^$|?*+()[]{}"
        return text.map { character in
            if character == "'" { return "\\x{27}" }
            return metacharacters.contains(character) ? "\\\(character)" : String(character)
        }.joined()
    }
}

enum VisualApplicationWindowLayout: String, CaseIterable, Identifiable, Sendable {
    case floating
    case tiling

    var id: Self { self }
    var title: String { rawValue.capitalized }
    var command: String { "layout \(rawValue)" }
}

struct VisualApplicationRule: Equatable, Sendable {
    var bundleIdentifier: String
    var titleContains: String
    var layout: VisualApplicationWindowLayout?
    var workspace: String
    var scratchpadSlot: Int? = nil
}

struct VisualHotkeyBinding: Identifiable, Equatable, Sendable {
    var id = UUID()
    var shortcut: String
    var commands: [String]
}

struct VisualConfigGaps: Equatable, Sendable {
    var innerHorizontal = 0
    var innerVertical = 0
    var outerLeft = 0
    var outerBottom = 0
    var outerTop = 0
    var outerRight = 0
}

struct VisualConfigDraft: Equatable, Sendable {
    var configVersion = 2
    var startAtLogin = false
    var autoReloadConfig = true
    var inheritEnvironmentVariables = true
    var environmentVariables: [VisualConfigPair] = []
    var afterLoginCommands: [String] = []
    var afterStartupCommands: [String] = []
    var flattenContainers = true
    var normalizeOppositeOrientation = true
    var defaultRootLayout = "tiles"
    var defaultRootOrientation = "auto"
    var accordionPadding = 30
    var layoutAnimationDurationMs = 160
    var layoutAnimationRespectsReduceMotion = true
    var persistentWorkspaces: [String] = []
    var onFocusedMonitorChanged: [String] = []
    var onFocusChanged: [String] = []
    var windowRules: [VisualWindowRule] = []
    var workspaceAssignments: [VisualWorkspaceAssignment] = []
    var gaps = VisualConfigGaps()
    var mainBindings: [VisualHotkeyBinding] = []
    var serviceBindings: [VisualHotkeyBinding] = []
}

private enum VisualConfigDecodeError: LocalizedError {
    case invalidRoot

    var errorDescription: String? {
        "The TOML document does not contain a valid root table."
    }
}

enum VisualConfigCodec {
    static func decode(_ text: String) throws -> VisualConfigDraft {
        let dictionary: [String: Any] = try .init(try TOMLTable(source: text))
        var diagnostics: [ConfigParseDiagnostic] = []
        guard let root = tomlAnyToOrderedJsonRecursive(any: dictionary, .emptyRoot, &diagnostics)?.asDictOrNil else {
            throw VisualConfigDecodeError.invalidRoot
        }

        let exec = root["exec"]?.asDictOrNil
        let environment = exec?["env-vars"]?.asDictOrNil
        let gaps = root["gaps"]?.asDictOrNil
        let inner = gaps?["inner"]?.asDictOrNil
        let outer = gaps?["outer"]?.asDictOrNil
        let modes = root["mode"]?.asDictOrNil
        let mainBindings = modes?[mainModeId]?.asDictOrNil?["binding"]?.asDictOrNil
        let serviceBindings = modes?["service"]?.asDictOrNil?["binding"]?.asDictOrNil

        return VisualConfigDraft(
            configVersion: root["config-version"]?.asIntOrNil ?? 2,
            startAtLogin: root["start-at-login"]?.asBoolOrNil ?? false,
            autoReloadConfig: root["auto-reload-config"]?.asBoolOrNil ?? false,
            inheritEnvironmentVariables: exec?["inherit-env-vars"]?.asBoolOrNil ?? true,
            environmentVariables: environment?.compactMap { key, value in
                value.asStringOrNil.map { VisualConfigPair(key: key, value: $0) }
            } ?? [],
            afterLoginCommands: stringList(root["after-login-command"]),
            afterStartupCommands: stringList(root["after-startup-command"]),
            flattenContainers: root["enable-normalization-flatten-containers"]?.asBoolOrNil ?? true,
            normalizeOppositeOrientation: root["enable-normalization-opposite-orientation-for-nested-containers"]?.asBoolOrNil ?? true,
            defaultRootLayout: root["default-root-container-layout"]?.asStringOrNil ?? "tiles",
            defaultRootOrientation: root["default-root-container-orientation"]?.asStringOrNil ?? "auto",
            accordionPadding: root["accordion-padding"]?.asIntOrNil ?? 30,
            layoutAnimationDurationMs: root["layout-animation-duration-ms"]?.asIntOrNil ?? 160,
            layoutAnimationRespectsReduceMotion: root["layout-animation-respect-reduce-motion"]?.asBoolOrNil ?? true,
            persistentWorkspaces: stringList(root["persistent-workspaces"]),
            onFocusedMonitorChanged: stringList(root["on-focused-monitor-changed"]),
            onFocusChanged: stringList(root["on-focus-changed"]),
            windowRules: root["on-window-detected"]?.asArrayOrNil?.compactMap { rawRule in
                guard let rule = rawRule.asDictOrNil, let condition = rule["if"]?.asStringOrNil else { return nil }
                return VisualWindowRule(
                    condition: condition,
                    commands: stringList(rule["run"]),
                    checkFurtherCallbacks: rule["check-further-callbacks"]?.asBoolOrNil ?? false,
                )
            } ?? [],
            workspaceAssignments: root["workspace-to-monitor-force-assignment"]?.asDictOrNil?.map {
                VisualWorkspaceAssignment(workspace: $0.key, monitors: stringList($0.value))
            } ?? [],
            gaps: VisualConfigGaps(
                innerHorizontal: inner?["horizontal"]?.asIntOrNil ?? 0,
                innerVertical: inner?["vertical"]?.asIntOrNil ?? 0,
                outerLeft: outer?["left"]?.asIntOrNil ?? 0,
                outerBottom: outer?["bottom"]?.asIntOrNil ?? 0,
                outerTop: outer?["top"]?.asIntOrNil ?? 0,
                outerRight: outer?["right"]?.asIntOrNil ?? 0,
            ),
            mainBindings: bindings(mainBindings),
            serviceBindings: bindings(serviceBindings),
        )
    }

    static func patch(_ originalText: String, from original: VisualConfigDraft, to draft: VisualConfigDraft) -> String {
        var document = MutableTomlDocument(originalText)

        update(&document, key: "config-version", old: original.configVersion, new: draft.configVersion) { String($0) }
        update(&document, key: "start-at-login", old: original.startAtLogin, new: draft.startAtLogin, render: tomlBool)
        update(&document, key: "auto-reload-config", old: original.autoReloadConfig, new: draft.autoReloadConfig, render: tomlBool)
        update(
            &document,
            key: "exec.inherit-env-vars",
            old: original.inheritEnvironmentVariables,
            new: draft.inheritEnvironmentVariables,
            render: tomlBool,
        )
        if original.environmentVariables != draft.environmentVariables {
            document.replaceDottedRootEntries(
                prefix: "exec.env-vars.",
                entries: draft.environmentVariables.map { ($0.key, tomlQuote($0.value)) },
            )
        }
        updateStringArray(&document, key: "after-login-command", old: original.afterLoginCommands, new: draft.afterLoginCommands)
        updateStringArray(&document, key: "after-startup-command", old: original.afterStartupCommands, new: draft.afterStartupCommands, multiline: true)
        update(
            &document,
            key: "enable-normalization-flatten-containers",
            old: original.flattenContainers,
            new: draft.flattenContainers,
            render: tomlBool,
        )
        update(
            &document,
            key: "enable-normalization-opposite-orientation-for-nested-containers",
            old: original.normalizeOppositeOrientation,
            new: draft.normalizeOppositeOrientation,
            render: tomlBool,
        )
        update(&document, key: "default-root-container-layout", old: original.defaultRootLayout, new: draft.defaultRootLayout, render: tomlQuote)
        update(
            &document,
            key: "default-root-container-orientation",
            old: original.defaultRootOrientation,
            new: draft.defaultRootOrientation,
            render: tomlQuote,
        )
        update(&document, key: "accordion-padding", old: original.accordionPadding, new: draft.accordionPadding) { String($0) }
        update(
            &document,
            key: "layout-animation-duration-ms",
            old: original.layoutAnimationDurationMs,
            new: draft.layoutAnimationDurationMs,
        ) { String($0) }
        update(
            &document,
            key: "layout-animation-respect-reduce-motion",
            old: original.layoutAnimationRespectsReduceMotion,
            new: draft.layoutAnimationRespectsReduceMotion,
            render: tomlBool,
        )
        updateStringArray(&document, key: "persistent-workspaces", old: original.persistentWorkspaces, new: draft.persistentWorkspaces)
        updateStringArray(
            &document,
            key: "on-focused-monitor-changed",
            old: original.onFocusedMonitorChanged,
            new: draft.onFocusedMonitorChanged,
        )
        updateStringArray(&document, key: "on-focus-changed", old: original.onFocusChanged, new: draft.onFocusChanged)

        if original.windowRules != draft.windowRules {
            document.replaceAssignment(key: "on-window-detected", section: nil, value: renderWindowRules(draft.windowRules))
        }
        if original.workspaceAssignments != draft.workspaceAssignments {
            document.replaceSectionEntries(
                section: "workspace-to-monitor-force-assignment",
                entries: draft.workspaceAssignments.map { ($0.workspace, tomlStringList($0.monitors)) },
            )
        }
        if original.gaps != draft.gaps {
            document.replaceSectionEntries(section: "gaps", entries: [
                ("inner.horizontal", String(draft.gaps.innerHorizontal)),
                ("inner.vertical", String(draft.gaps.innerVertical)),
                ("outer.left", String(draft.gaps.outerLeft)),
                ("outer.bottom", String(draft.gaps.outerBottom)),
                ("outer.top", String(draft.gaps.outerTop)),
                ("outer.right", String(draft.gaps.outerRight)),
            ])
        }
        if original.mainBindings != draft.mainBindings {
            document.replaceSectionEntries(
                section: "mode.main.binding",
                entries: draft.mainBindings.map { ($0.shortcut, tomlCommandList($0.commands)) },
            )
        }
        if original.serviceBindings != draft.serviceBindings {
            document.replaceSectionEntries(
                section: "mode.service.binding",
                entries: draft.serviceBindings.map { ($0.shortcut, tomlCommandList($0.commands)) },
            )
        }
        return document.text
    }

    private static func bindings(_ raw: OrderedJson.JsonDict?) -> [VisualHotkeyBinding] {
        raw?.map {
            VisualHotkeyBinding(shortcut: $0.key, commands: stringList($0.value))
        } ?? []
    }

    private static func stringList(_ raw: OrderedJson?) -> [String] {
        if let value = raw?.asStringOrNil { return [value] }
        return raw?.asArrayOrNil?.compactMap(\.asStringOrNil) ?? []
    }

    private static func update<T: Equatable>(
        _ document: inout MutableTomlDocument,
        key: String,
        old: T,
        new: T,
        render: (T) -> String,
    ) {
        if old != new {
            document.replaceAssignment(key: key, section: nil, value: render(new))
        }
    }

    private static func updateStringArray(
        _ document: inout MutableTomlDocument,
        key: String,
        old: [String],
        new: [String],
        multiline: Bool = false,
    ) {
        if old != new {
            document.replaceAssignment(key: key, section: nil, value: tomlStringList(new, multiline: multiline))
        }
    }

    private static func tomlBool(_ value: Bool) -> String { value ? "true" : "false" }

    static func tomlQuote(_ value: String) -> String {
        "\"" + value
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
            .replacingOccurrences(of: "\n", with: "\\n")
            .replacingOccurrences(of: "\t", with: "\\t") + "\""
    }

    private static func tomlStringList(_ values: [String], multiline: Bool = false) -> String {
        if values.isEmpty { return "[]" }
        if multiline {
            return "[\n" + values.map { "    \(tomlQuote($0))," }.joined(separator: "\n") + "\n]"
        }
        return "[" + values.map(tomlQuote).joined(separator: ", ") + "]"
    }

    private static func tomlCommandList(_ commands: [String]) -> String {
        commands.count == 1 ? tomlQuote(commands[0]) : tomlStringList(commands)
    }

    private static func renderWindowRules(_ rules: [VisualWindowRule]) -> String {
        if rules.isEmpty { return "[]" }
        let rendered = rules.map { rule in
            let checkFurtherCallbacks = rule.checkFurtherCallbacks ? "\n        check-further-callbacks = true," : ""
            return """
                    {
                        if = \(tomlQuote(rule.condition)),\(checkFurtherCallbacks)
                        run = \(tomlCommandList(rule.commands)),
                    },
                """
        }.joined(separator: "\n")
        return "[\n\(rendered)\n]"
    }
}

private struct MutableTomlDocument {
    private var lines: [String]
    private let hadTrailingNewline: Bool

    init(_ text: String) {
        hadTrailingNewline = text.hasSuffix("\n")
        lines = text.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
        if hadTrailingNewline, lines.last?.isEmpty == true { lines.removeLast() }
    }

    var text: String {
        lines.joined(separator: "\n") + (hadTrailingNewline ? "\n" : "")
    }

    mutating func replaceAssignment(key: String, section: String?, value: String) {
        let bounds = sectionBounds(section)
        if let range = assignmentRange(key: key, in: bounds) {
            let indentation = String(lines[range.lowerBound].prefix { $0 == " " || $0 == "\t" })
            lines.replaceSubrange(range, with: assignmentLines(indentation: indentation, key: key, value: value))
        } else {
            var insertion = bounds.upperBound
            while insertion > bounds.lowerBound {
                let previous = lines[insertion - 1].trimmingCharacters(in: .whitespaces)
                guard previous.isEmpty || previous.hasPrefix("#") else { break }
                insertion -= 1
            }
            lines.insert(contentsOf: assignmentLines(indentation: "", key: key, value: value), at: insertion)
        }
    }

    mutating func replaceDottedRootEntries(prefix: String, entries: [(String, String)]) {
        let bounds = sectionBounds(nil)
        var result: [String] = []
        var emitted = Set<String>()
        var insertNewEntriesAt: Int?
        var index = bounds.lowerBound
        while index < bounds.upperBound {
            if let key = assignmentKey(lines[index]), key.hasPrefix(prefix) {
                let range = assignmentRange(key: key, in: index ..< bounds.upperBound) ?? index ..< index + 1
                let suffix = String(key.dropFirst(prefix.count))
                if let value = entries.first(where: { $0.0 == suffix })?.1 {
                    result.append("\(prefix)\(tomlBareKey(suffix)) = \(value)")
                    emitted.insert(suffix)
                }
                insertNewEntriesAt = result.count
                index = range.upperBound
            } else {
                result.append(lines[index])
                index += 1
            }
        }
        let newLines = entries.compactMap { key, value in
            emitted.contains(key) ? nil : "\(prefix)\(tomlBareKey(key)) = \(value)"
        }
        result.insert(contentsOf: newLines, at: insertNewEntriesAt ?? result.count)
        lines.replaceSubrange(bounds, with: result)
    }

    mutating func replaceSectionEntries(section: String, entries: [(String, String)]) {
        guard let header = sectionHeaderIndex(section) else {
            if lines.last?.isEmpty == false { lines.append("") }
            lines.append("[\(section)]")
            lines += entries.map { "\(tomlBareKey($0.0)) = \($0.1)" }
            return
        }

        let bounds = sectionBounds(section)
        var result: [String] = []
        var emitted = Set<String>()
        var insertNewEntriesAt: Int?
        var index = bounds.lowerBound
        while index < bounds.upperBound {
            if let key = assignmentKey(lines[index]) {
                let range = assignmentRange(key: key, in: index ..< bounds.upperBound) ?? index ..< index + 1
                if let value = entries.first(where: { $0.0 == key })?.1 {
                    result += assignmentLines(indentation: "", key: key, value: value)
                    emitted.insert(key)
                    insertNewEntriesAt = result.count
                }
                index = range.upperBound
            } else {
                result.append(lines[index])
                index += 1
            }
        }
        let newLines = entries
            .filter { !emitted.contains($0.0) }
            .flatMap { assignmentLines(indentation: "", key: $0.0, value: $0.1) }
        result.insert(contentsOf: newLines, at: insertNewEntriesAt ?? result.count)
        lines.replaceSubrange((header + 1) ..< bounds.upperBound, with: result)
    }

    private func sectionHeaderIndex(_ section: String) -> Int? {
        lines.firstIndex { parsedSectionName($0) == section }
    }

    private func sectionBounds(_ section: String?) -> Range<Int> {
        if let section, let header = sectionHeaderIndex(section) {
            let end = lines[(header + 1)...].firstIndex { parsedSectionName($0) != nil } ?? lines.endIndex
            return (header + 1) ..< end
        }
        if section != nil { return lines.endIndex ..< lines.endIndex }
        let end = lines.firstIndex { parsedSectionName($0) != nil } ?? lines.endIndex
        return lines.startIndex ..< end
    }

    private func assignmentRange(key: String, in bounds: Range<Int>) -> Range<Int>? {
        guard let start = bounds.first(where: { assignmentKey(lines[$0]) == key }) else { return nil }
        var balance = bracketBalance(afterEqualsIn: lines[start])
        var end = start + 1
        while balance > 0, end < bounds.upperBound {
            balance += bracketBalance(in: lines[end])
            end += 1
        }
        return start ..< end
    }

    private func assignmentLines(indentation: String, key: String, value: String) -> [String] {
        let valueLines = value.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
        guard let first = valueLines.first else { return ["\(indentation)\(tomlBareKey(key)) = \""] }
        return ["\(indentation)\(tomlKeyPath(key)) = \(first)"] + valueLines.dropFirst()
    }

    private func parsedSectionName(_ line: String) -> String? {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        guard trimmed.hasPrefix("["), trimmed.hasSuffix("]"), !trimmed.hasPrefix("[[") else { return nil }
        return String(trimmed.dropFirst().dropLast())
    }

    private func assignmentKey(_ line: String) -> String? {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty, !trimmed.hasPrefix("#"), let equals = trimmed.firstIndex(of: "=") else { return nil }
        return String(trimmed[..<equals]).trimmingCharacters(in: .whitespaces).trimmingCharacters(in: CharacterSet(charactersIn: "\"'"))
    }

    private func bracketBalance(afterEqualsIn line: String) -> Int {
        guard let equals = line.firstIndex(of: "=") else { return 0 }
        return bracketBalance(in: String(line[line.index(after: equals)...]))
    }

    private func bracketBalance(in text: String) -> Int {
        var balance = 0
        var quote: Character?
        var escaping = false
        for character in text {
            if escaping {
                escaping = false
                continue
            }
            if quote == "\"", character == "\\" {
                escaping = true
                continue
            }
            if let activeQuote = quote {
                if character == activeQuote { quote = nil }
                continue
            }
            if character == "#" { break }
            if character == "\"" || character == "'" {
                quote = character
            } else if character == "[" || character == "{" {
                balance += 1
            } else if character == "]" || character == "}" {
                balance -= 1
            }
        }
        return balance
    }

    private func tomlBareKey(_ key: String) -> String {
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "_-"))
        return key.unicodeScalars.allSatisfy { allowed.contains($0) }
            ? key
            : VisualConfigCodec.tomlQuote(key)
    }

    private func tomlKeyPath(_ key: String) -> String {
        key.split(separator: ".", omittingEmptySubsequences: false)
            .map { tomlBareKey(String($0)) }
            .joined(separator: ".")
    }
}

enum VisualConfigSaveStatus: Equatable {
    case ready
    case saving
    case saved(String)
    case failed(String)
}

@MainActor
final class VisualConfigSettingsStore: ObservableObject {
    @Published var draft = VisualConfigDraft()
    @Published private(set) var status: VisualConfigSaveStatus = .ready
    @Published private(set) var configPath = ""

    private var originalDraft = VisualConfigDraft()
    private var originalText = ""
    private var configFileUrl: URL?
    private let configLocation: URL?
    private let reload: (URL) async -> ReloadConfigResult

    var hasChanges: Bool { draft != originalDraft }
    var previewText: String { VisualConfigCodec.patch(originalText, from: originalDraft, to: draft) }

    init(
        configLocation: URL? = nil,
        reload: @escaping (URL) async -> ReloadConfigResult = { await reloadConfig_nonCancellable(forceConfigUrl: $0) },
    ) {
        self.configLocation = configLocation
        self.reload = reload
        load()
    }

    func load() {
        let url = configLocation ?? findCustomConfigUrl().urlOrNil ?? configUrl
        do {
            let text = try String(contentsOf: url, encoding: .utf8)
            let decoded = try VisualConfigCodec.decode(text)
            configFileUrl = url
            configPath = url.path
            originalText = text
            originalDraft = decoded
            draft = decoded
            status = .ready
        } catch {
            status = .failed("Could not load the configuration: \(error.localizedDescription)")
        }
    }

    func discardChanges() {
        draft = originalDraft
        status = .ready
    }

    func save() async {
        guard let url = configFileUrl else {
            status = .failed("Configuration file not found.")
            return
        }
        status = .saving
        let savedDraft = draft
        let candidate = VisualConfigCodec.patch(originalText, from: originalDraft, to: savedDraft)
        let parsed = parseConfig(candidate)
        guard parsed.errors.isEmpty else {
            status = .failed(parsed.errors.map { $0.description(.error) }.joined(separator: "\n"))
            return
        }
        do {
            let diskText = try String(contentsOf: url, encoding: .utf8)
            guard diskText == originalText else {
                status = .failed("The configuration changed on disk. Save your pending edits elsewhere, then choose Reload from Disk and apply them again.")
                return
            }
            try Data(candidate.utf8).write(to: url, options: .atomic)
            let reload = await self.reload(url)
            guard reload.isOk else {
                status = .failed(reload.stdout.isEmpty ? reload.stderr : reload.stdout)
                return
            }
            originalText = candidate
            originalDraft = savedDraft
            let warning = reload.stderr.isEmpty ? "Configuration saved and applied." : "Saved with warnings: \(reload.stderr)"
            status = .saved(warning)
        } catch {
            status = .failed("Could not save: \(error.localizedDescription)")
        }
    }

    func openConfigFile() {
        guard let configFileUrl else { return }
        configFileUrl.open(with: getTextEditorToOpenConfig())
    }
}
