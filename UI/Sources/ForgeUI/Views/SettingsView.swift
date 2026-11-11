import ForgeCore
import SwiftUI
import UniformTypeIdentifiers

public struct SettingsView: View {
    @Environment(AppModel.self) private var model
    @State private var apiKey = ""
    @State private var importing = false
    @State private var report: ImportReport?
    @State private var importError: String?
    @State private var connectingHealth = false
    @State private var hubURL = ""
    @State private var hubToken = ""
    @State private var hubHost = ""
    @State private var syncSetupError: String?
    @State private var exporting = false
    @State private var exportDocument: ForgeExportDocument?

    public init() {}

    public var body: some View {
        @Bindable var model = model
        NavigationStack {
            Form {
                Section("Units") {
                    Picker("Weight", selection: $model.unit) {
                        Text("Pounds (lb)").tag(WeightUnit.lb)
                        Text("Kilograms (kg)").tag(WeightUnit.kg)
                    }
                }.listRowBackground(Theme.card)
                Section("Training") {
                    Stepper("Default rest  \(Units.clock(seconds: model.defaultRestSeconds))", value: $model.defaultRestSeconds, in: 15...300, step: 15)
                    NavigationLink("Bodyweight") { BodyweightView() }
                    NavigationLink("Changes and undo") { ChangesView() }
                }.listRowBackground(Theme.card)
                if model.healthAvailable {
                    Section {
                        LabeledContent("Status", value: connectingHealth ? "Waiting for permission…" : (model.healthEnabled ? "Connected" : "Not connected"))
                        Button(model.healthEnabled ? "Disconnect Apple Health" : "Connect Apple Health") {
                            connectingHealth = true
                            Task {
                                await model.setHealthEnabled(!model.healthEnabled)
                                connectingHealth = false
                            }
                        }
                        .disabled(connectingHealth)
                    } header: { Text("Apple Health") } footer: {
                        Text("Finished workouts are saved to Health, and sleep, HRV and resting heart rate are read so your Mac and Claude can see recovery next to training.")
                    }.listRowBackground(Theme.card)
                }
                Section {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Status").font(.caption).foregroundStyle(Theme.dim)
                        Text(model.syncStatus)
                    }
                    if model.syncConfigured {
                        Button { Task { await model.syncNow() } } label: { if model.syncing { ProgressView() } else { Text("Sync now") } }
                            .disabled(model.syncing)
                        Button("Remove sync setup", role: .destructive) { model.clearSyncConfig() }
                    } else {
                        TextField("Hub address (https://…)", text: $hubURL)
                            #if os(iOS)
                            .textInputAutocapitalization(.never).autocorrectionDisabled().keyboardType(.URL)
                            #endif
                        SecureField("Token", text: $hubToken)
                        TextField("Host header (only if you connect by IP)", text: $hubHost)
                            #if os(iOS)
                            .textInputAutocapitalization(.never).autocorrectionDisabled()
                            #endif
                        Button("Connect") {
                            do { try model.saveSyncConfig(url: hubURL, token: hubToken, hostHeader: hubHost); hubToken = ""; syncSetupError = nil; Task { await model.syncNow() } }
                            catch { syncSetupError = (error as? ForgeError)?.message ?? "\(error)" }
                        }
                        .disabled(hubURL.isEmpty || hubToken.isEmpty)
                        if let syncSetupError { Text(syncSetupError).font(.footnote).foregroundStyle(Theme.danger) }
                    }
                } header: { Text("Sync") } footer: {
                    Text("Keeps your phone, Mac and Claude on the same workouts. The token comes from the hub's tokens file.")
                }.listRowBackground(Theme.card)
                Section {
                    SecureField("Hevy API key", text: $apiKey)
                    Button { runImport() } label: {
                        if importing { ProgressView() } else { Text("Import from Hevy") }
                    }
                    .disabled(apiKey.trimmingCharacters(in: .whitespaces).isEmpty || importing)
                    if let report {
                        Text("Added \(report.exercises.added) exercises, \(report.routines.added) routines, \(report.workouts.added) workouts. Skipped \(report.workouts.skipped + report.routines.skipped + report.exercises.skipped) already here.")
                            .font(.footnote)
                        ForEach(report.warnings.prefix(3), id: \.self) { Text($0).font(.caption).foregroundStyle(Theme.dim) }
                    }
                    if let importError { Text(importError).font(.footnote).foregroundStyle(Theme.danger) }
                } header: { Text("Hevy") } footer: {
                    Text("Create a key at hevy.com → Settings → Developer. It's only used for this import and isn't stored. Running the import again only adds what's new.")
                }.listRowBackground(Theme.card)
                Section("Library") {
                    Button("Add starter exercises") { model.addStarterLibrary() }
                    Button("Export all data…") {
                        do { exportDocument = ForgeExportDocument(data: try model.exportData()); exporting = true } catch { model.lastError = "Export failed: \(error)" }
                    }
                    LabeledContent("Exercises", value: "\(model.exercises.count)")
                    LabeledContent("Routines", value: "\(model.routines.count)")
                    LabeledContent("Workouts", value: "\(model.workouts.count)")
                }.listRowBackground(Theme.card)
                if let error = model.lastError {
                    Section("Last error") { Text(error).font(.footnote); Button("Clear") { model.lastError = nil } }.listRowBackground(Theme.card)
                }
            }
            .formStyle(.grouped)
            .themedList()
            .navigationTitle("Settings")
            .fileExporter(isPresented: $exporting, document: exportDocument, contentType: .json, defaultFilename: "forge-export") { _ in }
        }
    }

    private func runImport() {
        importing = true
        importError = nil
        report = nil
        let key = apiKey.trimmingCharacters(in: .whitespaces)
        Task {
            do { report = try await model.importHevy(apiKey: key); apiKey = "" } catch {
                importError = (error as? ForgeError)?.message ?? "\(error)"
            }
            importing = false
        }
    }
}


/// The export as a file the system's save dialog can write.
struct ForgeExportDocument: FileDocument {
    static var readableContentTypes: [UTType] { [.json] }
    var data: Data

    init(data: Data) { self.data = data }
    init(configuration: ReadConfiguration) throws { data = configuration.file.regularFileContents ?? Data() }
    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper { FileWrapper(regularFileWithContents: data) }
}
