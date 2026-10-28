import DerbyCore
import DerbyKit
import AVFoundation
import SwiftUI

/// Runs the capture session. AVCaptureSession isn't safe to share between threads, so
/// everything except creating the preview layer happens on `queue`, one step at a time.
final class CaptureEngine: NSObject, AVCapturePhotoCaptureDelegate, @unchecked Sendable {
    let session = AVCaptureSession()
    private let output = AVCapturePhotoOutput()
    private let queue = DispatchQueue(label: "derby.camera")
    private var input: AVCaptureDeviceInput?
    private var photoTaken: (@Sendable (Data?) -> Void)?

    /// Switches to the camera with this id and starts it. Calls `failed` with a message if it can't.
    func use(deviceID: String, failed: @escaping @Sendable (String) -> Void) {
        queue.async { [self] in
            guard let device = AVCaptureDevice(uniqueID: deviceID) else {
                failed("That camera is no longer connected.")
                return
            }
            session.beginConfiguration()
            session.sessionPreset = .photo
            if let input { session.removeInput(input) }
            do {
                let newInput = try AVCaptureDeviceInput(device: device)
                if session.canAddInput(newInput) {
                    session.addInput(newInput)
                    input = newInput
                }
                if session.canAddOutput(output) { session.addOutput(output) }
            } catch {
                failed("Could not open the camera: \(error.localizedDescription)")
            }
            session.commitConfiguration()
            if !session.isRunning { session.startRunning() }
        }
    }

    func stop() {
        queue.async { [self] in session.stopRunning() }
    }

    /// Takes a photo and calls `done` with its JPEG or HEIC data, or nil if it failed.
    func capture(_ done: @escaping @Sendable (Data?) -> Void) {
        queue.async { [self] in
            photoTaken = done
            output.capturePhoto(with: AVCapturePhotoSettings(), delegate: self)
        }
    }

    func photoOutput(_ output: AVCapturePhotoOutput, didFinishProcessingPhoto photo: AVCapturePhoto, error: Error?) {
        let data = photo.fileDataRepresentation()
        queue.async { [self] in
            photoTaken?(data)
            photoTaken = nil
        }
    }
}

/// What the camera sheet shows. Lives on the main actor; hands the session work to CaptureEngine.
@MainActor
final class CameraModel: ObservableObject {
    private let engine = CaptureEngine()
    var session: AVCaptureSession { engine.session }

    @Published var devices: [AVCaptureDevice] = []
    @Published var deviceID = ""
    @Published var captured: NSImage?
    @Published var error: String?

    func start() {
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:
            loadDevices()
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .video) { @Sendable [weak self] granted in
                Task { @MainActor in
                    if granted { self?.loadDevices() } else { self?.denied() }
                }
            }
        default:
            denied()
        }
    }

    private func denied() {
        error = "Camera access is off. Turn it on in System Settings › Privacy & Security › Camera, then try again."
    }

    private func loadDevices() {
        devices = AVCaptureDevice.DiscoverySession(
            deviceTypes: [.builtInWideAngleCamera, .external, .continuityCamera],
            mediaType: .video, position: .unspecified
        ).devices
        guard let device = AVCaptureDevice.default(for: .video) ?? devices.first else {
            error = "No camera was found. Connect a webcam or choose a photo file instead."
            return
        }
        select(device.uniqueID)
    }

    func select(_ id: String) {
        deviceID = id
        engine.use(deviceID: id) { @Sendable [weak self] message in
            Task { @MainActor in self?.error = message }
        }
    }

    func stop() {
        engine.stop()
    }

    func capture() {
        engine.capture { @Sendable [weak self] data in
            Task { @MainActor in
                if let image = data.flatMap(NSImage.init(data:)) {
                    self?.captured = image
                } else {
                    self?.error = "The photo could not be taken."
                }
            }
        }
    }
}

struct CameraPreview: NSViewRepresentable {
    let session: AVCaptureSession

    final class PreviewView: NSView {
        let previewLayer: AVCaptureVideoPreviewLayer

        init(session: AVCaptureSession) {
            previewLayer = AVCaptureVideoPreviewLayer(session: session)
            super.init(frame: .zero)
            wantsLayer = true
            layer = CALayer()
            layer?.backgroundColor = NSColor.black.cgColor
            previewLayer.videoGravity = .resizeAspect
            layer?.addSublayer(previewLayer)
        }

        required init?(coder: NSCoder) { fatalError("not used") }

        override func layout() {
            super.layout()
            previewLayer.frame = bounds
        }
    }

    func makeNSView(context: Context) -> PreviewView { PreviewView(session: session) }
    func updateNSView(_ nsView: PreviewView, context: Context) {}
}

/// Sheet that shows a live camera, takes a picture and hands it back.
struct CameraSheet: View {
    let title: String
    let onUse: (NSImage) -> Void
    @Environment(\.dismiss) private var dismiss
    @StateObject private var camera = CameraModel()

    var body: some View {
        VStack(spacing: 12) {
            HStack {
                Text(title).font(.headline)
                Spacer()
                if camera.devices.count > 1 {
                    Picker("Camera", selection: Binding(get: { camera.deviceID }, set: { camera.select($0) })) {
                        ForEach(camera.devices, id: \.uniqueID) { Text($0.localizedName).tag($0.uniqueID) }
                    }
                    .frame(maxWidth: 260)
                }
            }

            ZStack {
                if let image = camera.captured {
                    Image(nsImage: image).resizable().scaledToFit()
                } else if let error = camera.error {
                    Text(error).multilineTextAlignment(.center).padding()
                } else {
                    CameraPreview(session: camera.session)
                }
            }
            .frame(width: 640, height: 480)
            .background(.black)
            .clipShape(RoundedRectangle(cornerRadius: 8))

            HStack {
                Button("Cancel", role: .cancel) { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Spacer()
                if let image = camera.captured {
                    Button("Retake") { camera.captured = nil }
                    Button("Use Photo") {
                        onUse(image)
                        dismiss()
                    }
                    .keyboardShortcut(.defaultAction)
                    .buttonStyle(.borderedProminent)
                } else {
                    Button("Take Photo", systemImage: "camera.fill") { camera.capture() }
                        .keyboardShortcut(.defaultAction)
                        .buttonStyle(.borderedProminent)
                        .disabled(camera.error != nil)
                }
            }
        }
        .padding(20)
        .onAppear { camera.start() }
        .onDisappear { camera.stop() }
    }
}
