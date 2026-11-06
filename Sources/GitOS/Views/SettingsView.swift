import SwiftUI

struct SettingsView: View {
    var body: some View {
        TabView {
            Tab("General", systemImage: "gearshape") { GeneralSettings() }
            Tab("Accounts", systemImage: "person.2") { AccountsSettings() }
            Tab("Folder Rules", systemImage: "folder.badge.person.crop") { FolderRulesSettings() }
            Tab("GitHub", systemImage: "key") { GitHubSettings() }
            Tab("AI", systemImage: "sparkles") { AISettings() }
        }
        .frame(width: 680, height: 460)
    }
}

// MARK: - General

private struct GeneralSettings: View {
    @State private var checksForUpdates = AppUpdater.shared.automaticallyChecksForUpdates
    @Environment(AppState.self) private var app
    @State private var cliPath = CLIInstaller.installedPath
    @State private var cliError: String?

    var body: some View {
        @Bindable var app = app
        Form {
            Section("Background sync") {
                Toggle("Fetch all repositories in the background", isOn: $app.preferences.backgroundFetch)
                Picker("Every", selection: $app.preferences.fetchIntervalMinutes) {
                    ForEach([5, 10, 15, 30, 60], id: \.self) { Text("\($0) minutes").tag($0) }
                }
                .disabled(!app.preferences.backgroundFetch)
                Toggle("Notify when a branch has new commits upstream", isOn: $app.preferences.notifyNewCommits)
                    .onChange(of: app.preferences.notifyNewCommits) { _, on in
                        if on { app.sync.requestNotificationPermission() }
                    }
                Text("Each repository is fetched with its own account.")
                    .font(.caption).foregroundStyle(.secondary)
            }

            Section("Appearance") {
                ThemePicker(selection: $app.preferences.themeID)
            }

            Section("Updates") {
                Toggle("Check for updates automatically", isOn: $checksForUpdates)
                    .disabled(!AppUpdater.shared.isAvailable)
                    .onChange(of: checksForUpdates) { _, on in
                        AppUpdater.shared.automaticallyChecksForUpdates = on
                    }
                Text("GitOS checks when it opens and every hour, and downloads updates in the background. They only install when you restart to update.")
                    .font(.caption).foregroundStyle(.secondary)
                UpdateStatusRow(updater: AppUpdater.shared)
                Button("Check Now") { AppUpdater.shared.checkForUpdates() }
                    .disabled(!AppUpdater.shared.isAvailable || AppUpdater.shared.isReadyToInstall)
            }

            Section("Menu bar") {
                Toggle("Show GitOS in the menu bar", isOn: $app.preferences.showMenuBarExtra)
                Text("While it's shown, GitOS keeps running after you close its window.")
                    .font(.caption).foregroundStyle(.secondary)
            }

            Section("Command line") {
                LabeledContent("gitos command") {
                    if let cliPath {
                        Text(cliPath.abbreviatingWithTildeInPath).monospaced().textSelection(.enabled)
                    } else {
                        Text("Not installed").foregroundStyle(.secondary)
                    }
                }
                HStack {
                    Button(cliPath == nil ? "Install gitos Command" : "Reinstall") { installCLI() }
                    if let cliError { Text(cliError).foregroundStyle(Theme.removed).font(.caption) }
                }
                Text("Run `gitos .` in any repository to open it here.")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
    }

    private func installCLI() {
        do {
            cliPath = try CLIInstaller.install()
            cliError = nil
        } catch {
            cliError = error.localizedDescription
        }
    }
}

// MARK: - Accounts

private struct AccountsSettings: View {
    @Environment(AppState.self) private var app
    @State private var selection: Account.ID?
    @State private var showingSignIn = false
    @State private var pendingRemoval: Account?

    var body: some View {
        HStack(spacing: 0) {
            VStack(spacing: 0) {
                List(app.accounts, selection: $selection) { account in
                    HStack {
                        AvatarView(account: account, size: 24)
                        VStack(alignment: .leading, spacing: 0) {
                            Text(account.title)
                            Text(account.displayName).font(.caption).foregroundStyle(.secondary)
                        }
                        Spacer()
                        if app.defaultAccountID == account.id {
                            Image(systemName: "star.fill").foregroundStyle(Theme.modified).help("Default account")
                        }
                    }
                    .tag(account.id)
                }
                .overlay {
                    if app.accounts.isEmpty {
                        Text("No accounts").foregroundStyle(.secondary)
                    }
                }
                Divider()
                HStack(spacing: 0) {
                    Button { showingSignIn = true } label: { Image(systemName: "plus").frame(width: 24, height: 20) }
                        .help("Add GitHub account")
                    Button {
                        pendingRemoval = app.account(id: selection)
                    } label: { Image(systemName: "minus").frame(width: 24, height: 20) }
                        .disabled(selection == nil)
                        .help("Remove account")
                    Spacer()
                }
                .buttonStyle(.borderless)
                .padding(4)
            }
            .frame(width: 230)

            Divider()

            if let index = app.accounts.firstIndex(where: { $0.id == selection }) {
                AccountEditor(account: Binding(
                    get: { app.accounts[index] },
                    set: { app.accounts[index] = $0 }
                ), onReconnect: { showingSignIn = true })
            } else {
                ContentUnavailableView {
                    Label("Your GitHub Accounts", systemImage: "person.2.badge.key")
                } description: {
                    Text("Sign in to each GitHub account you use. Then add folder rules so repos pick the right one automatically.")
                } actions: {
                    Button("Add GitHub Account…") { showingSignIn = true }
                }
                .frame(maxWidth: .infinity)
            }
        }
        .sheet(isPresented: $showingSignIn) {
            SignInSheet { selection = $0.id }
        }
        .confirmationDialog("Remove \(pendingRemoval?.title ?? "")?",
                            isPresented: Binding(get: { pendingRemoval != nil }, set: { if !$0 { pendingRemoval = nil } }),
                            presenting: pendingRemoval) { account in
            Button("Remove Account", role: .destructive) {
                app.removeAccount(account)
                selection = nil
            }
        } message: { _ in
            Text("Its token is deleted from the Keychain and folder rules that use it are removed.")
        }
        .onAppear { if selection == nil { selection = app.accounts.first?.id } }
    }
}

private struct AccountEditor: View {
    @Environment(AppState.self) private var app
    @Binding var account: Account
    let onReconnect: () -> Void
    @State private var customEmail = false

    var body: some View {
        Form {
            Section {
                HStack(spacing: 12) {
                    AvatarView(account: account, size: 44)
                    VStack(alignment: .leading) {
                        Text(account.displayName).font(.headline)
                        Text("@\(account.login) on \(account.host)").foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button("Reconnect…", action: onReconnect)
                        .help("Sign in again to refresh the token")
                }
                TextField("Label", text: $account.label, prompt: Text("e.g. Work, Personal"))
                Toggle("Default account", isOn: Binding(
                    get: { app.defaultAccountID == account.id },
                    set: { app.defaultAccountID = $0 ? account.id : nil }
                ))
            }

            Section("Commit identity") {
                TextField("Name", text: $account.commitName)
                if customEmail || !account.knownEmails.contains(account.commitEmail) {
                    TextField("Email", text: $account.commitEmail)
                } else {
                    Picker("Email", selection: $account.commitEmail) {
                        ForEach(account.knownEmails, id: \.self) { Text($0).tag($0) }
                    }
                }
                Toggle("Use a custom email", isOn: $customEmail)
            }

            Section("Commit signing") {
                Toggle("Sign commits", isOn: Binding(
                    get: { account.signing != nil },
                    set: { account.signing = $0 ? (account.signing ?? SigningConfig()) : nil }
                ))
                if let signing = account.signing {
                    Picker("Format", selection: Binding(
                        get: { signing.format }, set: { account.signing?.format = $0 }
                    )) {
                        ForEach(SigningConfig.Format.allCases, id: \.self) { Text($0.title).tag($0) }
                    }
                    HStack {
                        TextField(signing.format == .ssh ? "Public key path" : "GPG key ID",
                                  text: Binding(get: { signing.key }, set: { account.signing?.key = $0 }),
                                  prompt: Text(signing.format == .ssh ? "~/.ssh/id_ed25519.pub" : "3AA5C34371567BD2"))
                        if signing.format == .ssh {
                            Button("Choose…") { chooseSSHKey() }
                        }
                    }
                    Text("Add the same key to GitHub as a **signing key** to get the Verified badge.")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
        }
        .formStyle(.grouped)
        .onChange(of: account.id) { customEmail = false }
    }

    private func chooseSSHKey() {
        let panel = NSOpenPanel()
        panel.directoryURL = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".ssh")
        panel.showsHiddenFiles = true
        panel.allowedContentTypes = []
        panel.message = "Choose the public key (.pub) to sign with"
        if panel.runModal() == .OK, let url = panel.url {
            account.signing?.key = url.path
        }
    }
}

// MARK: - Sign in (device flow)

struct SignInSheet: View {
    @Environment(AppState.self) private var app
    @Environment(\.dismiss) private var dismiss
    let onSignedIn: (Account) -> Void

    enum Phase {
        case intro
        case token
        case requesting
        case waiting(GitHubDeviceFlow.DeviceCode)
        case finishing
        case failed(String)
    }

    @State private var phase: Phase
    @State private var task: Task<Void, Never>?
    @State private var token = ""

    init(startWithToken: Bool = false, onSignedIn: @escaping (Account) -> Void) {
        _phase = State(initialValue: startWithToken ? .token : .intro)
        self.onSignedIn = onSignedIn
    }

    var body: some View {
        VStack(spacing: 18) {
            Image(systemName: "person.badge.key.fill")
                .font(.system(size: 40))
                .foregroundStyle(.tint)
            Text("Add GitHub Account").font(.title2.weight(.semibold))

            switch phase {
            case .intro:
                Text("GitOS signs in through your browser. **Make sure the browser is signed into the GitHub account you want to add.** To add a second account, use a private window or sign out of the first one there.")
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.secondary)
                if app.githubClientID.isEmpty {
                    Label("Set your OAuth app's Client ID in Settings › GitHub first.", systemImage: "exclamationmark.triangle")
                        .foregroundStyle(Theme.modified)
                }
            case .token:
                Text("Use this if an organization hasn't approved GitOS. Tokens don't need its approval unless the organization blocks them.")
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                Link("Create a Classic Token on GitHub", destination: GitHubDeviceFlow.classicTokenURL)
                SecureField("Personal access token", text: $token, prompt: Text("ghp_…"))
                    .textFieldStyle(.roundedBorder)
                Text("Stored in your Keychain. If the organization uses SSO, also choose **Configure SSO** next to the token on GitHub.")
                    .font(.caption)
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            case .requesting, .finishing:
                ProgressView()
            case .waiting(let code):
                Text("Enter this code on GitHub:").foregroundStyle(.secondary)
                Text(code.userCode)
                    .font(.system(size: 34, weight: .bold, design: .monospaced))
                    .textSelection(.enabled)
                Button("Copy Code & Open GitHub") { open(code) }
                    .buttonStyle(.borderedProminent)
                HStack(spacing: 6) {
                    ProgressView().controlSize(.small)
                    Text("Waiting for you to authorize…").foregroundStyle(.secondary)
                }
            case .failed(let message):
                Label(message, systemImage: "xmark.octagon").foregroundStyle(Theme.removed)
                    .multilineTextAlignment(.center)
            }

            HStack {
                Button("Cancel") {
                    task?.cancel()
                    dismiss()
                }
                .keyboardShortcut(.cancelAction)
                Spacer()
                switch phase {
                case .intro, .failed:
                    Button("Use a Token…") { phase = .token }
                    Button("Sign in with Browser") { start() }
                        .keyboardShortcut(.defaultAction)
                        .disabled(app.githubClientID.isEmpty)
                case .token:
                    Button("Use Browser Instead") { phase = .intro }
                    Button("Add Account") { signInWithToken() }
                        .keyboardShortcut(.defaultAction)
                        .disabled(trimmedToken.isEmpty)
                default:
                    EmptyView()
                }
            }
        }
        .padding(24)
        .frame(width: 440)
        .onDisappear { task?.cancel() }
    }

    private var trimmedToken: String { token.trimmingCharacters(in: .whitespacesAndNewlines) }

    private func signInWithToken() {
        let grant = GitHubDeviceFlow.TokenGrant(accessToken: trimmedToken, refreshToken: nil, expiresAt: nil)
        phase = .finishing
        task = Task {
            do {
                let account = try await app.signIn(grant: grant)
                token = ""
                onSignedIn(account)
                dismiss()
            } catch is CancellationError {
            } catch {
                let rejected = (error as? GitHubError)?.statusCode == 401
                phase = .failed(rejected ? "GitHub didn't accept that token. Check it and try again." : error.localizedDescription)
            }
        }
    }

    private func start() {
        let clientID = app.githubClientID.trimmingCharacters(in: .whitespaces)
        phase = .requesting
        task = Task {
            do {
                let code = try await GitHubDeviceFlow.requestCode(clientID: clientID)
                phase = .waiting(code)
                open(code)
                let grant = try await GitHubDeviceFlow.pollForToken(clientID: clientID, code: code)
                phase = .finishing
                let account = try await app.signIn(grant: grant)
                onSignedIn(account)
                dismiss()
            } catch is CancellationError {
            } catch {
                phase = .failed(error.localizedDescription)
            }
        }
    }

    private func open(_ code: GitHubDeviceFlow.DeviceCode) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(code.userCode, forType: .string)
        NSWorkspace.shared.open(code.verificationURI)
    }
}

// MARK: - Folder rules

private struct FolderRulesSettings: View {
    @Environment(AppState.self) private var app
    @State private var selection: FolderRule.ID?

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Repositories inside a folder use that folder's account. The most specific folder wins. A per-repo choice in the toolbar overrides rules.")
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            Table(of: Binding<FolderRule>.self, selection: $selection) {
                TableColumn("Folder") { $rule in
                    Label(rule.folder.abbreviatingWithTildeInPath, systemImage: "folder")
                }
                TableColumn("Account") { $rule in
                    Picker("Account", selection: $rule.accountID) {
                        ForEach(app.accounts) { Text($0.title).tag($0.id) }
                    }
                    .labelsHidden()
                }
                .width(220)
            } rows: {
                @Bindable var app = app
                ForEach($app.rules) { $rule in
                    TableRow($rule)
                }
            }

            HStack {
                Button("Add Folder Rule…", systemImage: "plus") { addRule() }
                    .disabled(app.accounts.isEmpty)
                Button("Remove", systemImage: "minus") {
                    app.rules.removeAll { $0.id == selection }
                }
                .disabled(selection == nil)
                Spacer()
                if let fallback = app.account(id: app.defaultAccountID) {
                    Text("Everything else: \(fallback.title)").foregroundStyle(.secondary).font(.caption)
                }
            }
        }
        .padding(20)
    }

    private func addRule() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.prompt = "Choose Folder"
        panel.message = "Repositories in this folder will use the account you pick next"
        guard panel.runModal() == .OK, let url = panel.url, let account = app.accounts.first else { return }
        let rule = FolderRule(folder: url.path, accountID: account.id)
        app.rules.append(rule)
        selection = rule.id
    }
}

// MARK: - GitHub OAuth app

private struct GitHubSettings: View {
    @Environment(AppState.self) private var app

    var body: some View {
        @Bindable var app = app
        Form {
            Section {
                TextField("OAuth Client ID", text: $app.githubClientID, prompt: Text("Ov23li…"))
                    .font(.body.monospaced())
            } header: {
                Text("GitHub OAuth App")
            } footer: {
                VStack(alignment: .leading, spacing: 4) {
                    Text("One-time setup. Sign-in uses your own OAuth app with Device Flow:")
                    Text("1. Open github.com › Settings › Developer settings › OAuth Apps › New OAuth App")
                    Text("2. Any name. Homepage and callback URL: http://localhost")
                    Text("3. Tick **Enable Device Flow**, register, then paste the Client ID here")
                    Link("Open GitHub OAuth app registration",
                         destination: URL(string: "https://github.com/settings/applications/new")!)
                        .padding(.top, 4)
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
    }
}

// MARK: - AI

private struct AISettings: View {
    @Environment(AppState.self) private var app
    @State private var key = ""
    @State private var hasKey = Claude.apiKey != nil
    @State private var saveError: String?
    @State private var cliPath: String?

    var body: some View {
        @Bindable var app = app
        Form {
            Section {
                Picker("Use", selection: $app.preferences.aiProvider) {
                    ForEach(AIProvider.allCases) { Text($0.name).tag($0) }
                }
                if provider == .apiKey {
                    apiKeyFields
                } else {
                    cliStatus
                }
                if provider != .codex {
                    Picker("Model", selection: $app.preferences.aiModel) {
                        ForEach(Claude.models, id: \.id) { Text($0.name).tag($0.id) }
                    }
                }
            } header: {
                Text("AI")
            } footer: {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Used for ✨ commit messages (⌘⇧G in the commit box) and pull request descriptions. Only the diff and commit messages you're writing about are sent.")
                    if provider == .apiKey {
                        Link("Get an API key", destination: URL(string: "https://platform.claude.com/settings/keys")!)
                    } else {
                        Text("\(provider.name) uses the account you're signed in to on this Mac, and requests count toward that plan's limits.")
                    }
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }
        }
        .task(id: provider) {
            let selected = provider
            cliPath = nil
            cliPath = await Task.detached { AICLI.executable(for: selected) ?? "" }.value
        }
        .formStyle(.grouped)
    }

    private var provider: AIProvider { app.preferences.aiProvider }

    @ViewBuilder private var cliStatus: some View {
        LabeledContent("Command") {
            if let cliPath, !cliPath.isEmpty {
                Text(cliPath.abbreviatingWithTildeInPath).monospaced().textSelection(.enabled)
            } else if cliPath != nil {
                HStack {
                    Text("Not installed").foregroundStyle(.secondary)
                    if let url = provider.installURL { Link("Get \(provider.name)", destination: url) }
                }
            } else {
                ProgressView().controlSize(.small)
            }
        }
    }

    @ViewBuilder private var apiKeyFields: some View {
        if hasKey {
            LabeledContent("API key") {
                HStack {
                    Text("Saved in Keychain").foregroundStyle(.secondary)
                    Button("Remove", role: .destructive) {
                        Keychain.delete(Claude.keychainKey)
                        hasKey = false
                    }
                }
            }
        } else {
            SecureField("Anthropic API key", text: $key, prompt: Text("sk-ant-…"))
            Button("Save Key") {
                do {
                    try Keychain.set(key.trimmingCharacters(in: .whitespacesAndNewlines), for: Claude.keychainKey)
                    key = ""
                    hasKey = true
                    saveError = nil
                } catch {
                    saveError = error.localizedDescription
                }
            }
            .disabled(key.trimmingCharacters(in: .whitespaces).isEmpty)
            if let saveError { Text(saveError).foregroundStyle(Theme.removed).font(.caption) }
        }
    }
}
