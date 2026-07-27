import Testing
@testable import Food_Intolerances

/// Pins the promise copy VERBATIM (the PoorAirWarningBanner.title(for:)
/// pattern). This copy deliberately supersedes UI design §5 on two counts:
/// "your data never leaves this device" is false (coordinates go to
/// OpenWeather; CloudAIService is a BYOK client for OpenAI/Anthropic), and
/// "find what actually helps you" implies causation the engine does not
/// establish — it finds associations. A drive-by copy edit that reintroduces
/// either claim must fail here, not in review.
@Suite struct FirstRunPromiseCopyTests {
    @Test func headlineClaimsAssociationNotCausation() {
        #expect(FirstRunPromiseView.headline
                == "Notice patterns in what may help — or make symptoms worse.")
    }

    @Test func privacyCopyIsHonestAboutWhatLeavesTheDevice() {
        #expect(FirstRunPromiseView.privacy
                == "Your Health Graph is stored on this device. Environment features share your "
                 + "location with the weather provider only when enabled. Cloud AI is optional "
                 + "and off by default.")
    }
}
