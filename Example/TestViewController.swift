//
//  TestViewController.swift
//  ImagePicker
//
//  Created by Steven G Pint on 4/1/17.
//  Copyright © 2017 Hyper Interaktiv AS. All rights reserved.
//

import UIKit

class TestViewController: UIViewController {

  var statusBarHidden = true

    override func viewDidLoad() {
        super.viewDidLoad()

      self.view.backgroundColor = UIColor.white
      navigationController?.setNavigationBarHidden(true, animated: false)
    }

    @IBAction func dismissTouched(_ sender: Any) {
        self.dismiss(animated: true, completion: nil)
    }

  open override func viewWillAppear(_ animated: Bool) {
    super.viewWillAppear(animated)

    statusBarHidden = UIApplication.shared.isStatusBarHidden
    UIApplication.shared.setStatusBarHidden(true, with: .fade)
  }

//  override func viewDidAppear(_ animated: Bool) {
//    super.viewDidAppear(animated)
//
//    statusBarHidden = true
//    setNeedsStatusBarAppearanceUpdate()
//  }

  open override func viewWillDisappear(_ animated: Bool) {
    super.viewWillDisappear(animated)
    UIApplication.shared.setStatusBarHidden(statusBarHidden, with: .fade)
  }

  open override var prefersStatusBarHidden: Bool {
      return statusBarHidden
  }

  override var preferredStatusBarUpdateAnimation: UIStatusBarAnimation {
    return .fade
  }
}
