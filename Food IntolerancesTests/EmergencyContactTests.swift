import Testing
@testable import Food_Intolerances

struct EmergencyContactTests {
    @Test func callURLUsesTheEmergencyNumberConstant() {
        #expect(EmergencyContact.callURL?.absoluteString == "tel://\(EmergencyContact.emergencyNumber)")
        #expect(EmergencyContact.emergencyNumber == "911")
    }

    @Test func nearestERSearchesMaps() {
        let s = EmergencyContact.nearestERURL?.absoluteString ?? ""
        #expect(s.contains("maps.apple.com"))
        #expect(s.contains("emergency"))
    }
}
