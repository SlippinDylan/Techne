//
//  AppNotifications.swift
//  DevNexus
//
//  Created by SlippinDylan on 2026/3/12.
//

import Foundation

extension Notification.Name {
    static let devServerProcessStarted = Notification.Name("devServerProcessStarted")
    static let devServerStopped = Notification.Name("devServerStopped")
    static let browserDidOpen = Notification.Name("browserDidOpen")
}
