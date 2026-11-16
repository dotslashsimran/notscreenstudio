import AVFoundation
import CoreGraphics
import Foundation
import NSSCore

/// Check and request the three capture permissions.
public enum CapturePermissions {
    public enum Status: Sendable, Equatable {
        case granted, denied, notDetermined
    }

    public static func mapAuthorization(_ s: AVAuthorizationStatus) -> Status {
        switch s {
        case .authorized: return .granted
        case .notDetermined: return .notDetermined
        case .denied, .restricted: return .denied
        @unknown default: return .denied
        }
    }

    // Screen recording. Never prompts. This is only a fast hint: `CGPreflightScreenCaptureAccess`, or the last
    // successful `checkScreenRecording()`. Use `checkScreenRecording()` (SCShareableContent) for a real answer.
    public static var screenRecordingGranted: Bool {
        CGPreflightScreenCaptureAccess() || ScreenRecordingCache.lastGranted == true
    }

    /// Shows the system prompt the first time. The grant usually takes effect after an app restart.
    @discardableResult
    public static func requestScreenRecording() -> Bool {
        screenRecordingAsked = true
        return CGRequestScreenCaptureAccess()
    }

    static let askedKey = "notscreenstudio.shell.askedScreenRecording"
    /// True once the app has asked for Screen Recording. The system gives no "not asked yet" answer, so we remember it.
    public static var screenRecordingAsked: Bool {
        get { UserDefaults.standard.bool(forKey: askedKey) }
        set { UserDefaults.standard.set(newValue, forKey: askedKey) }
    }

    public static func microphoneStatus() -> Status { mapAuthorization(AVCaptureDevice.authorizationStatus(for: .audio)) }
    public static func cameraStatus() -> Status { mapAuthorization(AVCaptureDevice.authorizationStatus(for: .video)) }

    public static func requestMicrophone() async -> Bool { await AVCaptureDevice.requestAccess(for: .audio) }
    public static func requestCamera() async -> Bool { await AVCaptureDevice.requestAccess(for: .video) }

    /// Ensures everything `options` needs is allowed, prompting for mic/camera if undecided.
    /// Throws `NSSError.permissionDenied` naming the first missing permission.
    static func ensure(for options: RecordingOptions) async throws {
        let access = await checkScreenRecording()
        guard access.isGranted else {
            throw NSSError.permissionDenied(access.message ?? ScreenRecordingAccess.settingsHint)
        }
        if options.micDeviceID != nil {
            let ok = microphoneStatus() == .granted ? true : (microphoneStatus() == .notDetermined ? await requestMicrophone() : false)
            if !ok { throw NSSError.permissionDenied("Microphone permission is required. Enable it in System Settings > Privacy & Security > Microphone.") }
        }
        if options.cameraDeviceID != nil {
            let ok = cameraStatus() == .granted ? true : (cameraStatus() == .notDetermined ? await requestCamera() : false)
            if !ok { throw NSSError.permissionDenied("Camera permission is required. Enable it in System Settings > Privacy & Security > Camera.") }
        }
    }
}
