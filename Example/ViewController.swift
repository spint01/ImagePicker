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

  override func viewDidLoad() {
    super.viewDidLoad()
  }

  @IBAction func ImagePickerButtonTouched(_ sender: Any) {
    Configuration.collapseCollectionViewWhileShot = false

    let ctr = ImagePickerController()
    ctr.delegate = self
    present(ctr, animated: true, completion: nil)
  }
}

extension ViewController: ImagePickerDelegate {

  func wrapperDidPress(_ imagePicker: ImagePickerController, images: [UIImage]) {

  }
  
  func doneButtonDidPress(_ imagePicker: ImagePickerController, images: [UIImage]) {
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

      imagePicker.present(alert, animated: false, completion: nil)
    }
  }
}

