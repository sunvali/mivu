import SwiftUI

struct AdultEligibilityView: View {
    @Bindable var model: DiaryViewModel
    @Bindable var connection: ChatGPTConnection
    @State private var confirmDeletion = false

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Text("Mivu is for adults 18 and older").font(.title2.bold())
                    Text("Confirm that you have already turned 18 to log meals and use Coach. Your existing records are preserved.")
                    if AdultEligibility.canConfirm(birthYear: model.readModel?.profile.about?.birthYear) {
                        Button("I am 18 or older") { Task { await model.confirmAdultEligibility() } }
                            .frame(minHeight: 44).accessibilityIdentifier("confirmAdultEligibility")
                    } else {
                        Text("The birth year saved in this diary is under 18. You can still view, export or delete your records.")
                    }
                }
                Section("Your records") {
                    NavigationLink("View diary") { HistoryView(model: model) }
                    NavigationLink("Backup & export") { Form { DiaryBackupSettings(model: model) }.navigationTitle("Backup & export") }
                    Button("Choose another diary") { Task { await model.signOut() } }.frame(minHeight: 44)
                    Button("Disconnect ChatGPT") { Task { await connection.disconnect() } }.frame(minHeight: 44)
                    Button("Delete profile", role: .destructive) { confirmDeletion = true }.frame(minHeight: 44)
                }
                Section {
                    Link("Contact support", destination: MivuLinks.support).frame(minHeight: 44)
                    Link("Privacy Policy", destination: MivuLinks.privacyPolicy).frame(minHeight: 44)
                }
            }
            .navigationTitle("Mivu")
            .confirmationDialog("Delete this profile?", isPresented: $confirmDeletion, titleVisibility: .visible) {
                Button("Delete profile", role: .destructive) {
                    if let id = model.selection?.identity.profileID { Task { await model.deleteProfile(id) } }
                }
            } message: { Text("This removes local records. Copies you saved elsewhere remain where you saved them.") }
        }
    }
}
