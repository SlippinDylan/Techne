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
    static let browserInstancesChanged = Notification.Name("browserInstancesChanged")
    static let switchToDevEnvironment = Notification.Name("switchToDevEnvironment")
    static let switchToMiniApp = Notification.Name("switchToMiniApp")
    static let addDevProject = Notification.Name("addDevProject")
    static let addMiniAppProject = Notification.Name("addMiniAppProject")
    static let switchToADBDeploy = Notification.Name("switchToADBDeploy")
}
