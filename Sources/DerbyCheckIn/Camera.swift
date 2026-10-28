import DerbyCore
import AVFoundation
import SwiftUI

final class CameraModel: NSObject, ObservableObject, AVCapturePhotoCaptureDelegate {
    let session = AVCaptureSession()
    private let output = AVCapturePhotoOutput()
    private let queue = DispatchQueue(label: "camera")
    private var input: AVCaptureDeviceInput?

    @Published var devices: [AVCaptureDevice] = []
    @Published var deviceID = ""
    @Published var captured: NSImage?
    @Published var error: String?

    func start() {
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:
            loadDevices()
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .video) { granted in
                DispatchQueue.main.async {
                    if granted { self.loadDevices() } else { self.denied() }
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
        guard let device = devices.first(where: { $0.uniqueID == id }) ?? AVCaptureDevice(uniqueID: id) else { return }
        deviceID = id
        queue.async {
            self.session.beginConfiguration()
            self.session.sessionPreset = .photo
            if let old = self.input { self.session.removeInput(old) }
            do {
                let newInput = try AVCaptureDeviceInput(device: device)
                if self.session.canAddInput(newInput) {
                    self.session.addInput(newInput)
                    self.input = newInput
                }
                if self.session.canAddOutput(self.output) { self.session.addOutput(self.output) }
            } catch {
                DispatchQueue.main.async { self.error = "Could not open the camera: \(error.localizedDescription)" }
            }
            self.session.commitConfiguration()
            if !self.session.isRunning { self.session.startRunning() }
        }
    }

    func stop() {
        queue.async { self.session.stopRunning() }
    }

    func capture() {
        queue.async {
            self.output.capturePhoto(with: AVCapturePhotoSettings(), delegate: self)
        }
    }

    func photoOutput(_ output: AVCapturePhotoOutput, didFinishProcessingPhoto photo: AVCapturePhoto, error: Error?) {
        let image = photo.fileDataRepresentation().flatMap(NSImage.init(data:))
        DispatchQueue.main.async {
            if let image { self.captured = image } else { self.error = "The photo could not be taken." }
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
