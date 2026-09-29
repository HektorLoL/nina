import XCTest
@testable import Nina

final class GuardianApprovalTests: XCTestCase {
    func testApprovalCannotBeSentWithoutTheDeclarationTheConsentAndARelationship() {
        var form = GuardianApprovalForm.forApproval(request(age: .minor(.twelveToFifteen)))
        XCTAssertEqual(form.band, .twelveToFifteen)
        XCTAssertFalse(form.canSubmit)
        XCTAssertNil(form.approval())

        form.relationship = .mae
        form.declaresGuardianship = true
        XCTAssertFalse(form.canSubmit)
        XCTAssertNil(form.approval())

        form.consentsToProfile = true
        form.declaresGuardianship = false
        XCTAssertFalse(form.canSubmit)

        form.declaresGuardianship = true
        form.relationship = nil
        XCTAssertFalse(form.canSubmit)

        form.relationship = .responsavelLegal
        let approval = form.approval()
        XCTAssertEqual(
            approval,
            GuardianApproval(
                relationship: .responsavelLegal,
                band: .twelveToFifteen,
                consentVersion: MinorConsentVersion.current,
                healthConsent: false,
                nicknames: []
            )
        )
    }

    func testTheHealthConsentIsOptionalAndNeverRequiredToApprove() {
        var form = completedForm(age: .minor(.under12))
        XCTAssertTrue(form.canSubmit)
        XCTAssertEqual(form.approval()?.healthConsent, false)

        form.healthConsent = true
        XCTAssertEqual(form.approval()?.healthConsent, true)
    }

    func testAGuardianMayChooseTheSameBandOrAYoungerOneButNeverAnOlderOne() {
        var form = completedForm(age: .minor(.twelveToFifteen))
        XCTAssertEqual(form.allowedBands, [.under12, .twelveToFifteen])

        form.band = .sixteenToSeventeen
        XCTAssertFalse(form.canSubmit)

        form.band = .under12
        XCTAssertTrue(form.canSubmit)
    }

    func testAnUnknownRequesterHasNoBandPreselectedAndMustBeGivenOne() {
        var form = completedForm(age: .unknown)
        form.band = nil
        XCTAssertEqual(form.allowedBands, MinorBand.allCases)
        XCTAssertFalse(form.canSubmit)

        form.band = .sixteenToSeventeen
        XCTAssertTrue(form.canSubmit)
    }

    func testNicknamesAreTrimmedDeduplicatedAndCapped() {
        let many = (1...12).map { "Apelido \($0)" }.joined(separator: ",")

        XCTAssertEqual(
            MinorSupervisionDefaults.normalizedNicknames(" Pedrinho, pê , PEDRINHO,,Pê"),
            ["Pedrinho", "pê"]
        )
        XCTAssertEqual(MinorSupervisionDefaults.normalizedNicknames(many).count, 8)
        XCTAssertTrue(
            MinorSupervisionDefaults.normalizedNicknames(String(repeating: "a", count: 41)).isEmpty
        )
    }

    func testAProfileDraftTakesItsKindFromTheBandAndNeedsAName() {
        var form = completedForm(age: .unknown)
        form.band = .under12

        XCTAssertNil(form.profileDraft(name: "   "))
        let draft = form.profileDraft(name: " Pedro ")
        XCTAssertEqual(draft?.name, "Pedro")
        XCTAssertEqual(draft?.band.householdRole, .child)
    }

    func testTheRequesterTagNamesTheAgeWithoutADate() {
        XCTAssertEqual(JoinRequesterAge.adult.tag, "Maior de idade")
        XCTAssertEqual(JoinRequesterAge.minor(.under12).tag, "Menor de idade · menos de 12")
        XCTAssertEqual(JoinRequesterAge.minor(.twelveToFifteen).tag, "Menor de idade · 12 a 15")
        XCTAssertEqual(JoinRequesterAge.minor(.sixteenToSeventeen).tag, "Menor de idade · 16 ou 17")
        XCTAssertEqual(JoinRequesterAge.unknown.tag, "Idade não informada")
        XCTAssertEqual(JoinRequesterAge(status: nil, band: nil), .unknown)
    }

    private func completedForm(age: JoinRequesterAge) -> GuardianApprovalForm {
        var form = GuardianApprovalForm.forApproval(request(age: age))
        form.relationship = .pai
        form.band = form.band ?? .under12
        form.declaresGuardianship = true
        form.consentsToProfile = true
        return form
    }

    private func request(age: JoinRequesterAge) -> FamilyJoinRequest {
        FamilyJoinRequest(
            id: UUID(),
            familyID: UUID(),
            familyName: "Casa",
            requesterUserID: UUID(),
            requesterName: "Bia",
            status: .pending,
            createdAt: .now,
            requesterAge: age
        )
    }
}
