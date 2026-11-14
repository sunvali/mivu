import SwiftUI

extension KeyService: Identifiable { var id: String { rawValue } }

extension View {
    /// App Review 5.1.2(i): name the service and the data before anything is shared with it.
    func sharingConsent(for service: KeyService, isPresented: Binding<Bool>, connection: ChatGPTConnection, onAgree: @escaping () -> Void) -> some View {
        alert("Share with \(service.company)?", isPresented: isPresented) {
            Button("Agree and Continue") { connection.recordConsent(to: service); onAgree() }
            Button("Not Now", role: .cancel) {}
        } message: {
            Text("To estimate nutrition and answer Coach, Mivu sends \(service.company), using your own \(service.name) account, what you record: meals, photos, messages, weights, workouts, goals and profile details.\(service == .openRouter ? " OpenRouter passes it on to the maker of the model you pick." : "") Your diary stays on this iPhone, and you can remove the key any time in Settings.")
        }
    }
}

/// One row for a key service. A connected service becomes the Coach AI; otherwise consent comes first, then the connect screen.
struct KeyServiceLink<Label: View>: View {
    let connection: ChatGPTConnection
    let service: KeyService
    var onConnected: () -> Void = {}
    @ViewBuilder var label: Label
    @State private var askConsent = false
    @State private var connecting = false

    var body: some View {
        Button {
            if connection.available(.init(rawValue: service.rawValue)!) { connection.provider = .init(rawValue: service.rawValue)!; onConnected() }
            else if connection.consented(to: service) { connecting = true }
            else { askConsent = true }
        } label: { label }
        .accessibilityIdentifier("keyService." + service.rawValue)
        .sharingConsent(for: service, isPresented: $askConsent, connection: connection) { connecting = true }
        .sheet(isPresented: $connecting) {
            ConnectKeyServiceView(connection: connection, service: service) { connecting = false; onConnected() }
        }
    }
}

/// The list behind "Use another AI" in setup.
struct UseAnotherAIView: View {
    let connection: ChatGPTConnection
    var onConnected: () -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                Section {
                    ForEach(KeyService.allCases) { service in
                        KeyServiceLink(connection: connection, service: service, onConnected: onConnected) {
                            HStack {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(service.name).foregroundStyle(Color.diaryText)
                                    Text(service.caption).font(.caption).foregroundStyle(Color.diarySecondary)
                                }
                                Spacer()
                                Image(systemName: "chevron.forward").font(.footnote.weight(.semibold)).foregroundStyle(.tertiary).accessibilityHidden(true)
                            }
                            .frame(minHeight: 44).contentShape(Rectangle())
                        }
                    }
                } header: {
                    Text("Bring a key from a service you already use.").textCase(nil)
                } footer: {
                    Text("You pay the service directly for what you use. Mivu adds nothing.")
                }
            }
            .scrollContentBackground(.hidden).background(Color.diaryCanvas)
            .navigationTitle("Use another AI").navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } } }
        }
    }
}

/// Paste a key, or sign in to OpenRouter. The key is checked with the service before it is kept.
struct ConnectKeyServiceView: View {
    let connection: ChatGPTConnection
    let service: KeyService
    var onConnected: () -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var key = ""
    @State private var message: String?

    var body: some View {
        NavigationStack {
            Form {
                if service.connectsBySignIn { signIn } else { paste }
            }
            .scrollContentBackground(.hidden).background(Color.diaryCanvas)
            .navigationTitle("Connect \(service.name)").navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { if connection.isConnecting { connection.cancelConnection() }; dismiss() }
                }
            }
        }
    }

    private var cost: Text {
        Text("You pay \(service.company) directly for what you use. Mivu adds nothing. [Privacy policy](\(MivuLinks.privacyPolicy.absoluteString))")
    }

    @ViewBuilder private var paste: some View {
        Section {
            Link(destination: service.keyPage) {
                let open = Label("Open \(service.keyPageName)", systemImage: "arrow.up.right").labelStyle(.titleAndIcon).fontWeight(.semibold)
                ViewThatFits(in: .horizontal) {
                    HStack { Text("Get a key").foregroundStyle(Color.diaryText); Spacer(minLength: 12); open }
                    VStack(alignment: .leading, spacing: 4) { Text("Get a key").foregroundStyle(Color.diaryText); open }
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .frame(minHeight: 44)
            }
        }
        Section {
            SecureField("Paste your key", text: $key)
                .textInputAutocapitalization(.never).autocorrectionDisabled()
                .accessibilityIdentifier("keyField").frame(minHeight: 44)
            PasteButton(payloadType: String.self) { if let pasted = $0.first { key = pasted } }
                .labelStyle(.titleAndIcon).buttonBorderShape(.capsule).frame(minHeight: 44)
            if let message { Text(message).font(.subheadline).foregroundStyle(Color.diaryError) }
        } header: {
            Text("Your key")
        } footer: {
            Text("Stays in this iPhone's Keychain. Never in backups or exports.")
        }
        Section {
            Button(action: save) {
                Group { if connection.isCheckingKey { ProgressView().tint(Color.diaryActionText) } else { Text("Test and save") } }
                    .font(.headline).frame(maxWidth: .infinity, minHeight: 52)
            }
            .buttonStyle(.glassProminent).tint(.diaryAccent).foregroundStyle(Color.diaryActionText)
            .disabled(key.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || connection.isCheckingKey)
            .accessibilityIdentifier("saveKey")
            .listRowInsets(EdgeInsets()).listRowBackground(Color.clear)
        } footer: { cost }
    }

    @ViewBuilder private var signIn: some View {
        Section {
            if connection.isConnecting {
                ProgressView("Waiting for \(service.name)…").frame(maxWidth: .infinity, minHeight: 44)
                Button("Cancel connection") { connection.cancelConnection() }.frame(minHeight: 44)
            } else {
                Button {
                    Task {
                        await connection.signInOpenRouter()
                        if connection.connectedServices.contains(service) { onConnected() }
                    }
                } label: { Text("Sign in to \(service.name)").font(.headline).frame(maxWidth: .infinity, minHeight: 52) }
                .buttonStyle(.glassProminent).tint(.diaryAccent).foregroundStyle(Color.diaryActionText)
                .accessibilityIdentifier("signInOpenRouter")
                .listRowInsets(EdgeInsets()).listRowBackground(Color.clear)
            }
            if let notice = connection.notice { Text(notice.rawValue).font(.subheadline).foregroundStyle(Color.diarySecondary) }
        } header: {
            Text("One account reaches many models. No key to copy.").textCase(nil)
        } footer: { cost }
    }

    private func save() {
        message = nil
        Task {
            do { try await connection.saveKey(key, for: service); key = ""; onConnected() }
            catch {
                // The typed key stays in the field so a typo can be fixed.
                message = switch error as? KeyConnectionError {
                case .invalidKey: "Enter the key without spaces."
                case .rejected: "\(service.name) rejected this key. Check it and try again."
                case .storage: "Could not save this key securely. Your input is still here."
                default: "Couldn't reach \(service.name). Check your connection and try again."
                }
            }
        }
    }
}
