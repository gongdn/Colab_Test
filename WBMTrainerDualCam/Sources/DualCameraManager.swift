import Foundation
import AVFoundation
import Combine

enum CameraSource {
    case front
    case rear
}

final class DualCameraManager: NSObject, ObservableObject {
    enum State: Equatable {
        case idle
        case requestingPermission
        case configuring
        case running
        case blocked(String)
        case failed(String)
    }

    @Published private(set) var state: State = .idle
    @Published private(set) var frontFrameCount: UInt64 = 0
    @Published private(set) var rearFrameCount: UInt64 = 0

    let session = AVCaptureMultiCamSession()
    let frontPreviewLayer = AVCaptureVideoPreviewLayer()
    let rearPreviewLayer = AVCaptureVideoPreviewLayer()

    private let frontOutput = AVCaptureVideoDataOutput()
    private let rearOutput = AVCaptureVideoDataOutput()
    private let frontQueue = DispatchQueue(label: "wbm.camera.front.frames", qos: .userInteractive)
    private let rearQueue = DispatchQueue(label: "wbm.camera.rear.frames", qos: .userInteractive)
    private let configurationQueue = DispatchQueue(label: "wbm.camera.multicam.configuration")

    override init() {
        super.init()
        frontOutput.setSampleBufferDelegate(self, queue: frontQueue)
        rearOutput.setSampleBufferDelegate(self, queue: rearQueue)
        frontOutput.alwaysDiscardsLateVideoFrames = true
        rearOutput.alwaysDiscardsLateVideoFrames = true
    }

    func start() {
        guard AVCaptureMultiCamSession.isMultiCamSupported else {
            publish(.blocked("AVCaptureMultiCamSession unsupported on this iPhone"))
            return
        }

        publish(.requestingPermission)
        Task {
            let granted = await Self.requestVideoPermission()
            guard granted else {
                publish(.blocked("Camera permission denied"))
                return
            }
            publish(.configuring)
            configurationQueue.async { [weak self] in self?.configureAndStart() }
        }
    }

    func stop() {
        configurationQueue.async { [weak self] in
            guard let self else { return }
            if self.session.isRunning { self.session.stopRunning() }
            self.publish(.idle)
        }
    }

    private func publish(_ next: State) {
        DispatchQueue.main.async { [weak self] in self?.state = next }
    }

    private static func requestVideoPermission() async -> Bool {
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized: return true
        case .notDetermined: return await AVCaptureDevice.requestAccess(for: .video)
        default: return false
        }
    }

    private func configureAndStart() {
        do {
            session.beginConfiguration()
            defer { session.commitConfiguration() }

            guard let front = Self.camera(position: .front),
                  let rear = Self.camera(position: .back) else {
                throw CameraError.missingCamera
            }

            let frontInput = try AVCaptureDeviceInput(device: front)
            let rearInput = try AVCaptureDeviceInput(device: rear)

            guard session.canAddInput(frontInput), session.canAddInput(rearInput) else {
                throw CameraError.cannotAddInputs
            }
            session.addInputWithNoConnections(frontInput)
            session.addInputWithNoConnections(rearInput)

            guard session.canAddOutput(frontOutput), session.canAddOutput(rearOutput) else {
                throw CameraError.cannotAddOutputs
            }
            session.addOutputWithNoConnections(frontOutput)
            session.addOutputWithNoConnections(rearOutput)

            guard let frontPort = frontInput.ports.first(where: { $0.mediaType == .video }),
                  let rearPort = rearInput.ports.first(where: { $0.mediaType == .video }) else {
                throw CameraError.missingVideoPort
            }

            let frontDataConnection = AVCaptureConnection(inputPorts: [frontPort], output: frontOutput)
            let rearDataConnection = AVCaptureConnection(inputPorts: [rearPort], output: rearOutput)
            guard session.canAddConnection(frontDataConnection),
                  session.canAddConnection(rearDataConnection) else {
                throw CameraError.cannotAddDataConnections
            }
            session.addConnection(frontDataConnection)
            session.addConnection(rearDataConnection)

            frontPreviewLayer.setSessionWithNoConnection(session)
            rearPreviewLayer.setSessionWithNoConnection(session)
            frontPreviewLayer.videoGravity = .resizeAspect
            rearPreviewLayer.videoGravity = .resizeAspect

            let frontPreviewConnection = AVCaptureConnection(inputPort: frontPort, videoPreviewLayer: frontPreviewLayer)
            let rearPreviewConnection = AVCaptureConnection(inputPort: rearPort, videoPreviewLayer: rearPreviewLayer)

            if frontPreviewConnection.isVideoMirroringSupported {
                frontPreviewConnection.automaticallyAdjustsVideoMirroring = false
                frontPreviewConnection.isVideoMirrored = true
            }
            if rearPreviewConnection.isVideoMirroringSupported {
                rearPreviewConnection.automaticallyAdjustsVideoMirroring = false
                rearPreviewConnection.isVideoMirrored = false
            }

            guard session.canAddConnection(frontPreviewConnection),
                  session.canAddConnection(rearPreviewConnection) else {
                throw CameraError.cannotAddPreviewConnections
            }
            session.addConnection(frontPreviewConnection)
            session.addConnection(rearPreviewConnection)

            session.startRunning()
            publish(.running)
        } catch {
            publish(.failed(String(describing: error)))
        }
    }

    private static func camera(position: AVCaptureDevice.Position) -> AVCaptureDevice? {
        AVCaptureDevice.DiscoverySession(
            deviceTypes: [.builtInWideAngleCamera, .builtInUltraWideCamera, .builtInTelephotoCamera, .builtInTrueDepthCamera],
            mediaType: .video,
            position: position
        ).devices.first
    }

    enum CameraError: Error {
        case missingCamera
        case cannotAddInputs
        case cannotAddOutputs
        case missingVideoPort
        case cannotAddDataConnections
        case cannotAddPreviewConnections
    }
}

extension DualCameraManager: AVCaptureVideoDataOutputSampleBufferDelegate {
    func captureOutput(_ output: AVCaptureOutput,
                       didOutput sampleBuffer: CMSampleBuffer,
                       from connection: AVCaptureConnection) {
        if output === frontOutput {
            DispatchQueue.main.async { self.frontFrameCount &+= 1 }
        } else if output === rearOutput {
            DispatchQueue.main.async { self.rearFrameCount &+= 1 }
        }
    }
}
