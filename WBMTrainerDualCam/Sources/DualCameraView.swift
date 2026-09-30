import SwiftUI

struct DualCameraView: View {
    @ObservedObject var manager: DualCameraManager
    @Environment(\.verticalSizeClass) private var verticalSizeClass

    var body: some View {
        VStack(spacing: 6) {
            Group {
                if verticalSizeClass == .compact {
                    HStack(spacing: 8) {
                        card(.front)
                        card(.rear)
                    }
                } else {
                    VStack(spacing: 8) {
                        card(.front)
                        card(.rear)
                    }
                }
            }
            statusView
        }
        .padding(8)
    }

    private func card(_ source: CameraSource) -> some View {
        ZStack(alignment: .bottomLeading) {
            CameraPreview(
                previewLayer: source == .front
                    ? manager.frontPreviewLayer
                    : manager.rearPreviewLayer
            )
            .background(.black)
            .clipShape(RoundedRectangle(cornerRadius: 12))

            Text(source == .front ? "Front Camera" : "Rear Camera")
                .font(.caption.bold())
                .padding(6)
                .background(.thinMaterial, in: Capsule())
                .padding(8)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var statusView: some View {
        VStack(spacing: 2) {
            Text(statusText)
                .font(.caption.bold())
            Text("Frames — Front: \(manager.frontFrameCount)  Rear: \(manager.rearFrameCount)")
                .font(.caption2.monospacedDigit())
        }
        .padding(8)
        .frame(maxWidth: .infinity)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 8))
    }

    private var statusText: String {
        switch manager.state {
        case .idle: return "Idle"
        case .requestingPermission: return "Requesting camera permission"
        case .configuring: return "Configuring MultiCam"
        case .running: return "Dual camera running"
        case .blocked(let reason): return "BLOCKED: \(reason)"
        case .failed(let reason): return "FAIL: \(reason)"
        }
    }
}
