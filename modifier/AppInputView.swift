//
//  AppInputView.swift
//  modifier
//
//  Created by Sophia Wisdom on 8/10/20.
//  Copyright © 2020 Sophia Wisdom. All rights reserved.
//

import SwiftUI
import Combine
import AppKit

struct AppInputView: View {
    @State private var selectedApp: Int = -1
    @ObservedObject var appObserver = Apps()
    
    var body: some View {
        VStack {
            Picker(selection: $selectedApp, label: Text("Choose an app, bitch!!! cunt!!!")) {
                ForEach(appObserver.apps, id: \.self) { app in
                     HStack {
                        Image(nsImage: app.icon!).scaledToFit()
                        Text(app.localizedName!)
                     }.tag(self.appObserver.apps.firstIndex(of: app)!) // hate this. from here: https://stackoverflow.com/questions/57305372/why-does-binding-to-the-picker-not-work-anymore-in-swiftui
                }
            }
                        
            if (selectedApp != -1) {
                Text("You picked \(appObserver.apps[selectedApp].localizedName!)")
            }
        }
    }
}

class Apps: ObservableObject {
    @Published var apps: [NSRunningApplication] = []
    
    func getApps() -> [NSRunningApplication] {
        return NSWorkspace.shared.runningApplications.filter({ (app) -> Bool in
            app.activationPolicy == .regular
        })
    }
    
    init() {
        self.apps = self.getApps()
        NSWorkspace.shared.notificationCenter.addObserver(forName: NSWorkspace.didTerminateApplicationNotification, object: nil, queue: nil) { (notif) in
            self.apps = self.getApps()
        }
        NSWorkspace.shared.notificationCenter.addObserver(forName: NSWorkspace.didLaunchApplicationNotification, object: nil, queue: nil) { (notif) in
            self.apps = self.getApps()
        }
    }
}

struct AppInputView_Previews: PreviewProvider {
    static var previews: some View {
        AppInputView()
    }
}
