import ServiceManagement
import Testing

@testable import CueCore

@Suite struct LoginItemTests {
    @Test func mapsEveryServiceStatus() {
        #expect(LoginItemStatus(SMAppService.Status.notRegistered) == .notRegistered)
        #expect(LoginItemStatus(SMAppService.Status.enabled) == .enabled)
        #expect(LoginItemStatus(SMAppService.Status.requiresApproval) == .requiresApproval)
        #expect(LoginItemStatus(SMAppService.Status.notFound) == .notFound)
    }

    @Test func checkmarkIsOnOnlyWhenCueWillStartAtLogin() {
        #expect(LoginItemStatus.enabled.mark == .on)
        #expect(LoginItemStatus.requiresApproval.mark == .mixed)
        #expect(LoginItemStatus.notRegistered.mark == .off)
        #expect(LoginItemStatus.notFound.mark == .off)
    }

    @Test func choosingTheItemRegistersWhenOffAndRemovesWhenRegistered() {
        #expect(LoginItemStatus.notRegistered.registersOnToggle)
        #expect(LoginItemStatus.notFound.registersOnToggle)
        #expect(!LoginItemStatus.enabled.registersOnToggle)
        #expect(!LoginItemStatus.requiresApproval.registersOnToggle)
    }

    @Test func onlyRequiresApprovalPointsToSystemSettings() {
        #expect(LoginItemStatus.requiresApproval.needsApproval)
        #expect(!LoginItemStatus.enabled.needsApproval)
        #expect(!LoginItemStatus.notRegistered.needsApproval)
        #expect(!LoginItemStatus.notFound.needsApproval)
    }
}
