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

    // Screen recording. `CGPreflightScreenCaptureAccess` never prompts.
    public static var screenRecordingGranted: Bool { CGPreflightScreenCaptureAccess() }

    /// Shows the system prompt the first time. The grant usually takes effect after an app restart.
    @discardableResult
    public static func requestScreenRecording() -> Bool { CGRequestScreenCaptureAccess() }

    public static func microphoneStatus() -> Status { mapAuthorization(AVCaptureDevice.authorizationStatus(for: .audio)) }
    public static func cameraStatus() -> Status { mapAuthorization(AVCaptureDevice.authorizationStatus(for: .video)) }

    public static func requestMicrophone() async -> Bool { await AVCaptureDevice.requestAccess(for: .audio) }
    public static func requestCamera() async -> Bool { await AVCaptureDevice.requestAccess(for: .video) }

    /// Ensures everything `options` needs is allowed, prompting for mic/camera if undecided.
    /// Throws `NSSError.permissionDenied` naming the first missing permission.
    static func ensure(for options: RecordingOptions) async throws {
        guard screenRecordingGranted else {
            throw NSSError.permissionDenied("Screen recording permission is required. Enable it in System Settings > Privacy & Security > Screen & System Audio Recording.")
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
