import SwiftUI
import SwiftData

/// Helper for consistent save error handling across the app
struct SaveHelper {

    /// Attempts to save the model context and returns success status
    /// - Parameters:
    ///   - context: The SwiftData model context
    ///   - errorBinding: Optional binding to show error alert
    ///   - messageBinding: Optional binding for error message
    /// - Returns: true if save succeeded, false otherwise
    @MainActor
    static func save(
        context: ModelContext,
        showError: Binding<Bool>? = nil,
        errorMessage: Binding<String>? = nil
    ) -> Bool {
        do {
            try context.save()
            return true
        } catch {
            Logger.error(error, message: "Save failed", category: .data)
            errorMessage?.wrappedValue = "Could not save your data. Please try again."
            showError?.wrappedValue = true
            return false
        }
    }

    /// Attempts to save with a custom error message
    @MainActor
    static func save(
        context: ModelContext,
        showError: Binding<Bool>? = nil,
        customMessage: String
    ) -> Bool {
        do {
            try context.save()
            return true
        } catch {
            Logger.error(error, message: "Save failed", category: .data)
            showError?.wrappedValue = true
            return false
        }
    }
}

/// View modifier to add standard save error alert
struct SaveErrorAlertModifier: ViewModifier {
    @Binding var showError: Bool
    let message: String

    func body(content: Content) -> some View {
        content
            .alert("Save Failed", isPresented: $showError) {
                Button("OK", role: .cancel) { }
            } message: {
                Text(message)
            }
    }
}

extension View {
    /// Adds a standard save error alert to the view
    func saveErrorAlert(isPresented: Binding<Bool>, message: String = "Could not save your data. Please try again.") -> some View {
        modifier(SaveErrorAlertModifier(showError: isPresented, message: message))
    }
}
