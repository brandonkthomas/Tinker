//
//  TinkerApp.swift
//  Tinker
//
//  Created by Brandon Thomas.
//

import SwiftUI

@main
struct TinkerApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @State private var model = AppModel()

    var body: some Scene {
        Window("Tinker", id: "main") {
            ContentView(model: model)
        }
        .defaultSize(width: 900, height: 700)
    }
}
