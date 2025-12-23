import SwiftUI

/// Settings view for configuring Cloud AI features
struct AISettingsView: View {
    @State private var isCloudAIEnabled: Bool = false
    @State private var selectedProvider: CloudAIService.AIProvider = .openai
    @State private var apiKey: String = ""
    @State private var customModel: String = ""
    @State private var showAPIKey: Bool = false
    @State private var isSavingKey: Bool = false
    @State private var showSaveSuccess: Bool = false
    @State private var showDeleteConfirmation: Bool = false
    @State private var testResult: String? = nil
    @State private var isTesting: Bool = false

    private let cloudAI = CloudAIService.shared

    var body: some View {
        Form {
            // Cloud AI Toggle
            Section(header: Text("Cloud AI"), footer: Text("Enable cloud AI for more natural, conversational health insights. Requires an API key from OpenAI or Anthropic.")) {
                Toggle("Enable Cloud AI", isOn: $isCloudAIEnabled)
                    .onChange(of: isCloudAIEnabled) { _, newValue in
                        cloudAI.isEnabled = newValue
                    }
            }

            if isCloudAIEnabled {
                // Provider Selection
                Section(header: Text("AI Provider")) {
                    Picker("Provider", selection: $selectedProvider) {
                        ForEach(CloudAIService.AIProvider.allCases) { provider in
                            Text(provider.rawValue).tag(provider)
                        }
                    }
                    .pickerStyle(.segmented)
                    .onChange(of: selectedProvider) { _, newValue in
                        cloudAI.provider = newValue
                        // Load existing key for this provider
                        apiKey = ""
                        if cloudAI.hasAPIKey(for: newValue) {
                            apiKey = "••••••••••••••••" // Masked
                        }
                    }

                    // Model info
                    HStack {
                        Text("Default Model")
                            .foregroundColor(.secondary)
                        Spacer()
                        Text(selectedProvider.defaultModel)
                            .foregroundColor(.secondary)
                    }

                    // Custom model override
                    TextField("Custom Model (optional)", text: $customModel)
                        .autocapitalization(.none)
                        .autocorrectionDisabled()
                        .onChange(of: customModel) { _, newValue in
                            cloudAI.customModel = newValue
                        }
                }

                // API Key Management
                Section(header: Text("API Key"), footer: apiKeyFooter) {
                    HStack {
                        if showAPIKey {
                            TextField("API Key", text: $apiKey)
                                .autocapitalization(.none)
                                .autocorrectionDisabled()
                        } else {
                            SecureField("API Key", text: $apiKey)
                                .autocapitalization(.none)
                                .autocorrectionDisabled()
                        }

                        Button {
                            showAPIKey.toggle()
                        } label: {
                            Image(systemName: showAPIKey ? "eye.slash" : "eye")
                                .foregroundColor(.secondary)
                        }
                        .buttonStyle(.plain)
                    }

                    HStack {
                        Button {
                            saveAPIKey()
                        } label: {
                            if isSavingKey {
                                ProgressView()
                                    .frame(maxWidth: .infinity)
                            } else {
                                Text("Save API Key")
                                    .frame(maxWidth: .infinity)
                            }
                        }
                        .buttonStyle(.borderedProminent)
                        .disabled(apiKey.isEmpty || apiKey.contains("•") || isSavingKey)

                        if cloudAI.hasAPIKey(for: selectedProvider) {
                            Button(role: .destructive) {
                                showDeleteConfirmation = true
                            } label: {
                                Image(systemName: "trash")
                            }
                            .buttonStyle(.bordered)
                        }
                    }

                    if showSaveSuccess {
                        HStack {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundColor(.green)
                            Text("API key saved securely")
                                .foregroundColor(.green)
                        }
                        .transition(.opacity)
                    }
                }

                // Test Connection
                Section(header: Text("Test Connection")) {
                    Button {
                        testConnection()
                    } label: {
                        HStack {
                            if isTesting {
                                ProgressView()
                                    .padding(.trailing, 8)
                            }
                            Text(isTesting ? "Testing..." : "Test AI Connection")
                        }
                        .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                    .disabled(!cloudAI.hasAPIKey(for: selectedProvider) || isTesting)

                    if let result = testResult {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Response:")
                                .font(.caption)
                                .foregroundColor(.secondary)
                            Text(result)
                                .font(.callout)
                                .padding()
                                .background(Color(.tertiarySystemBackground))
                                .cornerRadius(8)
                        }
                    }
                }

                // Usage Info
                Section(header: Text("Information")) {
                    VStack(alignment: .leading, spacing: 12) {
                        InfoRow(
                            icon: "lock.shield",
                            title: "Secure Storage",
                            description: "Your API key is stored securely in the device Keychain"
                        )

                        InfoRow(
                            icon: "icloud.slash",
                            title: "No Cloud Sync",
                            description: "API keys are never synced to iCloud or external servers"
                        )

                        InfoRow(
                            icon: "dollarsign.circle",
                            title: "Usage Costs",
                            description: "API calls may incur costs from your provider"
                        )
                    }
                    .padding(.vertical, 4)
                }

                // Privacy Notice
                Section(header: Text("Privacy")) {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("When Cloud AI is enabled:")
                            .font(.subheadline)
                            .fontWeight(.medium)

                        BulletPoint(text: "Symptom summaries are sent to the AI provider")
                        BulletPoint(text: "No personal identifiers are included")
                        BulletPoint(text: "Data is not stored by the AI provider")
                        BulletPoint(text: "You can disable this anytime")
                    }
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .padding(.vertical, 4)
                }
            }
        }
        .navigationTitle("AI Settings")
        .onAppear {
            loadSettings()
        }
        .alert("Delete API Key?", isPresented: $showDeleteConfirmation) {
            Button("Cancel", role: .cancel) {}
            Button("Delete", role: .destructive) {
                deleteAPIKey()
            }
        } message: {
            Text("This will remove the API key for \(selectedProvider.rawValue). You'll need to enter it again to use Cloud AI.")
        }
    }

    private var apiKeyFooter: some View {
        VStack(alignment: .leading, spacing: 4) {
            if selectedProvider == .openai {
                Text("Get your API key from platform.openai.com")
            } else {
                Text("Get your API key from console.anthropic.com")
            }
        }
    }

    private func loadSettings() {
        isCloudAIEnabled = cloudAI.isEnabled
        selectedProvider = cloudAI.provider
        customModel = cloudAI.customModel

        if cloudAI.hasAPIKey(for: selectedProvider) {
            apiKey = "••••••••••••••••"
        }
    }

    private func saveAPIKey() {
        guard !apiKey.isEmpty && !apiKey.contains("•") else { return }

        isSavingKey = true

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            let success = cloudAI.saveAPIKey(apiKey, for: selectedProvider)

            isSavingKey = false

            if success {
                apiKey = "••••••••••••••••"
                showSaveSuccess = true

                DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                    withAnimation {
                        showSaveSuccess = false
                    }
                }
            }
        }
    }

    private func deleteAPIKey() {
        _ = cloudAI.deleteAPIKey(for: selectedProvider)
        apiKey = ""
        testResult = nil
    }

    private func testConnection() {
        isTesting = true
        testResult = nil

        cloudAI.generateHealthInsight(
            symptoms: ["test"],
            severity: 2,
            triggers: [],
            whatWorked: [],
            recentPatterns: [],
            userContext: "This is a test message to verify the connection."
        ) { result in
            isTesting = false

            switch result {
            case .success(let response):
                testResult = response
            case .failure(let error):
                testResult = "Error: \(error.localizedDescription)"
            }
        }
    }
}

// MARK: - Supporting Views

struct InfoRow: View {
    let icon: String
    let title: String
    let description: String

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: icon)
                .foregroundColor(.blue)
                .frame(width: 24)

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.subheadline)
                    .fontWeight(.medium)
                Text(description)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
    }
}

struct BulletPoint: View {
    let text: String

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Text("•")
            Text(text)
        }
    }
}

#Preview {
    NavigationStack {
        AISettingsView()
    }
}
