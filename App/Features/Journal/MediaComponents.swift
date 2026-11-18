import AVKit
import PencilKit
import PickupCore
import SwiftUI
import UIKit

public struct MediaAttachmentStrip: View {
    let store: AppStore
    let attachments: [MediaAttachment]
    let onTap: (MediaAttachment) -> Void
    var onRemove: ((MediaAttachment) -> Void)? = nil

    public var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 10) {
                ForEach(attachments) { att in
                    MediaThumbnailTile(store: store, attachment: att, onTap: { onTap(att) }, onRemove: onRemove.map { cb in { cb(att) } })
                }
            }
        }
    }
}

private struct MediaThumbnailTile: View {
    let store: AppStore
    let attachment: MediaAttachment
    let onTap: () -> Void
    let onRemove: (() -> Void)?

    @State private var uiImage: UIImage? = nil

    var body: some View {
        let p = store.palette
        ZStack(alignment: .topTrailing) {
            Button(action: onTap) {
                ZStack(alignment: .bottomLeading) {
                    if let uiImage {
                        Image(uiImage: uiImage)
                            .resizable()
                            .scaledToFill()
                            .frame(width: 132, height: 102)
                            .clipped()
                    } else {
                        Rectangle()
                            .fill(p.elevatedSurface)
                            .frame(width: 132, height: 102)
                            .overlay {
                                Image(systemName: attachment.type == .video ? "video.fill" : "photo")
                                    .foregroundStyle(p.secondaryText)
                            }
                    }

                    // Badge
                    HStack(spacing: 4) {
                        if attachment.type == .motionPhoto {
                            Image(systemName: "livephoto")
                            Text("LIVE")
                        } else if attachment.type == .video {
                            Image(systemName: "play.fill")
                            Text("VIDEO")
                        } else if attachment.type == .sketch {
                            Image(systemName: "scribble.variable")
                            Text("INK")
                        }
                    }
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 3)
                    .background(.black.opacity(0.62), in: Capsule())
                    .padding(6)
                }
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(p.hairline))
            }

            if let onRemove {
                Button(action: onRemove) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 20))
                        .foregroundStyle(.white, .black.opacity(0.75))
                }
                .padding(5)
            }
        }
        .task(id: attachment.mediaId) {
            if let data = await store.loadMediaData(mediaId: attachment.mediaId),
               let img = UIImage(data: data) {
                uiImage = img
            }
        }
    }
}

public struct MediaViewerSheet: View {
    let store: AppStore
    let attachments: [MediaAttachment]
    let initialAttachment: MediaAttachment

    @Environment(\.dismiss) private var dismiss
    @State private var selectedId: String = ""
    @State private var loadedImage: UIImage? = nil
    @State private var player: AVPlayer? = nil
    @State private var scale: CGFloat = 1

    public var body: some View {
        let current = attachments.first(where: { $0.id == selectedId }) ?? initialAttachment
        ZStack(alignment: .topTrailing) {
            Color.black.ignoresSafeArea()

            VStack {
                Spacer()
                if current.type == .video || (current.type == .motionPhoto && player != nil) {
                    if let player {
                        VideoPlayer(player: player)
                            .frame(maxWidth: .infinity, maxHeight: 540)
                    }
                } else if let loadedImage {
                    Image(uiImage: loadedImage)
                        .resizable()
                        .scaledToFit()
                        .scaleEffect(scale)
                        .gesture(
                            MagnificationGesture()
                                .onChanged { value in scale = max(1, min(4, value)) }
                                .onEnded { _ in withAnimation(.spring()) { scale = 1 } }
                        )
                } else {
                    ProgressView().tint(.white)
                }
                Spacer()
            }

            Button {
                player?.pause()
                dismiss()
            } label: {
                Image(systemName: "xmark")
                    .font(.headline)
                    .foregroundStyle(.white)
                    .frame(width: 40, height: 40)
                    .pickupGlassCircle()
            }
            .padding(20)
        }
        .onAppear {
            selectedId = initialAttachment.id
        }
        .task(id: selectedId) {
            loadedImage = nil
            player?.pause()
            player = nil
            let att = attachments.first(where: { $0.id == selectedId }) ?? initialAttachment
            if att.type == .video {
                let url = await store.repository.mediaFileURL(for: att.mediaId)
                player = AVPlayer(url: url)
                player?.play()
            } else if let data = await store.loadMediaData(mediaId: att.mediaId) {
                loadedImage = UIImage(data: data)
            }
        }
    }
}

public struct PencilSketchSheet: View {
    let palette: PickupPalette
    let isZh: Bool
    let onSave: (Data) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var canvasView = PKCanvasView()
    @State private var inkColor: Color? = nil

    private var selectedInkColor: Color {
        inkColor ?? palette.primaryText
    }

    private var inkSwatches: [Color] {
        [palette.primaryText, palette.highlight, palette.secondaryText, palette.redPen]
    }

    public var body: some View {
        NavigationStack {
            ZStack {
                palette.background.ignoresSafeArea()
                VStack(spacing: 12) {
                    HStack(spacing: 14) {
                        ForEach(inkSwatches, id: \.self) { c in
                            Button {
                                inkColor = c
                                updateTool()
                            } label: {
                                Circle()
                                    .fill(c)
                                    .frame(width: 28, height: 28)
                                    .overlay(
                                        Circle()
                                            .strokeBorder(palette.background, lineWidth: selectedInkColor == c ? 3 : 0)
                                    )
                                    .overlay(
                                        Circle()
                                            .strokeBorder(palette.primaryText, lineWidth: selectedInkColor == c ? 1.5 : 0.6)
                                    )
                            }
                        }
                        Spacer()
                        Button(isZh ? "清空" : "Clear") {
                            canvasView.drawing = PKDrawing()
                        }
                        .font(.subheadline)
                        .foregroundStyle(palette.secondaryText)
                    }
                    .padding(.horizontal, 18)

                    PencilCanvasRepresentable(canvasView: $canvasView, inkColor: UIColor(selectedInkColor), backgroundColor: UIColor(palette.cardSurface))
                        .clipShape(RoundedRectangle(cornerRadius: 22))
                        .overlay(RoundedRectangle(cornerRadius: 22).strokeBorder(palette.hairline))
                        .padding(.horizontal, 16)
                        .padding(.bottom, 16)
                }
            }
            .navigationTitle(isZh ? "手绘瞬间" : "Quick Sketch")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(isZh ? "取消" : "Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(isZh ? "插入日记" : "Attach") {
                        let bounds = canvasView.bounds.isEmpty ? CGRect(x: 0, y: 0, width: 640, height: 480) : canvasView.bounds
                        let img = canvasView.drawing.image(from: bounds, scale: 2.0)
                        if let png = img.pngData() {
                            onSave(png)
                        }
                        dismiss()
                    }
                    .fontWeight(.bold)
                }
            }
        }
        .onAppear { updateTool() }
    }

    private func updateTool() {
        canvasView.tool = PKInkingTool(.pen, color: UIColor(selectedInkColor), width: 4.5)
    }
}

private struct PencilCanvasRepresentable: UIViewRepresentable {
    @Binding var canvasView: PKCanvasView
    let inkColor: UIColor
    let backgroundColor: UIColor

    func makeUIView(context: Context) -> PKCanvasView {
        canvasView.backgroundColor = backgroundColor
        canvasView.drawingPolicy = .anyInput
        canvasView.isOpaque = true
        canvasView.tool = PKInkingTool(.pen, color: inkColor, width: 4.5)
        return canvasView
    }

    func updateUIView(_ uiView: PKCanvasView, context: Context) {
        uiView.backgroundColor = backgroundColor
    }
}
