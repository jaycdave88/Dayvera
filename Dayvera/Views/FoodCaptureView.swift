import AVFoundation
import PhotosUI
import SwiftUI

struct FoodCaptureView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var nutrition: NutritionModel
    let onReview: (Data, [RecognizedFood]) -> Void
    @State private var pickerItem: PhotosPickerItem?
    @State private var photo: Data?
    @State private var showingCamera = false
    @State private var isAnalyzing = false
    @State private var error: String?
    @State private var analysis: Task<Void, Never>?

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 24) {
                    if let photo, let image = UIImage(data: photo) {
                        Image(uiImage: image).resizable().scaledToFit().frame(maxHeight: 300).clipShape(RoundedRectangle(cornerRadius: 24))
                    } else {
                        Image(systemName: "camera.macro").font(.system(size: 72)).foregroundStyle(Color.coachMint).padding(30).accessibilityHidden(true)
                    }
                    Text("A photo is the starting point.").font(.title2.bold())
                    Text("We’ll identify visible foods on your device. You’ll match the food, check portions, and add anything the camera cannot see before saving.")
                        .foregroundStyle(.secondary)
                    if let reason = nutrition.recognition.unavailableReason { Text(reason).font(.callout).foregroundStyle(Color.coachAmber) }
                    Button { Task { await openCamera() } } label: { Label("Take a photo", systemImage: "camera.fill").frame(maxWidth: .infinity, minHeight: 44) }
                        .buttonStyle(.borderedProminent)
                    PhotosPicker(selection: $pickerItem, matching: .images) { Label("Choose a photo", systemImage: "photo.on.rectangle") }
                    if photo != nil {
                        Button { analyze() } label: {
                            HStack { if isAnalyzing { SwiftUI.ProgressView() }; Text(isAnalyzing ? "Identifying food…" : "Identify food on device") }.frame(minHeight: 44)
                        }.buttonStyle(.bordered).disabled(isAnalyzing || nutrition.recognition.unavailableReason != nil)
                        Button("Use photo with manual food entry") {
                            if let photo { onReview(photo, []); dismiss() }
                        }.frame(minHeight: 44)
                    }
                    if let error { Text(error).foregroundStyle(Color.coachRose) }
                    Label("Photos stay on this device", systemImage: "lock.shield").font(.footnote).foregroundStyle(.secondary)
                }.padding(24)
            }.background(Color.coachBackground)
            .navigationTitle("Photograph food").navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cancel") { analysis?.cancel(); dismiss() } } }
            .sheet(isPresented: $showingCamera) { CameraCapture { data in prepare(data) } }
            .onChange(of: pickerItem) { _, item in
                Task {
                    do { if let data = try await item?.loadTransferable(type: Data.self) { prepare(data) } }
                    catch { self.error = "The selected photo could not be loaded." }
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
        guard UIImagePickerController.isSourceTypeAvailable(.camera) else { error = "A camera is unavailable here. Choose a photo or enter food manually."; return }
        let granted = await AVCaptureDevice.requestAccess(for: .video)
        if granted { showingCamera = true } else { error = "Camera access is off. Enable it in Settings or choose a photo." }
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
