import AppKit
import Foundation
import Testing
@testable import Techne

@MainActor
struct ApplicationRelaunchControllerTests {
    @Test
    func requestsOneTerminationAndConsumesTheRequestOnce() {
        var terminationCount = 0
        let controller = ApplicationRelaunchController {
            terminationCount += 1
        }

        #expect(controller.requestRelaunch())
        #expect(controller.requestRelaunch() == false)
        #expect(terminationCount == 1)
        #expect(controller.consumeRelaunchRequest())
        #expect(controller.consumeRelaunchRequest() == false)
    }

    @Test
    func ordinaryTerminationDoesNotOpenAnotherApplicationInstance() {
        var reopenCount = 0
        let controller = ApplicationRelaunchController(terminateApplication: { })
        let delegate = AppDelegate(
            relaunchController: controller,
            reopenApplication: { reopenCount += 1 }
        )

        delegate.applicationWillTerminate(Notification(name: NSApplication.willTerminateNotification))

        #expect(reopenCount == 0)
    }

    @Test
    func requestedRelaunchOpensOneReplacementApplicationInstance() {
        var reopenCount = 0
        let controller = ApplicationRelaunchController(terminateApplication: { })
        let delegate = AppDelegate(
            relaunchController: controller,
            reopenApplication: { reopenCount += 1 }
        )

        #expect(controller.requestRelaunch())
        delegate.applicationWillTerminate(Notification(name: NSApplication.willTerminateNotification))
        delegate.applicationWillTerminate(Notification(name: NSApplication.willTerminateNotification))

        #expect(reopenCount == 1)
    }
}
