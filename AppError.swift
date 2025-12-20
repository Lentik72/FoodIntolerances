import Foundation

enum AppError: Error, LocalizedError {
    case locationUnavailable
    case dataFetchFailed(String)
    case saveFailed(String)
    case networkError(String)
    case permissionDenied(String)
    case validationError(String)
    
    var errorDescription: String? {
        switch self {
        case .locationUnavailable:
            return "Location services are unavailable. Some features will be limited."
        case .dataFetchFailed(let details):
            return "Failed to fetch data: \(details)"
        case .saveFailed(let details):
            return "Failed to save: \(details)"
        case .networkError(let details):
            return "Network error: \(details)"
        case .permissionDenied(let details):
            return "Permission denied: \(details)"
        case .validationError(let details):
            return "Validation error: \(details)"
        }
    }
    
    var recoverySuggestion: String? {
        switch self {
        case .locationUnavailable:
            return "You can enable location services in Settings to access weather data and other location-based features."
        case .permissionDenied(let feature):
            return "Please go to Settings and enable permission for \(feature) to use this feature."
        case .validationError:
            return "Please check your input and try again."
        default:
            return "Please try again later or contact support if the problem persists."
        }
    }
}

// Protocol for error presentation
protocol ErrorPresentable: AnyObject {
    var alertMessage: String { get set }
    var showAlert: Bool { get set }
}

// Extension with helper method for convenience
extension ErrorPresentable {
    func setErrorAlert(message: String) {
        self.alertMessage = message
        self.showAlert = true
    }
}

// Extension with enhanced handler
extension AppError {
    static func handle<T: ErrorPresentable>(_ error: Error, in viewModel: T) {
        let appError: AppError
        
        if let error = error as? AppError {
            appError = error
        } else {
            appError = .saveFailed(error.localizedDescription)
        }
        
        print("Error occurred: \(appError.localizedDescription)")
        
        // Use the method instead of direct property access
        DispatchQueue.main.async {
            viewModel.setErrorAlert(message: appError.errorDescription ?? "An unknown error occurred")
        }
    }
    
    // Additional handler for async context
    static func handleAsync(_ error: Error) async -> AppError {
        if let appError = error as? AppError {
            return appError
        }
        return .saveFailed(error.localizedDescription)
    }
}
