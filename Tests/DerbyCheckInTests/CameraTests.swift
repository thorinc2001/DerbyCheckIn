import Foundation
import Testing
@testable import DerbyCheckIn

/// Smoke tests for the camera's background queue. A closure that wrongly inherits the main
/// actor only crashes when it actually runs off the main thread, so run those paths once.
@MainActor
@Suite("Camera")
struct CameraTests {
    @Test func missingCameraReportsAnErrorFromTheCameraQueue() async {
        let engine = CaptureEngine()
        let message = await withCheckedContinuation { (done: CheckedContinuation<String, Never>) in
            engine.use(deviceID: "no-such-camera") { @Sendable message in done.resume(returning: message) }
        }
        #expect(message == "That camera is no longer connected.")
        engine.stop()
    }

    @Test func modelShowsTheErrorOnTheMainActor() async throws {
        let model = CameraModel()
        model.select("no-such-camera")
        for _ in 0..<50 where model.error == nil { try await Task.sleep(for: .milliseconds(20)) }
        #expect(model.error == "That camera is no longer connected.")
        #expect(model.deviceID == "no-such-camera")
        model.stop()
    }
}
