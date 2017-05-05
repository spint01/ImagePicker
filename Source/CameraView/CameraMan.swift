import Foundation
import AVFoundation
import PhotosUI

protocol CameraManDelegate: class {
  func cameraManNotAvailable(_ cameraMan: CameraMan)
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

  deinit {
    stop()
  }

  // MARK: - Setup

  func setup(_ startOnFrontCamera: Bool = false) {
    self.startOnFrontCamera = startOnFrontCamera
    checkPermission()
  }

  func setupDevices() {
    // Input
    AVCaptureDevice
    .devices().flatMap {
      return $0 as? AVCaptureDevice
    }.filter {
      return $0.hasMediaType(AVMediaTypeVideo)
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
    let status = AVCaptureDevice.authorizationStatus(forMediaType: AVMediaTypeVideo)

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
    AVCaptureDevice.requestAccess(forMediaType: AVMediaTypeVideo) { granted in
      DispatchQueue.main.async {
        if granted {
          self.start()
        } else {
          self.delegate?.cameraManNotAvailable(self)
        }
      }
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

  func takePhoto(_ previewLayer: AVCaptureVideoPreviewLayer, location: CLLocation?, completion: (() -> Void)? = nil) {
    guard let connection = stillImageOutput?.connection(withMediaType: AVMediaTypeVideo) else { return }

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
        if let location = location, var metaDict = CMCopyDictionaryOfAttachments(nil, buffer, kCMAttachmentMode_ShouldPropagate) as? [String: Any] {
          // Get the existing metadata dictionary (if there is one)

          // Append the GPS metadata to the existing metadata
          metaDict[kCGImagePropertyGPSDictionary as String] = location.exifMetadata()

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
        self.savePhoto(withData: imageData, location: location, completion: completion)
      }
    }
  }

  func savePhoto(withData data: Data, location: CLLocation?, completion: (() -> Void)? = nil) {
    PHPhotoLibrary.shared().performChanges({
      if #available(iOS 9.0, *) {
        // For iOS 9+ we can skip the temporary file step and write the image data from the buffer directly to an asset
        let request = PHAssetCreationRequest.forAsset()
        request.addResource(with: PHAssetResourceType.photo, data: data, options: nil)
        request.creationDate = Date()
        request.location = location
      } else {
        // Fallback on earlier versions; write a temporary file and then add this file to the Camera Roll using the Photos API
        let tmpURL = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true).appendingPathComponent("tempPhoto").appendingPathExtension("jpg")
        do {
          try data.write(to: tmpURL)

          let request = PHAssetChangeRequest.creationRequestForAssetFromImage(atFileURL: tmpURL)
          request?.creationDate = Date()
          request?.location = location
        } catch {
          // Error writing the data; photo is not appended to the camera roll
        }
      }
    }, completionHandler: { _ in
      DispatchQueue.main.async {
        completion?()
      }
    })
  }

  func savePhoto(_ image: UIImage, location: CLLocation?, completion: (() -> Void)? = nil) {
    PHPhotoLibrary.shared().performChanges({
      let request = PHAssetChangeRequest.creationRequestForAsset(from: image)
      request.creationDate = Date()
      request.location = location
      }, completionHandler: { _ in
        DispatchQueue.main.async {
          completion?()
        }
    })
  }

  func flash(_ mode: AVCaptureFlashMode) {
    guard let device = currentInput?.device, device.isFlashModeSupported(mode) else { return }

    queue.async {
      self.lock {
        device.flashMode = mode
      }
    }
  }

  func focus(_ point: CGPoint) {
    guard let device = currentInput?.device, device.isFocusModeSupported(AVCaptureFocusMode.locked) else { return }

    queue.async {
      self.lock {
        device.focusPointOfInterest = point
      }
    }
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
      if input.device.supportsAVCaptureSessionPreset(asset) && self.session.canSetSessionPreset(asset) {
        self.session.sessionPreset = asset
        return
      }
    }
  }

  func preferredPresets() -> [String] {
    return [
      AVCaptureSessionPresetHigh,
      AVCaptureSessionPresetMedium,
      AVCaptureSessionPresetLow
    ]
  }
}
