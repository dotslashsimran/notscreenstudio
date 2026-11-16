import CoreGraphics
import Foundation
import os
import Security

/// Decides when the app may call anything that can raise the macOS Screen Recording prompt.
///
/// On macOS 15 every `SCShareableContent` call by an app that is not approved shows the system prompt again, so
/// the rules are strict:
/// - A probe runs only when `CGPreflightScreenCaptureAccess` is true, or the user clicked Allow / Check again in
///   this process. The persisted "asked" flag never allows a probe by itself.
/// - Automatic probes (launch, app activation) run at most once per activation generation.
/// - `CGRequestScreenCaptureAccess` runs at most once, and only from an explicit user action.
/// - The persisted "asked" flag is tied to the app's signing identity and counts as false when it changes.
public final class ScreenRecordingGate: @unchecked Sendable {
    public enum Trigger: Sendable, Equatable {
        /// Launch or app activation. Rate limited and never prompts on its own.
        case automatic
        /// The user clicked Allow or Check Again.
        case user
    }

    private struct State {
        var userEngaged = false
        var activation = 0
        var lastAutomaticActivation = -1
    }

    private let preflight: @Sendable () -> Bool
    private let identity: @Sendable () -> String?
    private let loadAskedIdentity: @Sendable () -> String?
    private let saveAskedIdentity: @Sendable (String?) -> Void
    private let request: @Sendable () -> Bool
    private let state = OSAllocatedUnfairLock(initialState: State())

    public init(
        preflight: @escaping @Sendable () -> Bool,
        identity: @escaping @Sendable () -> String?,
        loadAskedIdentity: @escaping @Sendable () -> String?,
        saveAskedIdentity: @escaping @Sendable (String?) -> Void,
        request: @escaping @Sendable () -> Bool
    ) {
        self.preflight = preflight
        self.identity = identity
        self.loadAskedIdentity = loadAskedIdentity
        self.saveAskedIdentity = saveAskedIdentity
        self.request = request
    }

    /// True once this signing identity has asked for Screen Recording. False after a rebuild with a new identity.
    public var asked: Bool {
        guard let current = identity(), let stored = loadAskedIdentity() else { return false }
        return stored == current
    }

    /// Marks the start of a new app activation, which allows one more automatic probe.
    public func noteActivation() { state.withLock { $0.activation += 1 } }

    /// True if the user clicked Allow or Check Again in this process.
    public var userEngaged: Bool { state.withLock { $0.userEngaged } }

    /// May a call that can prompt (SCShareableContent) run now? Consumes the automatic allowance when it says yes.
    public func authorizeProbe(_ trigger: Trigger) -> Bool {
        if trigger == .user {
            state.withLock { $0.userEngaged = true }
            return true
        }
        guard preflight() || userEngaged else { return false }
        return state.withLock { s in
            guard s.lastAutomaticActivation != s.activation else { return false }
            s.lastAutomaticActivation = s.activation
            return true
        }
    }

    /// Can something that may prompt (the source list) run? Never because of the persisted flag alone.
    public var mayTouchScreenCaptureKit: Bool { preflight() || userEngaged }

    /// The explicit Allow action. Calls `CGRequestScreenCaptureAccess` once per identity and returns whether it
    /// was called. Never call this from anything but a user click.
    @discardableResult
    public func requestFromUserAction() -> Bool {
        state.withLock { $0.userEngaged = true }
        guard !asked else { return false }
        markAsked()
        _ = request()
        return true
    }

    public func markAsked() { saveAskedIdentity(identity()) }
}

extension ScreenRecordingGate {
    static let askedIdentityKey = "notscreenstudio.shell.askedScreenRecordingIdentity"

    /// The gate used by the app: real preflight, real request, UserDefaults, and this process's signature.
    static let system = ScreenRecordingGate(
        preflight: { CGPreflightScreenCaptureAccess() },
        identity: { SigningIdentity.current },
        loadAskedIdentity: { UserDefaults.standard.string(forKey: askedIdentityKey) },
        saveAskedIdentity: { UserDefaults.standard.set($0, forKey: askedIdentityKey) },
        request: { CGRequestScreenCaptureAccess() })
}

/// A string that changes when the app's signature changes (and so when macOS stops matching its permission).
enum SigningIdentity {
    /// The designated requirement of this process: certificate leaf hash for a stable identity, cdhash for ad hoc.
    static let current: String? = read()

    private static func read() -> String? {
        var code: SecCode?
        guard SecCodeCopySelf([], &code) == errSecSuccess, let code else { return nil }
        var staticCode: SecStaticCode?
        guard SecCodeCopyStaticCode(code, [], &staticCode) == errSecSuccess, let staticCode else { return nil }
        var requirement: SecRequirement?
        if SecCodeCopyDesignatedRequirement(staticCode, [], &requirement) == errSecSuccess, let requirement {
            var text: CFString?
            if SecRequirementCopyString(requirement, [], &text) == errSecSuccess, let text { return text as String }
        }
        var info: CFDictionary?
        guard SecCodeCopySigningInformation(staticCode, SecCSFlags(rawValue: kSecCSSigningInformation), &info) == errSecSuccess,
              let dict = info as? [String: Any], let hash = dict[kSecCodeInfoUnique as String] as? Data else { return nil }
        return "cdhash " + hash.map { String(format: "%02x", $0) }.joined()
    }
}
