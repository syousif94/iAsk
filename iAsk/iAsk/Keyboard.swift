//
//  Keyboard.swift
//  iAsk
//
//  Created by Sammy Yousif on 8/8/23.
//

import Combine
import SwiftUI
import UIKit

class KeyboardObserver: ObservableObject {
    @Published var isKeyboardVisible = false
    var cancellables = Set<AnyCancellable>()

    init() {
        NotificationCenter.default.publisher(for: UIResponder.keyboardWillShowNotification)
            .sink { _ in
                withAnimation {
                    self.isKeyboardVisible = true
                }
            }
            .store(in: &cancellables)

        NotificationCenter.default.publisher(for: UIResponder.keyboardWillHideNotification)
            .sink { _ in
                withAnimation {
                    DispatchQueue.main.async {
                        self.isKeyboardVisible = false
                    }
                }
            }
            .store(in: &cancellables)
    }
}

extension UIApplication {
    func endEditing() {
        sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
    }
}

class KeyboardAnimation {
    let duration: TimeInterval
    let options: UIView.AnimationOptions

    init?(notification: Notification) {
        guard let userInfo = notification.userInfo,
              let duration = userInfo[UIResponder.keyboardAnimationDurationUserInfoKey] as? TimeInterval,
              let curve = userInfo[UIResponder.keyboardAnimationCurveUserInfoKey] as? UInt else {
            return nil
        }

        self.duration = duration
        self.options = UIView.AnimationOptions(rawValue: curve)
    }
}

class KeyboardManager {
    var cancellables = Set<AnyCancellable>()
    var keyboardInfoPublisher: AnyPublisher<(CGFloat, KeyboardAnimation?), Never>!

    init() {
        let willShowPublisher = NotificationCenter.default.publisher(for: UIResponder.keyboardWillShowNotification)
            .map { notification -> (CGFloat, KeyboardAnimation?) in
                let height = (notification.userInfo?[UIResponder.keyboardFrameEndUserInfoKey] as? CGRect)?.height ?? 0
                let animation = KeyboardAnimation(notification: notification)
                return (height, animation)
            }

        let willHidePublisher = NotificationCenter.default.publisher(for: UIResponder.keyboardWillHideNotification)
            .map { notification in
                return (CGFloat(0), KeyboardAnimation(notification: notification))
            }
        
        keyboardInfoPublisher = Publishers.Merge(willShowPublisher, willHidePublisher)
            .eraseToAnyPublisher()
    }

    func observeKeyboardChanges(callback: @escaping ((CGFloat, KeyboardAnimation?) -> Void)) {
        keyboardInfoPublisher
            .sink { info in
                callback(info.0, info.1)
            }
            .store(in: &cancellables)
    }
}
