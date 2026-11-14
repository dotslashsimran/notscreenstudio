import AppKit
import SwiftUI
import NSSCore

struct ExportSheet: View {
    @Bindable var export: ExportModel
    var close: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Export").font(.title2.bold())
            Form {
                Picker("Resolution", selection: $export.resolution) {
                    Text("1080p").tag(ExportResolution.p1080)
                    Text("4K").tag(ExportResolution.p2160)
                }.pickerStyle(.segmented)
                Picker("Codec", selection: $export.codec) {
                    Text("H.264").tag(VideoCodec.h264)
                    Text("HEVC").tag(VideoCodec.hevc)
                }.pickerStyle(.segmented)
                LabeledContent("Format", value: export.outputDescription)
                LabeledContent("Save to") {
                    HStack {
                        Text(export.outputURL.path).lineLimit(1).truncationMode(.middle).foregroundStyle(.secondary)
                        Button("Choose…") { choose() }
                    }
                }
            }
            .disabled(export.isRunning)

            status

            HStack {
                Spacer()
                if export.isRunning {
                    Button("Cancel Export") { export.cancel() }
                } else if export.finishedURL != nil {
                    Button("Reveal in Finder") { export.revealInFinder() }
                    Button("Done") { close() }.keyboardShortcut(.defaultAction)
                } else {
                    Button("Close") { close() }.keyboardShortcut(.cancelAction)
                    Button("Export") { export.start() }.keyboardShortcut(.defaultAction)
                }
            }
        }
        .padding(20)
        .frame(width: 460)
    }

    @ViewBuilder private var status: some View {
        switch export.progress {
        case .running(let f, let written, let total):
            VStack(alignment: .leading) {
                ProgressView(value: f)
                Text(total > 0 ? "\(written) / \(total) frames" : "Starting…").font(.caption).foregroundStyle(.secondary)
            }
        case .finished: Label("Export finished", systemImage: "checkmark.circle.fill").foregroundStyle(.green)
        case .failed(let m): Label(m, systemImage: "exclamationmark.triangle.fill").foregroundStyle(.red)
        case .cancelled: Label("Export cancelled", systemImage: "xmark.circle").foregroundStyle(.secondary)
        case .idle: EmptyView()
        }
    }

    private func choose() {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.mpeg4Movie]
        panel.nameFieldStringValue = export.outputURL.lastPathComponent
        panel.directoryURL = export.outputURL.deletingLastPathComponent()
        if panel.runModal() == .OK, let url = panel.url {
            export.outputURL = url
            export.reset()
        }
    }
}
