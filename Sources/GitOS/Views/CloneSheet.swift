import SwiftUI

struct CloneSheet: View {
    @Environment(AppState.self) private var app
    @Environment(\.dismiss) private var dismiss

    @State private var accountID: Account.ID?
    @State private var pickedURL: String?
    @State private var urlMode = false
    @State private var remoteURL = ""
    @State private var parent: URL?
    @State private var cloning = false
    @State private var cloneError: String?

    private var account: Account? { app.account(id: accountID) }

    private var chosenURL: String? {
        if urlMode { return remoteURL.trimmingCharacters(in: .whitespaces).nilIfEmpty }
        return pickedURL
    }

    private var folderName: String {
        guard let url = chosenURL else { return "" }
        var name = (url as NSString).lastPathComponent
        if name.hasSuffix(".git") { name.removeLast(4) }
        return name
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Picker("Account", selection: $accountID) {
                    ForEach(app.accounts) { Text($0.title).tag(Optional($0.id)) }
                }
                .frame(maxWidth: 280)
                Spacer()
                Picker("Source", selection: $urlMode) {
                    Text("From account").tag(false)
                    Text("URL").tag(true)
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .frame(width: 200)
            }
            .padding(12)

            if urlMode {
                Form {
                    TextField("Repository URL", text: $remoteURL, prompt: Text("https://github.com/owner/repo.git"))
                    Text("SSH URLs work too. They're fetched over HTTPS with the selected account's token.")
                        .font(.caption).foregroundStyle(.secondary)
                }
                .formStyle(.grouped)
                .frame(maxHeight: .infinity, alignment: .top)
            } else {
                AccountRepoPicker(account: account, cloneURL: $pickedURL)
            }

            Divider()
            HStack {
                Image(systemName: "folder").foregroundStyle(.secondary)
                Text(destinationText).lineLimit(1).truncationMode(.head).foregroundStyle(.secondary)
                Button("Change…") { chooseParent() }
                Spacer()
                if let cloneError {
                    Text(cloneError).foregroundStyle(Theme.removed).lineLimit(2).font(.caption)
                }
            }
            .padding(.horizontal, 12).padding(.top, 10)

            HStack {
                Button("Cancel") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Spacer()
                if cloning { ProgressView().controlSize(.small) }
                Button("Clone") { clone() }
                    .keyboardShortcut(.defaultAction)
                    .disabled(chosenURL == nil || cloning)
            }
            .padding(12)
        }
        .frame(width: 620, height: 520)
        .task {
            accountID = accountID ?? app.defaultAccountID ?? app.accounts.first?.id
        }
        .onChange(of: accountID) { parent = nil }
    }

    private var destinationText: String {
        let base = parent ?? app.suggestedCloneFolder(for: account)
        let path = folderName.isEmpty ? base.path : base.appendingPathComponent(folderName).path
        return path.abbreviatingWithTildeInPath
    }

    private func chooseParent() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.canCreateDirectories = true
        panel.prompt = "Clone Here"
        panel.directoryURL = parent ?? app.suggestedCloneFolder(for: account)
        if panel.runModal() == .OK { parent = panel.url }
    }

    private func clone() {
        guard let url = chosenURL else { return }
        let destination = parent ?? app.suggestedCloneFolder(for: account)
        let name = folderName
        if FileManager.default.fileExists(atPath: destination.appendingPathComponent(name).path) {
            cloneError = "\(name) already exists in that folder."
            return
        }
        cloning = true
        cloneError = nil
        Task {
            do {
                try await app.clone(url, into: destination, name: name, account: account)
                dismiss()
            } catch {
                cloneError = error.localizedDescription
            }
            cloning = false
        }
    }
}

extension String {
    var nilIfEmpty: String? { isEmpty ? nil : self }
}

/// A searchable list of the repositories an account can reach. Reports the chosen clone URL.
struct AccountRepoPicker: View {
    let account: Account?
    @Binding var cloneURL: String?

    @State private var repos: [GitHubAPI.Repository] = []
    @State private var loading = false
    @State private var loadError: String?
    @State private var search = ""
    @State private var selection: GitHubAPI.Repository.ID?

    private var filtered: [GitHubAPI.Repository] {
        guard !search.isEmpty else { return repos }
        return repos.filter { $0.fullName.localizedCaseInsensitiveContains(search) }
    }

    var body: some View {
        TextField("Filter repositories", text: $search)
            .textFieldStyle(.roundedBorder)
            .padding(.horizontal, 12)
        List(filtered, selection: $selection) { repo in
            HStack {
                Image(systemName: repo.isPrivate ? "lock" : repo.fork ? "tuningfork" : "book.closed")
                    .foregroundStyle(.secondary)
                    .frame(width: 18)
                VStack(alignment: .leading, spacing: 1) {
                    Text(repo.fullName)
                    if let description = repo.description, !description.isEmpty {
                        Text(description).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                    }
                }
                Spacer()
                if let pushed = repo.pushedAt {
                    Text(pushed, format: .relative(presentation: .named))
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
            .tag(repo.id)
        }
        .overlay {
            if loading {
                ProgressView("Loading repositories…")
            } else if let loadError {
                ContentUnavailableView("Couldn't load repositories", systemImage: "exclamationmark.triangle",
                                       description: Text(loadError))
            } else if account == nil {
                ContentUnavailableView("No Account", systemImage: "person.crop.circle.badge.plus",
                                       description: Text("Add a GitHub account in Settings, or enter a URL."))
            }
        }
        .onChange(of: selection) { cloneURL = repos.first { $0.id == selection }?.cloneURL }
        .task(id: account?.id) { await load() }
    }

    private func load() async {
        selection = nil
        guard let account, let token = Keychain.get(account.id.uuidString) else { repos = []; return }
        loading = true
        loadError = nil
        defer { loading = false }
        do {
            repos = try await GitHubAPI(token: token).repositories()
        } catch {
            loadError = error.localizedDescription
        }
    }
}
