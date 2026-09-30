import SwiftUI
import AVFoundation

struct CameraPreview: UIViewRepresentable {
    let previewLayer: AVCaptureVideoPreviewLayer

    func makeUIView(context: Context) -> PreviewHostView {
        let view = PreviewHostView()
        view.attach(previewLayer)
        return view
    }

    func updateUIView(_ uiView: PreviewHostView, context: Context) {
        uiView.attach(previewLayer)
    }
}

final class PreviewHostView: UIView {
    private weak var attachedLayer: AVCaptureVideoPreviewLayer?

    func attach(_ layer: AVCaptureVideoPreviewLayer) {
        if attachedLayer !== layer {
            attachedLayer?.removeFromSuperlayer()
            self.layer.addSublayer(layer)
            attachedLayer = layer
        }
        setNeedsLayout()
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        attachedLayer?.frame = bounds
    }
}
