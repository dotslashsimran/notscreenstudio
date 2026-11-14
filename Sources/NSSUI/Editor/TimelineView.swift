import SwiftUI
import NSSCore

/// Timeline: ruler, thumbnail strip with trim handles, click markers, zoom track and playhead.
struct EditorTimelineView: View {
    let model: EditorModel
    let thumbnails: ThumbnailStore
    let seek: (MediaTime) -> Void

    @State private var blockDragBase: [ZoomBlock]?
    private let space = "timelineTrack"
    private let rulerH: CGFloat = 22
    private let stripH: CGFloat = 48
    private let markerH: CGFloat = 14
    private let zoomH: CGFloat = 36

    var body: some View {
        GeometryReader { geo in
            let g = TimelineGeometry(duration: model.duration, width: geo.size.width)
            ZStack(alignment: .topLeading) {
                VStack(spacing: 0) {
                    ruler(g).frame(height: rulerH)
                    strip(g).frame(height: stripH)
                    clickMarkers(g).frame(height: markerH)
                    zoomTrack(g).frame(height: zoomH)
                }
                playhead(g)
            }
            .coordinateSpace(name: space)
            .contentShape(Rectangle())
        }
        .frame(height: rulerH + stripH + markerH + zoomH + 8)
        .focusable()
        .onKeyPress(.delete) { deleteSelected() }
        .onKeyPress(.deleteForward) { deleteSelected() }
    }

    private func deleteSelected() -> KeyPress.Result {
        guard let id = model.selectedZoomID else { return .ignored }
        model.deleteZoomBlock(id)
        return .handled
    }

    // MARK: Ruler

    private func ruler(_ g: TimelineGeometry) -> some View {
        Canvas { ctx, size in
            let step = g.tickInterval()
            var t: MediaTime = 0
            while t <= g.duration {
                let x = g.x(for: t)
                var p = Path()
                p.move(to: CGPoint(x: x, y: size.height - 7))
                p.addLine(to: CGPoint(x: x, y: size.height))
                ctx.stroke(p, with: .color(.secondary), lineWidth: 1)
                ctx.draw(Text(TimelineGeometry.label(for: t)).font(.system(size: 9).monospacedDigit()).foregroundStyle(.secondary),
                         at: CGPoint(x: x + 3, y: 8), anchor: .leading)
                t += step
            }
        }
        .contentShape(Rectangle())
                .gesture(scrubGesture(g))
    }

    /// Click or drag on the ruler or strip: seeks at once and the drawn playhead follows the mouse exactly.
    private func scrubGesture(_ g: TimelineGeometry) -> some Gesture {
        DragGesture(minimumDistance: 0, coordinateSpace: .named(space))
            .onChanged {
                model.isScrubbing = true
                seek(g.time(forX: $0.location.x))
            }
            .onEnded { _ in model.isScrubbing = false }
    }

    // MARK: Thumbnails + trim

    private func strip(_ g: TimelineGeometry) -> some View {
        ZStack(alignment: .leading) {
            Color.black.opacity(0.35)
            ForEach(thumbnails.thumbs) { th in
                let w = g.width / 24
                Image(decorative: th.image, scale: 1)
                    .resizable().aspectRatio(contentMode: .fill)
                    .frame(width: w, height: stripH).clipped()
                    .offset(x: g.x(for: th.time) - w / 2)
            }
            // Dim trimmed-away regions.
            let sx = g.x(for: model.trimStart), ex = g.x(for: model.trimEnd)
            Rectangle().fill(.black.opacity(0.6)).frame(width: max(sx, 0)).frame(maxWidth: .infinity, alignment: .leading)
            Rectangle().fill(.black.opacity(0.6)).frame(width: max(g.width - ex, 0)).frame(maxWidth: .infinity, alignment: .trailing)
            Rectangle().strokeBorder(Color.yellow, lineWidth: 2)
                .frame(width: max(ex - sx, 0)).offset(x: sx).allowsHitTesting(false)
            trimHandle(x: sx, isStart: true, g: g)
            trimHandle(x: ex, isStart: false, g: g)
        }
        .clipShape(RoundedRectangle(cornerRadius: 4))
        .contentShape(Rectangle())
                .gesture(scrubGesture(g))
    }

    private func trimHandle(x: Double, isStart: Bool, g: TimelineGeometry) -> some View {
        RoundedRectangle(cornerRadius: 2).fill(Color.yellow)
            .frame(width: 8, height: stripH)
            .offset(x: x - (isStart ? 8 : 0))
            .gesture(
                DragGesture(minimumDistance: 0, coordinateSpace: .named(space))
                    .onChanged { v in
                        model.beginGesture("Trim")
                        let t = g.time(forX: v.location.x)
                        if isStart { model.setTrimStart(t) } else { model.setTrimEnd(t) }
                    }
                    .onEnded { _ in model.endGesture() }
            )
            .help(isStart ? "Trim start" : "Trim end")
    }

    // MARK: Click markers

    private func clickMarkers(_ g: TimelineGeometry) -> some View {
        Canvas { ctx, size in
            for c in model.track.clicks where c.kind == .down && c.t <= g.duration {
                let x = g.x(for: c.t)
                ctx.fill(Path(ellipseIn: CGRect(x: x - 2.5, y: size.height / 2 - 2.5, width: 5, height: 5)), with: .color(.orange))
            }
        }
        .allowsHitTesting(false)
    }

    // MARK: Zoom track

    private func zoomTrack(_ g: TimelineGeometry) -> some View {
        ZStack(alignment: .topLeading) {
            RoundedRectangle(cornerRadius: 4).fill(Color.primary.opacity(0.06))
                .onTapGesture(count: 2, coordinateSpace: .named(space)) { loc in
                    model.addZoomBlock(at: g.time(forX: loc.x))
                }
                .onTapGesture { model.selectedZoomID = nil }
            ForEach(model.project.timeline.zoomBlocks) { block in
                zoomBlockView(block, g: g)
            }
        }
        .overlay(alignment: .leading) {
            if model.project.timeline.zoomBlocks.isEmpty {
                Text("Double-click to add a zoom").font(.caption2).foregroundStyle(.tertiary).padding(.leading, 8).allowsHitTesting(false)
            }
        }
    }

    private func zoomBlockView(_ block: ZoomBlock, g: TimelineGeometry) -> some View {
        let x = g.x(for: block.start)
        let w = max(g.x(for: block.end) - x, 4)
        let selected = block.id == model.selectedZoomID
        return ZStack {
            RoundedRectangle(cornerRadius: 5)
                .fill(Color.accentColor.opacity(selected ? 0.85 : 0.55))
                .overlay(RoundedRectangle(cornerRadius: 5).strokeBorder(selected ? Color.white : .clear, lineWidth: 1.5))
            Text(String(format: "%.1f×", block.scale) + (block.focus == .auto ? "" : " ⌖"))
                .font(.caption2.weight(.semibold)).foregroundStyle(.white).lineLimit(1)
        }
        .frame(width: w, height: zoomH - 6)
        .overlay(alignment: .leading) { edgeHandle(block, edge: .start, g: g) }
        .overlay(alignment: .trailing) { edgeHandle(block, edge: .end, g: g) }
        .offset(x: x, y: 3)
        .onTapGesture { model.selectedZoomID = block.id }
        .gesture(
            DragGesture(minimumDistance: 3, coordinateSpace: .named(space))
                .onChanged { v in
                    if blockDragBase == nil {
                        blockDragBase = model.project.timeline.zoomBlocks
                        model.selectedZoomID = block.id
                        model.beginGesture("Move Zoom")
                    }
                    model.moveZoomBlock(block.id, by: v.translation.width / g.pixelsPerSecond, from: blockDragBase ?? [])
                }
                .onEnded { _ in
                    blockDragBase = nil
                    model.endGesture()
                }
        )
    }

    private func edgeHandle(_ block: ZoomBlock, edge: ZoomBlockEditing.Edge, g: TimelineGeometry) -> some View {
        Rectangle().fill(Color.white.opacity(0.001)).frame(width: 8)
            .overlay(Capsule().fill(.white.opacity(0.8)).frame(width: 2, height: 14))
            .gesture(
                DragGesture(minimumDistance: 0, coordinateSpace: .named(space))
                    .onChanged { v in
                        if blockDragBase == nil {
                            blockDragBase = model.project.timeline.zoomBlocks
                            model.selectedZoomID = block.id
                            model.beginGesture("Resize Zoom")
                        }
                        model.resizeZoomBlock(block.id, edge: edge, to: g.time(forX: v.location.x), from: blockDragBase ?? [])
                    }
                    .onEnded { _ in
                        blockDragBase = nil
                        model.endGesture()
                    }
            )
    }

    // MARK: Playhead

    private func playhead(_ g: TimelineGeometry) -> some View {
        let x = g.x(for: model.displayPlayhead)
        return ZStack(alignment: .top) {
            Rectangle().fill(Color.red).frame(width: 1.5)
            Image(systemName: "arrowtriangle.down.fill").font(.system(size: 9)).foregroundStyle(.red).offset(y: -1)
        }
        .frame(width: 12)
        .offset(x: x - 6)
        .allowsHitTesting(false)
    }
}
