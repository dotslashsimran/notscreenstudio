import CoreGraphics
import Foundation
import Testing
import NSSCore
@testable import NSSUI

@MainActor
@Suite struct ShellModelTests {
    @Test func oneClickRecordUsesMainDisplayAndNoDevicesByDefault() async throws {
        let rig = ShellRig()
        defer { rig.cleanup() }
        await rig.model.startRecording()
        guard case .recording = rig.model.phase else { Issue.record("phase \(rig.model.phase)"); return }
        #expect(rig.session.startedOptions?.source == .display(id: 7))
        #expect(rig.session.startedOptions?.micDeviceID == nil)
        #expect(rig.session.startedOptions?.cameraDeviceID == nil)
        #expect(rig.logger.startedSource == .display(id: 7))
        #expect(rig.effects.hudShown)
        #expect(rig.effects.shortcutRegistered)
        #expect(!rig.effects.bubbleShown)
        let bundle = try #require(rig.session.startedBundle)
        #expect(bundle.pathExtension == "nssproj")
        #expect(FileManager.default.fileExists(atPath: bundle.path))
    }

    @Test func stateMachineRunsIdleRecordingSavingEditing() async throws {
        let rig = ShellRig()
        defer { rig.cleanup() }
        #expect(rig.model.phase == .idle)
        await rig.model.startRecording()
        #expect(rig.model.isRecording)
        await rig.model.stopRecording()
        guard case .editing(let ref) = rig.model.phase else { Issue.record("phase \(rig.model.phase)"); return }
        #expect(!rig.effects.hudShown)
        #expect(!rig.effects.shortcutRegistered)
        #expect(rig.model.editorRequestID == 1)
        // Saved through the ProjectStore, cursor rebased to the session's origin.
        #expect(rig.logger.stopOrigin == 42)
        let loaded = try await rig.store.load(ref)
        #expect(loaded.assets.duration == 3)
        #expect(loaded.style.camera.visible == false)
        let track = try await rig.store.loadCursorTrack(for: ref, assets: loaded.assets)
        #expect(track.samples.count == 1)
        #expect(rig.model.lastSaved?.project.id == loaded.id)
    }

    @Test func rememberedSourceAndDevicesAreUsed() async {
        let initial = ShellSettings(source: .window(id: 55), micEnabled: true, micDeviceID: "mic1", cameraEnabled: true, cameraDeviceID: "cam1")
        let rig = ShellRig(initial: initial)
        defer { rig.cleanup() }
        await rig.model.startRecording()
        #expect(rig.session.startedOptions == RecordingOptions(source: .window(id: 55), micDeviceID: "mic1", cameraDeviceID: "cam1"))
        #expect(rig.effects.bubbleShown)
    }

    @Test func goneWindowFallsBackToMainDisplay() async {
        let rig = ShellRig(initial: ShellSettings(source: .window(id: 999)))
        defer { rig.cleanup() }
        await rig.model.startRecording()
        #expect(rig.session.startedOptions?.source == .display(id: 7))
        #expect(rig.model.notice != nil)
    }

    @Test func missingScreenPermissionOpensOnboardingInsteadOfRecording() async {
        let rig = ShellRig(permissions: [.screenRecording: .denied, .camera: .granted, .microphone: .granted])
        defer { rig.cleanup() }
        await rig.model.startRecording()
        #expect(rig.model.phase == .idle)
        #expect(rig.model.onboardingRequestID == 1)
        #expect(rig.session.startedOptions == nil)
    }

    @Test func deniedMicAndCameraAreSkippedNotFatal() async {
        let rig = ShellRig(
            permissions: [.screenRecording: .granted, .camera: .denied, .microphone: .denied],
            initial: ShellSettings(micEnabled: true, cameraEnabled: true))
        defer { rig.cleanup() }
        await rig.model.startRecording()
        #expect(rig.model.isRecording)
        #expect(rig.session.startedOptions?.micDeviceID == nil)
        #expect(rig.session.startedOptions?.cameraDeviceID == nil)
        #expect(rig.model.notice?.contains("Microphone") == true)
        #expect(rig.model.notice?.contains("Camera") == true)
        #expect(!rig.effects.bubbleShown)
    }

    @Test func startFailureLeavesFailedPhaseAndNoEmptyBundle() async throws {
        let rig = ShellRig()
        defer { rig.cleanup() }
        rig.session.failStart = .io("disk full")
        await rig.model.startRecording()
        #expect(rig.model.phase == .failed("disk full"))
        let leftovers = (try? FileManager.default.contentsOfDirectory(atPath: rig.library.path)) ?? []
        #expect(leftovers.filter { $0.hasSuffix(".nssproj") }.isEmpty)
        #expect(!rig.effects.hudShown)
        rig.model.dismissError()
        #expect(rig.model.phase == .idle)
        #expect(rig.model.canStart)
    }

    @Test func permissionDeniedFromSessionOpensOnboarding() async {
        let rig = ShellRig()
        defer { rig.cleanup() }
        rig.session.failStart = .permissionDenied("Screen recording permission is required.")
        await rig.model.startRecording()
        #expect(rig.model.onboardingRequestID == 1)
    }

    @Test func discardDeletesTheBundleAndReturnsToIdle() async throws {
        let rig = ShellRig()
        defer { rig.cleanup() }
        await rig.model.startRecording()
        let bundle = try #require(rig.session.startedBundle)
        await rig.model.discardRecording()
        #expect(rig.model.phase == .idle)
        #expect(!FileManager.default.fileExists(atPath: bundle.path))
        #expect(!rig.effects.hudShown)
        #expect(rig.model.lastSaved == nil)
        #expect(rig.model.editorRequestID == 0)
    }

    @Test func secondStartWhileRecordingIsIgnored() async {
        let rig = ShellRig()
        defer { rig.cleanup() }
        await rig.model.startRecording()
        let first = rig.session.startedBundle
        await rig.model.startRecording()
        #expect(rig.session.startedBundle == first)
    }

    @Test func toggleStartsThenStops() async {
        let rig = ShellRig()
        defer { rig.cleanup() }
        await rig.model.toggleRecording()
        #expect(rig.model.isRecording)
        await rig.model.toggleRecording()
        if case .editing = rig.model.phase {} else { Issue.record("phase \(rig.model.phase)") }
    }

    @Test func bubbleGeometryIsSavedIntoProjectAndSettings() async throws {
        let rig = ShellRig(initial: ShellSettings(cameraEnabled: true, cameraShape: .squircle))
        defer { rig.cleanup() }
        await rig.model.startRecording()
        // The initial frame comes from the saved defaults, relative to the 1440x900 main display.
        let shown = try #require(rig.effects.shownBubbleFrame)
        #expect(abs(shown.width - 0.18 * 1440) < 1e-6)
        // The user drags and resizes the bubble.
        rig.effects.bubbleFrameValue = CGRect(x: 1000, y: 100, width: 288, height: 288)
        await rig.model.stopRecording()
        guard case .editing(let ref) = rig.model.phase else { Issue.record("phase \(rig.model.phase)"); return }
        let project = try await rig.store.load(ref)
        let cam = project.style.camera
        #expect(cam.visible)
        #expect(cam.shape == .squircle)
        #expect(abs(cam.position.x - 1144.0 / 1440) < 1e-9)
        #expect(abs(cam.position.y - (900.0 - 244.0) / 900) < 1e-9)
        #expect(abs(cam.size - 0.2) < 1e-9)
        #expect(abs(rig.model.settings.bubbleSize - 0.2) < 1e-9)
    }

    @Test func areaOnSecondDisplayPlacesBubbleOnThatDisplay() async throws {
        let rig = ShellRig(initial: ShellSettings(cameraEnabled: true))
        defer { rig.cleanup() }
        rig.effects.areaResult = AreaSelection(displayID: 8, rect: CGRect(x: 100, y: 100, width: 800, height: 600))
        await rig.model.chooseArea()
        #expect(rig.model.settings.source == .area(displayID: 8, rect: CGRect(x: 100, y: 100, width: 800, height: 600)))
        await rig.model.startRecording()
        let shown = try #require(rig.effects.shownBubbleFrame)
        // Area global rect is (1540,100,800,600) top-left, so AppKit x range is 1540...2340.
        #expect(shown.midX > 1540 && shown.midX < 2340)
    }

    @Test func cancelledAreaSelectionKeepsPreviousSource() async {
        let rig = ShellRig(initial: ShellSettings(source: .display(id: 8)))
        defer { rig.cleanup() }
        rig.effects.areaResult = nil
        await rig.model.chooseArea()
        #expect(rig.model.settings.source == .display(id: 8))
    }

    @Test func settingsPersistAcrossModels() async {
        let rig = ShellRig()
        defer { rig.cleanup() }
        rig.model.selectSource(.display(id: 8))
        rig.model.setMicEnabled(true)
        rig.model.selectMicrophone("mic1")
        rig.model.setCameraEnabled(true)
        rig.model.selectCamera("cam1")
        rig.model.selectShape(.rectangle)
        let reloaded = ShellSettingsStore(defaults: rig.defaults).load()
        #expect(reloaded == rig.model.settings)
        #expect(reloaded.source == .display(id: 8))
        #expect(reloaded.micEnabled && reloaded.cameraEnabled)
        #expect(reloaded.cameraShape == .rectangle)
    }

    @Test func launchRequestsOnboardingOnlyWhenScreenRecordingIsMissing() async {
        let denied = ShellRig(permissions: [.screenRecording: .notDetermined])
        defer { denied.cleanup() }
        await denied.model.launch()
        #expect(denied.model.onboardingRequestID == 1)
        let ok = ShellRig()
        defer { ok.cleanup() }
        await ok.model.launch()
        #expect(ok.model.onboardingRequestID == 0)
        #expect(ok.model.listing.displays.count == 2)
        #expect(ok.model.microphones.count == 1)
    }

    @Test func captureFailureWhileRecordingEndsInFailedPhase() async throws {
        let rig = ShellRig()
        defer { rig.cleanup() }
        await rig.model.startRecording()
        rig.session.set(.failed(message: "Window closed"))
        // The watcher runs on the main actor; give it a few turns.
        for _ in 0..<50 where rig.model.isRecording { try await Task.sleep(for: .milliseconds(20)) }
        #expect(rig.model.phase == .failed("Window closed"))
        #expect(!rig.effects.hudShown)
    }

    @Test func menuBarSymbolReflectsRecordingState() async {
        let rig = ShellRig()
        defer { rig.cleanup() }
        #expect(rig.model.menuBarSymbol == "record.circle")
        await rig.model.startRecording()
        #expect(rig.model.menuBarSymbol == "record.circle.fill")
    }
}
