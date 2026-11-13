import SwiftUI

/// 3-way merge editor for one conflicted file: ours / (base) / theirs per conflict, with a live result.
struct ConflictEditorView: View {
    let model: RepoModel
    let change: FileChange

    @State private var document: ConflictDocument?
    @State private var resolutions: [Int: ConflictDocument.Resolution] = [:]
    @State private var editing: Int?
    @State private var customText = ""
    @State private var showBase = false
    @State private var showResult = false
    @State private var resultOverride: String?
    @State private var loadError: String?

    private var fileURL: URL { model.repo.url.appendingPathComponent(change.path) }
    private var conflicts: [ConflictDocument.Conflict] { document?.conflicts ?? [] }
    private var resolvedCount: Int { conflicts.filter { resolutions[$0.id] != nil }.count }
    private var result: String { resultOverride ?? document?.render(resolutions) ?? "" }

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            if let loadError {
                wholeFileOnly(message: loadError)
            } else if document == nil {
                ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if conflicts.isEmpty {
                wholeFileOnly(message: "No conflict markers in this file. It may be a binary, deleted or renamed-file conflict.")
            } else if showResult {
                TextEditor(text: Binding(get: { result }, set: { resultOverride = $0 }))
                    .font(.system(size: 12, design: .monospaced))
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 14) {
                        ForEach(Array(conflicts.enumerated()), id: \.element.id) { index, conflict in
                            conflictCard(conflict, number: index + 1)
                        }
                    }
                    .padding(12)
                }
            }
            Divider()
            footer
        }
        .task(id: change.id) { load() }
        .sheet(item: Binding(get: { editing.map { EditTarget(id: $0) } }, set: { editing = $0?.id })) { target in
            customEditor(for: target.id)
        }
    }

    private var header: some View {
        HStack(spacing: 10) {
            Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(Theme.modified)
            Text(change.path).font(.headline).lineLimit(1).truncationMode(.middle)
            Spacer()
            if !conflicts.isEmpty {
                Toggle("Base", isOn: $showBase).toggleStyle(.checkbox)
                    .disabled(!conflicts.contains { $0.base != nil })
                    .help("Show the common ancestor (needs merge.conflictStyle=diff3 or zdiff3)")
                Picker("", selection: $showResult) {
                    Text("Conflicts").tag(false)
                    Text("Result").tag(true)
                }
                .pickerStyle(.segmented)
                .frame(width: 170)
            }
            Menu("Whole File") {
                Button("Use Ours for Whole File") { Task { await whole(ours: true) } }
                Button("Use Theirs for Whole File") { Task { await whole(ours: false) } }
                Divider()
                Button("Open in External Editor") { NSWorkspace.shared.open(fileURL) }
                Button("Reload from Disk") { load() }
            }
            .fixedSize()
            FocusModeButton()
        }
        .padding(.horizontal, 12).padding(.vertical, 8)
    }

    private var footer: some View {
        HStack {
            if resultOverride != nil {
                Label("Result edited by hand", systemImage: "pencil").foregroundStyle(.secondary)
                Button("Discard Edits") { resultOverride = nil }.buttonStyle(.borderless)
            } else if !conflicts.isEmpty {
                ProgressView(value: Double(resolvedCount), total: Double(max(conflicts.count, 1)))
                    .frame(width: 120)
                Text("\(resolvedCount) of \(conflicts.count) resolved").foregroundStyle(.secondary)
            }
            Spacer()
            Button("Save & Mark Resolved") { Task { await save() } }
                .prominentButton()
                .disabled(conflicts.isEmpty || (resultOverride == nil && resolvedCount < conflicts.count) || model.isBusy)
        }
        .padding(10)
    }

    private func conflictCard(_ conflict: ConflictDocument.Conflict, number: Int) -> some View {
        let resolution = resolutions[conflict.id]
        return VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Conflict \(number) of \(conflicts.count)").font(.headline)
                if let resolution {
                    Label(label(for: resolution), systemImage: "checkmark.circle.fill")
                        .foregroundStyle(Theme.added).font(.callout)
                    Button("Undo") { resolutions[conflict.id] = nil }.buttonStyle(.borderless).font(.callout)
                }
                Spacer()
            }
            HStack(alignment: .top, spacing: 8) {
                side(title: "Ours", label: conflict.oursLabel, text: conflict.ours, tint: Theme.added,
                     chosen: resolution == .ours) { resolutions[conflict.id] = .ours }
                if showBase, let base = conflict.base {
                    side(title: "Base", label: "common ancestor", text: base, tint: .secondary, chosen: false, choose: nil)
                }
                side(title: "Theirs", label: conflict.theirsLabel, text: conflict.theirs, tint: Theme.renamed,
                     chosen: resolution == .theirs) { resolutions[conflict.id] = .theirs }
            }
            HStack {
                Button("Ours, then Theirs") { resolutions[conflict.id] = .oursThenTheirs }
                Button("Theirs, then Ours") { resolutions[conflict.id] = .theirsThenOurs }
                Button("Edit…") {
                    customText = resolution.map(conflict.text(for:)) ?? conflict.ours
                    editing = conflict.id
                }
            }
            .controlSize(.small)
        }
        .padding(10)
        .background(.quaternary.opacity(0.35), in: RoundedRectangle(cornerRadius: 8))
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(resolution == nil ? Theme.modified.opacity(0.6) : Theme.added.opacity(0.5)))
    }

    private func side(title: String, label: String, text: String, tint: Color, chosen: Bool,
                      choose: (() -> Void)?) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(title).font(.caption.weight(.bold))
                Text(label).font(.caption).foregroundStyle(.secondary).lineLimit(1).truncationMode(.middle)
                Spacer()
                if let choose {
                    Button(chosen ? "Chosen" : "Use \(title)", action: choose)
                        .controlSize(.small)
                        .buttonStyle(.bordered)
                        .tint(chosen ? tint : nil)
                }
            }
            Text(text.isEmpty ? "(empty)" : text.hasSuffix("\n") ? String(text.dropLast()) : text)
                .font(.system(size: 12, design: .monospaced))
                .foregroundStyle(text.isEmpty ? .secondary : .primary)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(6)
                .background(tint.opacity(chosen ? 0.25 : 0.1), in: RoundedRectangle(cornerRadius: 4))
        }
        .frame(maxWidth: .infinity)
    }

    private func customEditor(for id: Int) -> some View {
        VStack(alignment: .leading) {
            Text("Edit Resolution").font(.headline)
            TextEditor(text: $customText)
                .font(.system(size: 12, design: .monospaced))
                .frame(minHeight: 220)
                .overlay(RoundedRectangle(cornerRadius: 4).stroke(.separator))
            HStack {
                Button("Cancel") { editing = nil }.keyboardShortcut(.cancelAction)
                Spacer()
                Button("Use This") {
                    var text = customText
                    if !text.isEmpty && !text.hasSuffix("\n") { text += "\n" }
                    resolutions[id] = .custom(text)
                    editing = nil
                }
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(16)
        .frame(width: 560)
    }

    private func wholeFileOnly(message: String) -> some View {
        ContentUnavailableView {
            Label("Resolve Whole File", systemImage: "doc.on.doc")
        } description: {
            Text(message)
        } actions: {
            HStack {
                Button("Use Ours") { Task { await whole(ours: true) } }
                Button("Use Theirs") { Task { await whole(ours: false) } }
                Button("Mark Resolved As Is") { Task { await model.perform("Resolving") { try await model.repo.markResolved(change.path) } } }
                Button("Delete File", role: .destructive) {
                    Task { await model.perform("Resolving") { try await model.repo.resolveByDeleting(change.path) } }
                }
            }
        }
    }

    private func label(for resolution: ConflictDocument.Resolution) -> String {
        switch resolution {
        case .ours: "Ours"
        case .theirs: "Theirs"
        case .oursThenTheirs: "Ours, then theirs"
        case .theirsThenOurs: "Theirs, then ours"
        case .custom: "Edited"
        }
    }

    private func load() {
        resolutions = [:]
        resultOverride = nil
        guard let data = try? Data(contentsOf: fileURL) else {
            loadError = "The file isn't in the working tree (deleted on one side)."
            return
        }
        guard let text = String(data: data, encoding: .utf8) else {
            loadError = "This file isn't text."
            return
        }
        loadError = nil
        document = ConflictDocument.parse(text)
    }

    private func save() async {
        let text = result
        await model.perform("Saving resolution") {
            try Data(text.utf8).write(to: fileURL, options: .atomic)
            try await model.repo.markResolved(change.path)
        }
    }

    private func whole(ours: Bool) async {
        await model.perform("Resolving") { try await model.repo.resolveWholeFile(change.path, ours: ours) }
    }
}

private struct EditTarget: Identifiable { let id: Int }
