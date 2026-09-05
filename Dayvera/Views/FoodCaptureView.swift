import AVFoundation
import PhotosUI
import SwiftUI

enum FoodCaptureSource {
    case choice, camera, photoLibrary
}

struct FoodCaptureView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL
    @EnvironmentObject private var nutrition: NutritionModel
    let onReview: (Data, [RecognizedFood]) -> Void
    @State private var pickerItem: PhotosPickerItem?
    @State private var photo: Data?
    @State private var showingCamera = false
    @State private var showingPhotoPicker = false
    @State private var cameraAccessDenied = false
    @State private var isAnalyzing = false
    @State private var error: String?
    @State private var analysis: Task<Void, Never>?
    @State private var launchedInitialSource = false
    let initialSource: FoodCaptureSource

    init(initialSource: FoodCaptureSource = .choice, onReview: @escaping (Data, [RecognizedFood]) -> Void) {
        self.initialSource = initialSource
        self.onReview = onReview
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 24) {
                    if let photo, let image = UIImage(data: photo) {
                        Image(uiImage: image).resizable().scaledToFit().frame(maxHeight: 300).clipShape(RoundedRectangle(cornerRadius: 24))
                    } else {
                        Image(systemName: "camera.macro").font(.system(size: 72)).foregroundStyle(Color.coachMint).padding(30).accessibilityHidden(true)
                    }
                    Text(isAnalyzing ? "Looking for foods…" : photo == nil ? "Add a meal photo" : "Review your photo").font(.title2.bold())
                    Text(isAnalyzing
                         ? "Dayvera will suggest foods and rough portions. You’ll review everything before anything is saved."
                         : "A photo suggests visible foods and rough portions. Trusted nutrients come from the food you match, a package label, or values you enter.")
                        .foregroundStyle(.secondary)
                    if let reason = nutrition.recognition.unavailableReason { Text(reason).font(.callout).foregroundStyle(Color.coachAmber) }
                    if cameraAccessDenied {
                        Button("Open Settings") {
                            if let url = URL(string: UIApplication.openSettingsURLString) { openURL(url) }
                        }
                        .buttonStyle(.bordered).frame(minHeight: 44)
                    }
                    if !isAnalyzing {
                        Button { Task { await openCamera() } } label: { Label(photo == nil ? "Take Photo" : "Retake Photo", systemImage: "camera.fill").frame(maxWidth: .infinity, minHeight: 44) }
                            .buttonStyle(.borderedProminent)
                        PhotosPicker(selection: $pickerItem, matching: .images) {
                            Label(photo == nil ? "Choose Photo" : "Choose Another Photo", systemImage: "photo.on.rectangle").frame(minHeight: 44)
                        }.buttonStyle(.bordered)
                    }
                    if photo != nil {
                        Button { analyze() } label: {
                            HStack { if isAnalyzing { SwiftUI.ProgressView() }; Text(isAnalyzing ? "Looking for foods…" : "Identify Food on Device") }.frame(maxWidth: .infinity, minHeight: 44)
                        }.buttonStyle(.borderedProminent).disabled(isAnalyzing || nutrition.recognition.unavailableReason != nil)
                        Button("Continue without recognition") {
                            if let photo { onReview(photo, []); dismiss() }
                        }.frame(minHeight: 44).disabled(isAnalyzing)
                    }
                    if let error { Text(error).foregroundStyle(Color.coachRose) }
                    Label("Photos stay on this device", systemImage: "lock.shield").font(.footnote).foregroundStyle(.secondary)
                }.padding(24)
            }.background(Color.coachBackground)
            .navigationTitle("Photograph food").navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cancel") { analysis?.cancel(); dismiss() } } }
            .sheet(isPresented: $showingCamera) { CameraCapture { data in prepare(data) } }
            .photosPicker(isPresented: $showingPhotoPicker, selection: $pickerItem, matching: .images)
            .onChange(of: pickerItem) { _, item in
                Task {
                    do { if let data = try await item?.loadTransferable(type: Data.self) { prepare(data) } }
                    catch { self.error = "The selected photo could not be loaded." }
                }
            }
            .task {
                guard !launchedInitialSource else { return }
                launchedInitialSource = true
                switch initialSource {
                case .camera: await openCamera()
                case .photoLibrary: showingPhotoPicker = true
                case .choice: break
                }
            }
            .onDisappear { analysis?.cancel() }
        }
    }
    private func prepare(_ data: Data) {
        analysis?.cancel(); isAnalyzing = false
        do { photo = try NutritionStore.normalizedPhoto(data); error = nil } catch { self.error = error.localizedDescription }
    }
    private func openCamera() async {
        cameraAccessDenied = false
        guard UIImagePickerController.isSourceTypeAvailable(.camera) else {
            error = "A camera is unavailable on this device. Choose a photo or enter food manually."
            return
        }
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:
            showingCamera = true
        case .notDetermined:
            if await AVCaptureDevice.requestAccess(for: .video) {
                showingCamera = true
            } else {
                cameraAccessDenied = true
                error = "Camera access is off. Enable it in Settings or choose a photo."
            }
        case .denied:
            cameraAccessDenied = true
            error = "Camera access is off. Enable it in Settings or choose a photo."
        case .restricted:
            error = "Camera access is restricted on this device. Choose a photo or enter food manually."
        @unknown default:
            error = "Camera access is unavailable. Choose a photo or enter food manually."
        }
    }
    private func analyze() {
        guard let photo else { return }
        analysis?.cancel(); isAnalyzing = true; error = nil
        analysis = Task { @MainActor in
            defer { isAnalyzing = false }
            do {
                let foods = try await nutrition.recognition.recognize(imageData: photo)
                try Task.checkCancellation()
                if foods.isEmpty { error = "No foods could be identified. Try another photo or enter the meal manually."; return }
                onReview(photo, foods); dismiss()
            } catch is CancellationError { }
            catch { self.error = error.localizedDescription }
        }
    }
}

private struct CameraCapture: UIViewControllerRepresentable {
    @Environment(\.dismiss) private var dismiss
    let onCapture: (Data) -> Void
    func makeCoordinator() -> Coordinator { Coordinator(parent: self) }
    func makeUIViewController(context: Context) -> UIImagePickerController {
        let picker = UIImagePickerController(); picker.sourceType = .camera; picker.cameraCaptureMode = .photo
        picker.delegate = context.coordinator; return picker
    }
    func updateUIViewController(_ uiViewController: UIImagePickerController, context: Context) {}
    final class Coordinator: NSObject, UIImagePickerControllerDelegate, UINavigationControllerDelegate {
        let parent: CameraCapture
        init(parent: CameraCapture) { self.parent = parent }
        func imagePickerController(_ picker: UIImagePickerController, didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]) {
            if let image = info[.originalImage] as? UIImage, let data = image.jpegData(compressionQuality: 0.9) { parent.onCapture(data) }
            parent.dismiss()
        }
        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) { parent.dismiss() }
    }
}
