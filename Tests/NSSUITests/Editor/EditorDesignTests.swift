import Testing
@testable import NSSUI

@Suite struct EditorDesignTests {
    @Test func inspectorSectionsAreInTheSpecifiedOrder() {
        #expect(InspectorSectionID.allCases.map(\.title) == ["Background", "Frame", "Cursor", "Zoom", "Camera", "Audio"])
    }

    @Test func timelineTracksAreInTheSpecifiedOrder() {
        #expect(TimelineTrackKind.allCases.map(\.title) == ["Video", "Zoom", "Camera", "Audio"])
    }

    @Test func hitZonesOnAWideBlock() {
        #expect(TrackBlockStyle.hitZone(atX: 0, blockWidth: 100) == .startEdge)
        #expect(TrackBlockStyle.hitZone(atX: 7.9, blockWidth: 100) == .startEdge)
        #expect(TrackBlockStyle.hitZone(atX: 50, blockWidth: 100) == .body)
        #expect(TrackBlockStyle.hitZone(atX: 92.1, blockWidth: 100) == .endEdge)
        #expect(TrackBlockStyle.hitZone(atX: 100, blockWidth: 100) == .endEdge)
    }

    @Test func narrowBlockKeepsAGrabbableBody() {
        // 12 pt wide: edges shrink to a third (4 pt) so the middle 4 pt stays the body.
        #expect(TrackBlockStyle.hitZone(atX: 1, blockWidth: 12) == .startEdge)
        #expect(TrackBlockStyle.hitZone(atX: 6, blockWidth: 12) == .body)
        #expect(TrackBlockStyle.hitZone(atX: 11, blockWidth: 12) == .endEdge)
    }

    @Test func displayWidthHasAMinimum() {
        #expect(TrackBlockStyle.displayWidth(0) == Double(TrackBlockStyle.minimumWidth))
        #expect(TrackBlockStyle.displayWidth(200) == 200)
    }

    @Test func formattersMatchTheOldInspector() {
        #expect(InspectorFormat.percent(0.5) == "50%")
        #expect(InspectorFormat.multiplier(2) == "2.0×")
        #expect(InspectorFormat.degrees(45) == "45°")
    }
}
