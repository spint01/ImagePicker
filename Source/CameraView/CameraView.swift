import UIKit
import AVFoundation
import PhotosUI

protocol CameraViewDelegate: class {

  func setFlashButtonHidden(_ hidden: Bool)
  func imageToLibrary()
  func cameraNotAvailable()
}

class CameraView: UIViewController, CLLocationManagerDelegate, CameraManDelegate {

  var configuration = Configuration()

  lazy var blurView: UIVisualEffectView = { [unowned self] in
    let effect = UIBlurEffect(style: .dark)
    let blurView = UIVisualEffectView(effect: effect)

    return blurView
    }()

  lazy var focusImageView: UIImageView = { [unowned self] in
    let imageView = UIImageView()
    imageView.image = AssetManager.getImage("focusIcon")
    imageView.backgroundColor = UIColor.clear
    imageView.frame = CGRect(x: 0, y: 0, width: 110, height: 110)
    imageView.alpha = 0

    return imageView
    }()

  lazy var capturedImageView: UIView = { [unowned self] in
    let view = UIView()
    view.backgroundColor = UIColor.black
    view.alpha = 0

    return view
    }()

  lazy var containerView: UIView = {
    let view = UIView()
    view.alpha = 0

    return view
  }()

  lazy var noCameraLabel: UILabel = { [unowned self] in
    let label = UILabel()
    label.font = self.configuration.noCameraFont
    label.textColor = self.configuration.noCameraColor
    label.text = self.configuration.noCameraTitle
    label.sizeToFit()

    return label
    }()

  lazy var noCameraButton: UIButton = { [unowned self] in
    let button = UIButton(type: .system)
    let title = NSAttributedString(string: self.configuration.settingsTitle,
      attributes: [
        NSFontAttributeName : self.configuration.settingsFont,
        NSForegroundColorAttributeName : self.configuration.settingsColor
      ])

    button.setAttributedTitle(title, for: UIControlState())
    button.contentEdgeInsets = UIEdgeInsets(top: 5.0, left: 10.0, bottom: 5.0, right: 10.0)
    button.sizeToFit()
    button.layer.borderColor = self.configuration.settingsColor.cgColor
    button.layer.borderWidth = 1
    button.layer.cornerRadius = 4
    button.addTarget(self, action: #selector(settingsButtonDidTap), for: .touchUpInside)

    return button
    }()

  lazy var tapGestureRecognizer: UITapGestureRecognizer = { [unowned self] in
    let gesture = UITapGestureRecognizer()
    gesture.addTarget(self, action: #selector(tapGestureRecognizerHandler(_:)))

    return gesture
    }()

  lazy var pinchGestureRecognizer: UIPinchGestureRecognizer = { [unowned self] in
    let gesture = UIPinchGestureRecognizer(target: self, action: #selector(pinchGestureRecognizerHandler(_:)))

    return gesture
  }()

  let cameraMan = CameraMan()

  var previewLayer: AVCaptureVideoPreviewLayer?
  weak var delegate: CameraViewDelegate?
  var animationTimer: Timer?
  var locationManager: LocationManager?
  var startOnFrontCamera: Bool = false
  var pivotPinchScale: CGFloat = 1.0
  var maxZoomFactor: CGFloat = 3.5

  public init(configuration: Configuration? = nil) {
    if let configuration = configuration {
      self.configuration = configuration
    }
    super.init(nibName: nil, bundle: nil)
  }

  required init?(coder aDecoder: NSCoder) {
    fatalError("init(coder:) has not been implemented")
  }

  override func viewDidLoad() {
    super.viewDidLoad()

    if configuration.recordLocation {
      locationManager = LocationManager()
    }

    view.backgroundColor = configuration.mainColor

    view.addSubview(containerView)
    containerView.addSubview(blurView)

    [focusImageView, capturedImageView].forEach {
      view.addSubview($0)
    }

    view.addGestureRecognizer(tapGestureRecognizer)
    view.addGestureRecognizer(pinchGestureRecognizer)

    cameraMan.delegate = self
    cameraMan.setup(self.startOnFrontCamera, albumName: configuration.photoAlbumName)
  }

  override func viewDidAppear(_ animated: Bool) {
    super.viewDidAppear(animated)

    locationManager?.startUpdatingLocation()
  }

  override func viewDidDisappear(_ animated: Bool) {
    super.viewDidDisappear(animated)
    locationManager?.stopUpdatingLocation()
  }

  func setupPreviewLayer() {
    guard let layer = AVCaptureVideoPreviewLayer(session: cameraMan.session) else { return }

    layer.backgroundColor = configuration.mainColor.cgColor
    layer.autoreverses = true
    layer.videoGravity = AVLayerVideoGravityResizeAspectFill

    view.layer.insertSublayer(layer, at: 0)
    layer.frame = view.layer.frame
    view.clipsToBounds = true

    if Helper.runningOnIpad {
      layer.connection.videoOrientation = Helper.videoOrientation()
    } else {
      layer.connection.videoOrientation = .portrait
    }
    previewLayer = layer
  }

  // MARK: - Layout

  override func viewDidLayoutSubviews() {
    super.viewDidLayoutSubviews()

    let centerX = view.bounds.width / 2

    noCameraLabel.center = CGPoint(x: centerX,
      y: view.bounds.height / 2 - 80)

    noCameraButton.center = CGPoint(x: centerX,
      y: noCameraLabel.frame.maxY + 20)

    blurView.frame = view.bounds
    containerView.frame = view.bounds
    capturedImageView.frame = view.bounds
    previewLayer?.frame = view.bounds
  }

  // MARK: - Actions

  func settingsButtonDidTap() {
    DispatchQueue.main.async {
      if let settingsURL = URL(string: UIApplicationOpenSettingsURLString) {
        UIApplication.shared.openURL(settingsURL)
      }
    }
  }

  // MARK: - Camera actions

  func rotateCamera() {
    UIView.animate(withDuration: 0.3, animations: { _ in
      self.containerView.alpha = 1
      }, completion: { _ in
        self.cameraMan.switchCamera {
          UIView.animate(withDuration: 0.7, animations: {
            self.containerView.alpha = 0
          })
        }
    })
  }

  func flashCamera(_ title: String) {
    let mapping: [String: AVCaptureFlashMode] = [
      "ON": .on,
      "OFF": .off
    ]

    cameraMan.flash(mapping[title] ?? .auto)
  }

  func takePicture(_ completion: @escaping () -> ()) {
    guard let previewLayer = previewLayer else { return }

    UIView.animate(withDuration: 0.1, animations: {
      self.capturedImageView.alpha = 1
      }, completion: { _ in
        UIView.animate(withDuration: 0.1, animations: {
          self.capturedImageView.alpha = 0
        })
    })

    cameraMan.takePhoto(previewLayer, locationManager: locationManager) {
      completion()
      self.delegate?.imageToLibrary()
    }
  }

  // MARK: - Timer methods

  func timerDidFire() {
    UIView.animate(withDuration: 0.3, animations: { [unowned self] in
      self.focusImageView.alpha = 0
      }, completion: { _ in
        self.focusImageView.transform = CGAffineTransform.identity
    })
  }

  // MARK: - Camera methods

  func focusTo(_ point: CGPoint) {
    let convertedPoint = CGPoint(x: point.x / view.bounds.width,
                                 y:point.y / view.bounds.height)

    cameraMan.focus(convertedPoint)

    focusImageView.center = point
    UIView.animate(withDuration: 0.5, animations: { _ in
      self.focusImageView.alpha = 1
      self.focusImageView.transform = CGAffineTransform(scaleX: 0.6, y: 0.6)
      }, completion: { _ in
        self.animationTimer = Timer.scheduledTimer(timeInterval: 1, target: self,
          selector: #selector(CameraView.timerDidFire), userInfo: nil, repeats: false)
    })
  }

  // MARK: - Tap

  func tapGestureRecognizerHandler(_ gesture: UITapGestureRecognizer) {
    let touch = gesture.location(in: view)

    focusImageView.transform = CGAffineTransform.identity
    animationTimer?.invalidate()
    focusTo(touch)
  }

  // MARK: - Pinch

  func pinchGestureRecognizerHandler(_ gesture: UIPinchGestureRecognizer) {
      switch gesture.state {
      case .began:
        pivotPinchScale = cameraMan.zoomFactor()
//        print("pivotPinchScale: \(pivotPinchScale) maxZoom: \(cameraMan.maxZoomFactor())")
      case .changed:
        let newValue: CGFloat = pivotPinchScale * gesture.scale
        let factor = newValue < 1 ? 1 : newValue > maxZoomFactor ? maxZoomFactor : newValue

        if factor != cameraMan.zoomFactor() {
//          print("pinchGesture: \(gesture.scale) new: \(factor)")
          cameraMan.zoomFactor(factor)
//          NotificationCenter.default.post(name: Notification.Name(rawValue: ZoomView.Notifications.zoomValueChanged), object: self, userInfo: ["newValue": newValue])
        }
      case .failed, .ended:
        break
      default:
        break
      }
  }

  // MARK: - Private helpers

  func showNoCamera(_ show: Bool) {
    [noCameraButton, noCameraLabel].forEach {
      show ? view.addSubview($0) : $0.removeFromSuperview()
    }
  }

  // CameraManDelegate
  func cameraManNotAvailable(_ cameraMan: CameraMan) {
    showNoCamera(true)
    focusImageView.isHidden = true
    delegate?.cameraNotAvailable()
  }

  func cameraMan(_ cameraMan: CameraMan, didChangeInput input: AVCaptureDeviceInput) {
    delegate?.setFlashButtonHidden(!input.device.hasFlash)
  }

  func cameraManDidStart(_ cameraMan: CameraMan) {
    setupPreviewLayer()
  }
}
