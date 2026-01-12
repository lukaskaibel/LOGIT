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
    @StateObject private var scanModel = ScanModel()

    @State private var photoPickerItem: PhotosPickerItem?
    @State private var workoutImage: UIImage?

    @Binding var selectedImage: UIImage?
    @Binding var isShowingPhotosPicker: Bool
    let type: ScanScreenType

    var body: some View {
        ZStack {
            // Background
            Color.black.ignoresSafeArea()
            
            // Camera preview or captured image
            Group {
                if let image = scanModel.photo?.image ?? workoutImage {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFit()
                } else {
                    cameraPreview
                        .ignoresSafeArea()
                }
            }
            
            // Controls overlay
            VStack {
                Spacer()
                
                // Bottom controls
                Group {
                    if scanModel.photo?.image != nil || workoutImage != nil {
                        VStack(spacing: 12) {
                            Button {
                                selectedImage = scanModel.photo?.image ?? workoutImage
                            } label: {
                                HStack {
                                    Spacer()
                                    Label(NSLocalizedString(type == .workout ? "useThisPhoto" : "useThisPhoto", comment: ""), systemImage: "sparkles")
                                        .fontWeight(.semibold)
                                    Spacer()
                                }
                                .padding(.vertical, 14)
                                .foregroundStyle(.black)
                            }
                            .buttonStyle(.glassProminent)
                            
                            Button {
                                scanModel.photo = nil
                                workoutImage = nil
                            } label: {
                                HStack {
                                    Spacer()
                                    Text(NSLocalizedString("retakePhoto", comment: ""))
                                        .fontWeight(.medium)
                                    Spacer()
                                }
                                .padding(.vertical, 14)
                            }
                            .buttonStyle(.glass)
                        }
                    } else {
                        ZStack {
                            captureButton
                            
                            HStack {
                                Spacer()
                                flashButton
                                    .frame(width: 44)
                                    .padding(.trailing, 30)
                            }
                        }
                    }
                }
                .padding(.horizontal)
                .padding(.bottom, 30)
            }
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
                .font(.system(size: 24, weight: .medium, design: .default))
                .frame(width: 44, height: 44)
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
    ScanScreen(selectedImage: .constant(nil), isShowingPhotosPicker: .constant(false), type: .workout)
}
