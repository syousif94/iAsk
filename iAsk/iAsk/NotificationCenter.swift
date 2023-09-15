//
//  NotificationCenter.swift
//  iAsk
//
//  Created by Sammy Yousif on 8/7/23.
//

import Combine

class NotificationPublisher<T> {
    private let subject = PassthroughSubject<T, Never>()
    
    var value: T?

    var publisher: AnyPublisher<T, Never> {
        return subject.eraseToAnyPublisher()
    }

    func send(_ value: T) {
        self.value = value
        subject.send(value)
    }
}
