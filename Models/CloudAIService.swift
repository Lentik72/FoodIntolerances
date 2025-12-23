import Foundation
import Security

/// Service for cloud-based AI features using external APIs
/// Supports OpenAI and Anthropic for natural language health insights
class CloudAIService {

    static let shared = CloudAIService()

    // MARK: - Configuration

    enum AIProvider: String, CaseIterable, Identifiable {
        case openai = "OpenAI"
        case anthropic = "Anthropic"

        var id: String { rawValue }

        var apiEndpoint: String {
            switch self {
            case .openai: return "https://api.openai.com/v1/chat/completions"
            case .anthropic: return "https://api.anthropic.com/v1/messages"
            }
        }

        var defaultModel: String {
            switch self {
            case .openai: return "gpt-4o-mini"
            case .anthropic: return "claude-3-haiku-20240307"
            }
        }

        var keychainKey: String {
            "com.foodintolerances.apikey.\(rawValue.lowercased())"
        }
    }

    // MARK: - Settings

    @UserDefault(key: "cloudAIEnabled", defaultValue: false)
    var isEnabled: Bool

    @UserDefault(key: "cloudAIProvider", defaultValue: "OpenAI")
    private var providerRawValue: String

    var provider: AIProvider {
        get { AIProvider(rawValue: providerRawValue) ?? .openai }
        set { providerRawValue = newValue.rawValue }
    }

    @UserDefault(key: "cloudAIModel", defaultValue: "")
    var customModel: String

    var activeModel: String {
        customModel.isEmpty ? provider.defaultModel : customModel
    }

    // MARK: - API Key Management (Keychain)

    func saveAPIKey(_ key: String, for provider: AIProvider) -> Bool {
        let data = key.data(using: .utf8)!

        // Delete existing key first
        let deleteQuery: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: provider.keychainKey
        ]
        SecItemDelete(deleteQuery as CFDictionary)

        // Add new key
        let addQuery: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: provider.keychainKey,
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlockedThisDeviceOnly
        ]

        let status = SecItemAdd(addQuery as CFDictionary, nil)

        if status == errSecSuccess {
            Logger.info("API key saved for \(provider.rawValue)", category: .data)
            return true
        } else {
            Logger.error(NSError(domain: "Keychain", code: Int(status)), message: "Failed to save API key", category: .data)
            return false
        }
    }

    func getAPIKey(for provider: AIProvider) -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: provider.keychainKey,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]

        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)

        if status == errSecSuccess, let data = result as? Data {
            return String(data: data, encoding: .utf8)
        }

        return nil
    }

    func deleteAPIKey(for provider: AIProvider) -> Bool {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: provider.keychainKey
        ]

        let status = SecItemDelete(query as CFDictionary)
        return status == errSecSuccess || status == errSecItemNotFound
    }

    func hasAPIKey(for provider: AIProvider) -> Bool {
        return getAPIKey(for: provider) != nil
    }

    // MARK: - AI Response Generation

    /// Generate a natural language health insight
    func generateHealthInsight(
        symptoms: [String],
        severity: Int,
        triggers: [String],
        whatWorked: [String],
        recentPatterns: [String],
        userContext: String = "",
        completion: @escaping (Result<String, CloudAIError>) -> Void
    ) {
        guard isEnabled else {
            completion(.failure(.notEnabled))
            return
        }

        guard let apiKey = getAPIKey(for: provider) else {
            completion(.failure(.noAPIKey))
            return
        }

        let prompt = buildHealthPrompt(
            symptoms: symptoms,
            severity: severity,
            triggers: triggers,
            whatWorked: whatWorked,
            recentPatterns: recentPatterns,
            userContext: userContext
        )

        makeAPIRequest(prompt: prompt, apiKey: apiKey, completion: completion)
    }

    /// Generate food safety analysis
    func analyzeFoodSafety(
        food: String,
        allergies: [String],
        intolerances: [String],
        previousReactions: [String],
        completion: @escaping (Result<String, CloudAIError>) -> Void
    ) {
        guard isEnabled else {
            completion(.failure(.notEnabled))
            return
        }

        guard let apiKey = getAPIKey(for: provider) else {
            completion(.failure(.noAPIKey))
            return
        }

        let prompt = buildFoodSafetyPrompt(
            food: food,
            allergies: allergies,
            intolerances: intolerances,
            previousReactions: previousReactions
        )

        makeAPIRequest(prompt: prompt, apiKey: apiKey, completion: completion)
    }

    /// Generate weekly health summary
    func generateWeeklySummary(
        symptomCounts: [(String, Int)],
        averageSeverity: Double,
        triggersIdentified: [String],
        improvementsTried: [String],
        completion: @escaping (Result<String, CloudAIError>) -> Void
    ) {
        guard isEnabled else {
            completion(.failure(.notEnabled))
            return
        }

        guard let apiKey = getAPIKey(for: provider) else {
            completion(.failure(.noAPIKey))
            return
        }

        let prompt = buildWeeklySummaryPrompt(
            symptomCounts: symptomCounts,
            averageSeverity: averageSeverity,
            triggersIdentified: triggersIdentified,
            improvementsTried: improvementsTried
        )

        makeAPIRequest(prompt: prompt, apiKey: apiKey, completion: completion)
    }

    // MARK: - Private Methods

    private func buildHealthPrompt(
        symptoms: [String],
        severity: Int,
        triggers: [String],
        whatWorked: [String],
        recentPatterns: [String],
        userContext: String
    ) -> String {
        var prompt = """
        You are a helpful health assistant providing personalized insights based on the user's symptom history. \
        Be empathetic, concise, and actionable. Never diagnose conditions or recommend stopping medications. \
        Always suggest consulting a healthcare provider for serious concerns.

        Current situation:
        - Symptoms: \(symptoms.joined(separator: ", "))
        - Severity: \(severity)/5

        """

        if !triggers.isEmpty {
            prompt += "- Known triggers for this user: \(triggers.joined(separator: ", "))\n"
        }

        if !whatWorked.isEmpty {
            prompt += "- What has helped before: \(whatWorked.joined(separator: ", "))\n"
        }

        if !recentPatterns.isEmpty {
            prompt += "- Recent patterns observed: \(recentPatterns.joined(separator: "; "))\n"
        }

        if !userContext.isEmpty {
            prompt += "- Additional context: \(userContext)\n"
        }

        prompt += """

        Provide a brief, personalized response (2-3 sentences) that:
        1. Acknowledges the symptoms
        2. References what has worked for them before (if applicable)
        3. Offers one practical suggestion

        Keep the tone warm and supportive.
        """

        return prompt
    }

    private func buildFoodSafetyPrompt(
        food: String,
        allergies: [String],
        intolerances: [String],
        previousReactions: [String]
    ) -> String {
        var prompt = """
        You are a food safety assistant helping someone with food allergies and intolerances. \
        Be cautious and prioritize safety. When in doubt, recommend avoiding the food.

        User wants to know if they can eat: \(food)

        User's allergies: \(allergies.isEmpty ? "None reported" : allergies.joined(separator: ", "))
        User's intolerances: \(intolerances.isEmpty ? "None reported" : intolerances.joined(separator: ", "))
        """

        if !previousReactions.isEmpty {
            prompt += "\nPrevious reactions to similar foods: \(previousReactions.joined(separator: "; "))"
        }

        prompt += """

        Provide a brief safety assessment:
        1. Is this food likely safe, needs caution, or should be avoided?
        2. Any cross-reactivity concerns?
        3. One practical tip if they decide to try it

        Be concise (2-3 sentences).
        """

        return prompt
    }

    private func buildWeeklySummaryPrompt(
        symptomCounts: [(String, Int)],
        averageSeverity: Double,
        triggersIdentified: [String],
        improvementsTried: [String]
    ) -> String {
        let symptomsText = symptomCounts.map { "\($0.0): \($0.1) times" }.joined(separator: ", ")

        return """
        You are a health assistant providing a weekly summary. Be encouraging and actionable.

        This week's data:
        - Symptoms logged: \(symptomsText)
        - Average severity: \(String(format: "%.1f", averageSeverity))/5
        - Triggers identified: \(triggersIdentified.isEmpty ? "None new" : triggersIdentified.joined(separator: ", "))
        - Remedies tried: \(improvementsTried.isEmpty ? "None logged" : improvementsTried.joined(separator: ", "))

        Provide a brief weekly summary (3-4 sentences) that:
        1. Highlights any improvements or concerns
        2. Notes patterns worth watching
        3. Suggests one focus area for next week

        Keep it positive and motivating.
        """
    }

    private func makeAPIRequest(
        prompt: String,
        apiKey: String,
        completion: @escaping (Result<String, CloudAIError>) -> Void
    ) {
        guard let url = URL(string: provider.apiEndpoint) else {
            completion(.failure(.invalidURL))
            return
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = 30

        // Set headers based on provider
        switch provider {
        case .openai:
            request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")

            let body: [String: Any] = [
                "model": activeModel,
                "messages": [
                    ["role": "system", "content": "You are a helpful health assistant. Keep responses concise and supportive."],
                    ["role": "user", "content": prompt]
                ],
                "max_tokens": 300,
                "temperature": 0.7
            ]
            request.httpBody = try? JSONSerialization.data(withJSONObject: body)

        case .anthropic:
            request.setValue(apiKey, forHTTPHeaderField: "x-api-key")
            request.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")

            let body: [String: Any] = [
                "model": activeModel,
                "max_tokens": 300,
                "messages": [
                    ["role": "user", "content": prompt]
                ],
                "system": "You are a helpful health assistant. Keep responses concise and supportive."
            ]
            request.httpBody = try? JSONSerialization.data(withJSONObject: body)
        }

        URLSession.shared.dataTask(with: request) { data, response, error in
            DispatchQueue.main.async {
                if let error = error {
                    Logger.error(error, message: "Cloud AI request failed", category: .network)
                    completion(.failure(.networkError(error)))
                    return
                }

                guard let data = data else {
                    completion(.failure(.noData))
                    return
                }

                // Parse response based on provider
                do {
                    let responseText = try self.parseResponse(data: data)
                    completion(.success(responseText))
                } catch let parseError as CloudAIError {
                    completion(.failure(parseError))
                } catch {
                    completion(.failure(.parseError(error)))
                }
            }
        }.resume()
    }

    private func parseResponse(data: Data) throws -> String {
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw CloudAIError.invalidResponse
        }

        // Check for API errors
        if let error = json["error"] as? [String: Any],
           let message = error["message"] as? String {
            throw CloudAIError.apiError(message)
        }

        switch provider {
        case .openai:
            if let choices = json["choices"] as? [[String: Any]],
               let firstChoice = choices.first,
               let message = firstChoice["message"] as? [String: Any],
               let content = message["content"] as? String {
                return content.trimmingCharacters(in: .whitespacesAndNewlines)
            }

        case .anthropic:
            if let content = json["content"] as? [[String: Any]],
               let firstContent = content.first,
               let text = firstContent["text"] as? String {
                return text.trimmingCharacters(in: .whitespacesAndNewlines)
            }
        }

        throw CloudAIError.invalidResponse
    }
}

// MARK: - Error Types

enum CloudAIError: LocalizedError {
    case notEnabled
    case noAPIKey
    case invalidURL
    case networkError(Error)
    case noData
    case invalidResponse
    case parseError(Error)
    case apiError(String)

    var errorDescription: String? {
        switch self {
        case .notEnabled:
            return "Cloud AI is not enabled"
        case .noAPIKey:
            return "No API key configured"
        case .invalidURL:
            return "Invalid API URL"
        case .networkError(let error):
            return "Network error: \(error.localizedDescription)"
        case .noData:
            return "No data received from API"
        case .invalidResponse:
            return "Invalid response format"
        case .parseError(let error):
            return "Failed to parse response: \(error.localizedDescription)"
        case .apiError(let message):
            return "API error: \(message)"
        }
    }
}

// MARK: - UserDefault Property Wrapper

@propertyWrapper
struct UserDefault<T> {
    let key: String
    let defaultValue: T

    var wrappedValue: T {
        get { UserDefaults.standard.object(forKey: key) as? T ?? defaultValue }
        set { UserDefaults.standard.set(newValue, forKey: key) }
    }
}
