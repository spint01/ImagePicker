//
//  ViewController.swift
//  Example
//
//  Created by Steven G Pint on 12/10/16.
//

import UIKit
import Photos
import ImagePicker

class ViewController: UIViewController {

  var selectedAssets: [PHAsset]?

  override func viewDidLoad() {
    super.viewDidLoad()

//    self.extendedLayoutIncludesOpaqueBars = true
  }

  @IBAction func ImagePickerButtonTouched(_ sender: Any) {
    var config = Configuration()
    config.collapseCollectionViewWhileShot = false
    config.selectedPhotoImage = getImageWithColorBorder(color: UIColor.blue, size: CGSize(width: 20, height: 20))
    config.preselectedAssets = selectedAssets

    let ctr = ImagePickerController(configuration: config)
    ctr.delegate = self
//    ctr.modalPresentationCapturesStatusBarAppearance = true
    present(ctr, animated: true, completion: nil)
  }

  func getImageWithColorBorder(color: UIColor, size: CGSize) -> UIImage {
    let rect = CGRect(x: 0, y: 0, width: size.width, height: size.height)
    UIGraphicsBeginImageContextWithOptions(size, false, 0)
    color.setStroke()
    UIRectFrame(rect)
    let image: UIImage = UIGraphicsGetImageFromCurrentImageContext()!
    UIGraphicsEndImageContext()
    return image
  }
}

extension ViewController: ImagePickerDelegate {

  func wrapperDidPress(_ imagePicker: ImagePickerController, images: [UIImage]) {

  }
  
  func doneButtonDidPress(_ imagePicker: ImagePickerController, images: [UIImage]) {
    selectedAssets = imagePicker.stack.assets

    dismiss(animated: true, completion: nil)
  }

  func cancelButtonDidPress(_ imagePicker: ImagePickerController) {
    dismiss(animated: true, completion: nil)
  }

  func photoAdded(_ imagePicker: ImagePickerController, photo: PHAsset) {
    print("added photo")
    DispatchQueue.main.async {
      let alert = UIAlertController(title: "Added Photo", message: photo.description, preferredStyle: .alert)
      alert.addAction(UIAlertAction(title: "OK", style: .default, handler: nil))

      alert.view.transform = Helper.rotationTransform()
      imagePicker.present(alert, animated: false, completion: nil)
    }
  }
}

