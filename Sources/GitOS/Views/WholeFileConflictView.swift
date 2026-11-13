import SwiftUI

/// The free way to settle a conflicted file: keep one side of the whole file, keep it as edited,
/// or delete it. The 3-way editor (`ConflictEditorView`) is Pro.
struct WholeFileConflictView: View {
    let model: RepoModel
    let change: FileChange

    var body: some View {
        ContentUnavailableView {
            Label("Resolve \(change.fileName)", systemImage: "arrow.triangle.merge")
        } description: {
            Text("Keep one side of the whole file, or fix it in your editor and mark it resolved. Picking changes conflict by conflict needs the GitOS Pro conflict editor.")
        } actions: {
            VStack(spacing: 10) {
                HStack {
                    Button("Use Ours") { resolve { try await model.repo.resolveWholeFile(change.path, ours: true) } }
                    Button("Use Theirs") { resolve { try await model.repo.resolveWholeFile(change.path, ours: false) } }
                    Button("Mark Resolved As Is") { resolve { try await model.repo.markResolved(change.path) } }
                    Button("Delete File", role: .destructive) { resolve { try await model.repo.resolveByDeleting(change.path) } }
                }
                Button {
                    Licensing.shared.require(.conflictEditor)
                } label: {
                    HStack(spacing: 4) { Text("Open the Conflict Editor"); ProBadge() }
                }
                .buttonStyle(.borderless)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Theme.canvas)
    }

    private func resolve(_ action: @escaping @Sendable () async throws -> Void) {
        Task { _ = await model.perform("Resolving") { try await action() } }
    }
}
