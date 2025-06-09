//
//  ScanScreen.swift
//  LOGIT
//
//  Created by Lukas Kaibel on 26.10.23.
//

import AVFoundation
import Camera_SwiftUI
import Combine
import OSLog
import PhotosUI
import SwiftUI

enum ScanScreenType {
    case template, workout
}

struct ScanScreen: View {
    @Environment(\.dismiss) private var dismiss

    @StateObject private var scanModel = ScanModel()

    @State private var isShowingPhotosPicker = false
    @State private var photoPickerItem: PhotosPickerItem?
    @State private var workoutImage: UIImage?

    @Binding var selectedImage: UIImage?
    let type: ScanScreenType

    var body: some View {
        GeometryReader { _ in
            VStack {
                HStack {
                    if scanModel.photo == nil && workoutImage == nil {
                        cancelButton
                        Spacer()
                        Text(NSLocalizedString(type == .workout ? "scanAWorkout" : "scanATemplate", comment: ""))
                        Spacer()
                        flashButton
                    } else {
                        dismissImageButton
                        Spacer()
                    }
                }
                .padding(.horizontal)
                Spacer()
                Group {
                    if let image = scanModel.photo?.image ?? workoutImage {
                        Image(uiImage: image)
                            .resizable()
                            .scaledToFit()
                    } else {
                        cameraPreview
                    }
                }
                .frame(maxWidth: .infinity)
                Spacer()
                Group {
                    if let image = scanModel.photo?.image ?? workoutImage {
                        HStack {
                            Button {
                                selectedImage = image
                                dismiss()
                            } label: {
                                Label(NSLocalizedString(type == .workout ? "generateWorkout" : "generateTemplate", comment: ""), systemImage: "gearshape.2.fill")
                            }
                            .buttonStyle(BigButtonStyle())
                        }
                    } else {
                        HStack {
                            Button {
                                isShowingPhotosPicker = true
                            } label: {
                                Image(systemName: "photo.on.rectangle")
                            }
                            .buttonStyle(CapsuleButtonStyle())
                            Spacer()
                            captureButton
                            Spacer()
                            Button {
                                isShowingPhotosPicker = true
                            } label: {
                                Image(systemName: "photo.on.rectangle")
                            }
                            .buttonStyle(CapsuleButtonStyle())
                            .disabled(true)
                            .hidden()
                        }
                    }
                }
                .padding(.horizontal)
            }
            .padding(.vertical)
        }
        .onChange(of: photoPickerItem) { _ in
            Task {
                if let data = try? await photoPickerItem?.loadTransferable(type: Data.self) {
                    if let uiImage = UIImage(data: data) {
                        Logger().info("CreateTemplateMenu: Image picked")
                        workoutImage = uiImage
                        return
                    }
                }

                Logger().warning("CreateTemplateMenu: Loading image failed")
            }
        }
        .photosPicker(
            isPresented: $isShowingPhotosPicker,
            selection: $photoPickerItem,
            photoLibrary: .shared()
        )
    }

    // MARK: - Supporting Views

    private var flashButton: some View {
        Button(action: {
            scanModel.switchFlash()
        }, label: {
            Image(systemName: scanModel.isFlashOn ? "bolt.fill" : "bolt.slash.fill")
                .font(.system(size: 20, weight: .medium, design: .default))
        })
        .accentColor(scanModel.isFlashOn ? .yellow : .white)
    }

    private var captureButton: some View {
        Button(action: {
            scanModel.capturePhoto()
        }, label: {
            Circle()
                .foregroundColor(.white)
                .frame(width: 80, height: 80, alignment: .center)
                .overlay(
                    Circle()
                        .stroke(Color.black.opacity(0.8), lineWidth: 2)
                        .frame(width: 65, height: 65, alignment: .center)
                )
        })
    }

    private var cameraPreview: some View {
        CameraPreview(session: scanModel.session)
            .onAppear {
                scanModel.configure()
            }
            .alert(isPresented: $scanModel.showAlertError, content: {
                Alert(title: Text(scanModel.alertError.title), message: Text(scanModel.alertError.message), dismissButton: .default(Text(scanModel.alertError.primaryButtonTitle), action: {
                    scanModel.alertError.primaryAction?()
                }))
            })
            .overlay(
                Group {
                    if scanModel.willCapturePhoto {
                        Color.black
                    }
                }
            )
            .animation(.easeInOut)
    }

    private var dismissImageButton: some View {
        Button {
            scanModel.photo = nil
            workoutImage = nil
        } label: {
            Image(systemName: "xmark")
                .font(.title3.weight(.semibold))
                .padding(7)
                .background(Color.fill)
                .clipShape(Circle())
        }
    }

    private var cancelButton: some View {
        Button {
            dismiss()
        } label: {
            Image(systemName: "xmark")
        }
        .font(.title2)
    }
}

private final class ScanModel: ObservableObject {
    private let service = CameraService()

    @Published var photo: Photo?

    @Published var showAlertError = false

    @Published var isFlashOn = false

    @Published var willCapturePhoto = false

    var alertError: AlertError!

    var session: AVCaptureSession

    private var subscriptions = Set<AnyCancellable>()

    init() {
        session = service.session

        service.$photo.sink { [weak self] photo in
            guard let pic = photo else { return }
            self?.photo = pic
        }
        .store(in: &subscriptions)

        service.$shouldShowAlertView.sink { [weak self] val in
            self?.alertError = self?.service.alertError
            self?.showAlertError = val
        }
        .store(in: &subscriptions)

        service.$flashMode.sink { [weak self] mode in
            self?.isFlashOn = mode == .on
        }
        .store(in: &subscriptions)

        service.$willCapturePhoto.sink { [weak self] val in
            self?.willCapturePhoto = val
        }
        .store(in: &subscriptions)
    }

    func configure() {
        service.checkForPermissions()
        service.configure()
    }

    func capturePhoto() {
        service.capturePhoto()
    }

    func flipCamera() {
        service.changeCamera()
    }

    func zoom(with factor: CGFloat) {
        service.set(zoom: factor)
    }

    func switchFlash() {
        service.flashMode = service.flashMode == .on ? .off : .on
    }
}

#Preview {
    ScanScreen(selectedImage: .constant(nil), type: .workout)
}
