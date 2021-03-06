import Foundation
import AVFoundation
import PhotosUI

protocol CameraManDelegate: class {
  func cameraManNotAvailable(_ cameraMan: CameraMan)
  func cameraManPhotoLibNotAvailable(_ cameraMan: CameraMan)
  func cameraManDidStart(_ cameraMan: CameraMan)
  func cameraMan(_ cameraMan: CameraMan, didChangeInput input: AVCaptureDeviceInput)
}

class CameraMan {
  weak var delegate: CameraManDelegate?

  let session = AVCaptureSession()
  let queue = DispatchQueue(label: "no.hyper.ImagePicker.Camera.SessionQueue")

  var backCamera: AVCaptureDeviceInput?
  var frontCamera: AVCaptureDeviceInput?
  var stillImageOutput: AVCaptureStillImageOutput?
  var startOnFrontCamera: Bool = false
  var albumName: String?

  deinit {
    stop()
  }

  // MARK: - Setup

  func setup(_ startOnFrontCamera: Bool = false, albumName: String? = nil) {
    self.startOnFrontCamera = startOnFrontCamera
    self.albumName = albumName
    checkPermission()
  }

  func setupDevices() {
    // Input
    AVCaptureDevice
    .devices().flatMap {
      return $0
    }.filter {
      return $0.hasMediaType(AVMediaType.video)
    }.forEach {
      switch $0.position {
      case .front:
        self.frontCamera = try? AVCaptureDeviceInput(device: $0)
      case .back:
        self.backCamera = try? AVCaptureDeviceInput(device: $0)
      default:
        break
      }
    }

    // Output
    stillImageOutput = AVCaptureStillImageOutput()
    stillImageOutput?.outputSettings = [AVVideoCodecKey: AVVideoCodecJPEG]
  }

  func addInput(_ input: AVCaptureDeviceInput) {
    configurePreset(input)

    if session.canAddInput(input) {
      session.addInput(input)

      DispatchQueue.main.async {
        self.delegate?.cameraMan(self, didChangeInput: input)
      }
    }
  }

  // MARK: - Permission

  func checkPermission() {
    let status = AVCaptureDevice.authorizationStatus(for: AVMediaType.video)

    switch status {
    case .authorized:
      start()
    case .notDetermined:
      requestPermission()
    default:
      delegate?.cameraManNotAvailable(self)
    }
  }

  func requestPermission() {
    AVCaptureDevice.requestAccess(for: AVMediaType.video) { granted in
      DispatchQueue.main.async {
        if granted {
          self.start()
        } else {
          self.delegate?.cameraManNotAvailable(self)
        }
      }
    }
  }

  func checkSavePermission(completion: @escaping ((_ success: Bool) -> Void)) {
    // Photos
    let status = PHPhotoLibrary.authorizationStatus()
    switch status {
    case .authorized:
        completion(true)
    case .notDetermined:
        PHPhotoLibrary.requestAuthorization({status in
          if status == .authorized {
            completion(true)
          } else {
            self.delegate?.cameraManPhotoLibNotAvailable(self)
            completion(false)
          }
        })
    default:
      self.delegate?.cameraManPhotoLibNotAvailable(self)
      completion(false)
    }
  }

  // MARK: - Session

  var currentInput: AVCaptureDeviceInput? {
    return session.inputs.first as? AVCaptureDeviceInput
  }

  fileprivate func start() {
    // Devices
    setupDevices()

    guard let input = (self.startOnFrontCamera) ? frontCamera ?? backCamera : backCamera, let output = stillImageOutput else { return }

    addInput(input)

    if session.canAddOutput(output) {
      session.addOutput(output)
    }

    queue.async {
      self.session.startRunning()

      DispatchQueue.main.async {
        self.delegate?.cameraManDidStart(self)
      }
    }
  }

  func stop() {
    self.session.stopRunning()
  }

  func switchCamera(_ completion: (() -> Void)? = nil) {
    guard let currentInput = currentInput
      else {
        completion?()
        return
    }

    queue.async {
      guard let input = (currentInput == self.backCamera) ? self.frontCamera : self.backCamera
        else {
          DispatchQueue.main.async {
            completion?()
          }
          return
      }

      self.configure {
        self.session.removeInput(currentInput)
        self.addInput(input)
      }

      DispatchQueue.main.async {
        completion?()
      }
    }
  }

  func takePhoto(_ previewLayer: AVCaptureVideoPreviewLayer, locationManager: LocationManager?, completion: (() -> Void)? = nil) {
    guard let connection = stillImageOutput?.connection(with: AVMediaType.video) else { return }

    connection.videoOrientation = Helper.videoOrientation()

    queue.async {
      self.stillImageOutput?.captureStillImageAsynchronously(from: connection) {
        buffer, error in

        guard let buffer = buffer, error == nil && CMSampleBufferIsValid(buffer)
          else {
            DispatchQueue.main.async {
              completion?()
            }
            return
        }
        if let location = locationManager?.latestLocation, var metaDict = CMCopyDictionaryOfAttachments(nil, buffer, kCMAttachmentMode_ShouldPropagate) as? [String: Any] {
          // Get the existing metadata dictionary (if there is one)

          // Append the GPS metadata to the existing metadata
          metaDict[kCGImagePropertyGPSDictionary as String] = location.exifMetadata(heading: locationManager?.latestHeading)

          // Save the new metadata back to the buffer without duplicating any data
          CMSetAttachments(buffer, metaDict as CFDictionary, kCMAttachmentMode_ShouldPropagate)
        }

        // Get JPG image Data from the buffer
        guard let imageData = AVCaptureStillImageOutput.jpegStillImageNSDataRepresentation(buffer) else {
          // There was a problem; handle it here
          DispatchQueue.main.async {
            completion?()
          }
          return
        }

        // Now save this image to the Camera Roll (will save with GPS metadata embedded in the file)
        self.savePhoto(withData: imageData, location: locationManager?.latestLocation, completion: completion)
      }
    }
  }

  func savePhoto(withData data: Data, location: CLLocation?, completion: (() -> Void)? = nil) {
    checkSavePermission { (success) in
      if success {
        PHPhotoLibrary.shared().performChanges({
          let request = PHAssetCreationRequest.forAsset()
          request.addResource(with: PHAssetResourceType.photo, data: data, options: nil)
          request.creationDate = Date()
          request.location = location

          // save photo in given named album if set
          if let albumName = self.albumName, !albumName.isEmpty {
            var albumChangeRequest: PHAssetCollectionChangeRequest?

            if let assetCollection = self.fetchAssetCollectionForAlbum(albumName) {
              albumChangeRequest = PHAssetCollectionChangeRequest(for: assetCollection)
            } else {
              albumChangeRequest = PHAssetCollectionChangeRequest.creationRequestForAssetCollection(withTitle: albumName)
            }
            if let albumChangeRequest = albumChangeRequest, let assetPlaceholder = request.placeholderForCreatedAsset {
              let enumeration: NSArray = [assetPlaceholder]
              albumChangeRequest.addAssets(enumeration)
            }
          }
        }, completionHandler: { (success, error) in
          DispatchQueue.main.async {
            completion?()
          }
        })
      } else {
        completion?()
      }
    }
  }

  func fetchAssetCollectionForAlbum(_ albumName: String) -> PHAssetCollection? {

    let fetchOptions = PHFetchOptions()
    fetchOptions.predicate = NSPredicate(format: "title = %@", albumName)
    let collection = PHAssetCollection.fetchAssetCollections(with: .album, subtype: .any, options: fetchOptions)

    return collection.firstObject
  }

//  func savePhoto(_ image: UIImage, location: CLLocation?, completion: (() -> Void)? = nil) {
//    PHPhotoLibrary.shared().performChanges({
//      let request = PHAssetChangeRequest.creationRequestForAsset(from: image)
//      request.creationDate = Date()
//      request.location = location
//      }, completionHandler: { _ in
//        DispatchQueue.main.async {
//          completion?()
//        }
//    })
//  }

  func flash(_ mode: AVCaptureDevice.FlashMode) {
    guard let device = currentInput?.device, device.isFlashModeSupported(mode) else { return }

    queue.async {
      self.lock {
        device.flashMode = mode
      }
    }
  }

  func focus(_ point: CGPoint) {
    guard let device = currentInput?.device, device.isFocusModeSupported(AVCaptureDevice.FocusMode.locked) else { return }

    queue.async {
      self.lock {
        device.focusPointOfInterest = point
      }
    }
  }

  func zoomFactor(_ zoom: CGFloat) {
    guard let device = currentInput?.device else { return }

    queue.async {
      self.lock {
        var factor = zoom
        factor = max(1, min(factor, device.activeFormat.videoMaxZoomFactor))
        device.videoZoomFactor = factor
      }
    }
  }

  func zoomFactor() -> CGFloat {
    return currentInput?.device.videoZoomFactor ?? 1.0
  }

  func maxZoomFactor() -> CGFloat {
    return currentInput?.device.activeFormat.videoMaxZoomFactor ?? 1.0
  }

  // MARK: - Lock

  func lock(_ block: () -> Void) {
    if let device = currentInput?.device, (try? device.lockForConfiguration()) != nil {
      block()
      device.unlockForConfiguration()
    }
  }

  // MARK: - Configure
  func configure(_ block: () -> Void) {
    session.beginConfiguration()
    block()
    session.commitConfiguration()
  }

  // MARK: - Preset

  func configurePreset(_ input: AVCaptureDeviceInput) {
    for asset in preferredPresets() {
      if input.device.supportsSessionPreset(AVCaptureSession.Preset(rawValue: asset)) && self.session.canSetSessionPreset(AVCaptureSession.Preset(rawValue: asset)) {
        self.session.sessionPreset = AVCaptureSession.Preset(rawValue: asset)
        return
      }
    }
  }

  func preferredPresets() -> [String] {
    return [
      AVCaptureSession.Preset.photo.rawValue,
      AVCaptureSession.Preset.high.rawValue,
      AVCaptureSession.Preset.medium.rawValue,
      AVCaptureSession.Preset.low.rawValue
    ]
  }
}
