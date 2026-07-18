import Testing
@testable import Food_Intolerances

struct CrisisContactTests {
    @Test func callAndTextUseThe988Constant() {
        #expect(CrisisContact.crisisNumber == "988")
        #expect(CrisisContact.call988URL?.absoluteString == "tel:988")
        #expect(CrisisContact.text988URL?.absoluteString == "sms:988")
    }
}
