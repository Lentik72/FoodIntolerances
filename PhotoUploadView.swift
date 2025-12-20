import SwiftUI
import PhotosUI

struct PhotoUploadView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var selectedItem: PhotosPickerItem?
    @State private var image: Image?
    @State private var showCamera = false
    @State private var showPhotoLibrary = false
    @State private var capturedUIImage: UIImage?

    var body: some View {
        NavigationView {
            VStack(spacing: 20) {
                if let image = image {
                    image
                        .resizable()
                        .scaledToFit()
                        .frame(height: 300)
                } else {
                    Text("No photo selected.")
                        .foregroundColor(.gray)
                }

                HStack(spacing: 20) {
                    // 📸 Take a Photo
                    Button(action: {
                        showCamera = true
                    }) {
                        Label("Take Photo", systemImage: "camera")
                            .frame(width: 150, height: 50)
                            .background(Color.blue)
                            .foregroundColor(.white)
                            .cornerRadius(10)
                    }
                    .sheet(isPresented: $showCamera) {
                        ImagePicker(sourceType: .camera, selectedImage: $capturedUIImage)
                    }

                    // 🖼️ Select from Library
                    Button(action: {
                        showPhotoLibrary = true
                    }) {
                        Label("Choose Photo", systemImage: "photo")
                            .frame(width: 150, height: 50)
                            .background(Color.green)
                            .foregroundColor(.white)
                            .cornerRadius(10)
                    }
                    .photosPicker(isPresented: $showPhotoLibrary, selection: $selectedItem, matching: .images)
                }

                Button("Upload") {
                    dismiss()
                }
                .padding()
                .background(Color.purple)
                .foregroundColor(.white)
                .cornerRadius(10)
            }
            .padding()
            .onChange(of: selectedItem) { oldItem, newItem in
                Task {
                    if let data = try? await newItem?.loadTransferable(type: Data.self),
                       let uiImage = UIImage(data: data) {
                        image = Image(uiImage: uiImage)
                    }
                }
            }
            .onChange(of: capturedUIImage) { oldValue, newValue in
                if let uiImage = newValue {
                    image = Image(uiImage: uiImage)
                }
            }
            .navigationTitle("Upload/Take Photo")
        }
    }
}
