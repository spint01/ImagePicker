//
//  Test2ViewController.swift
//  ImagePicker
//
//  Created by Steven G Pint on 4/1/17.
//  Copyright © 2017 Hyper Interaktiv AS. All rights reserved.
//

import UIKit

class Test2ViewController: UIViewController {

    override func viewDidLoad() {
        super.viewDidLoad()

        let button = UIButton(frame: CGRect(x: 100, y: 200, width: 40, height: 44))
        button.addTarget(self, action: #selector(buttonTouched), for: .touchUpInside)
        view.addSubview(button)

      view.backgroundColor = UIColor.white
    }

  func buttonTouched(_ sender: Any) {
    self.dismiss(animated: true, completion: nil)
  }

  open override var prefersStatusBarHidden: Bool {
    return true
  }

  override var preferredStatusBarUpdateAnimation: UIStatusBarAnimation {
    return .fade
  }
}
