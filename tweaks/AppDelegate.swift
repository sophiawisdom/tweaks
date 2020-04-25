//
//  AppDelegate.swift
//  tweaks
//
//  Created by Sophia Wisdom on 4/1/20.
//  Copyright © 2020 Sophia Wisdom. All rights reserved.
//

import Cocoa
import SwiftUI

func getCalendarApp() -> NSRunningApplication? {
    let apps = NSWorkspace.shared.runningApplications
    // var calendarApp? = nil
    for app in apps {
        if app.bundleIdentifier == "com.apple.iCal" {
            return app
        }
    }
    
    return nil
}

@NSApplicationMain
class AppDelegate: NSObject, NSApplicationDelegate {

    var window: NSWindow!


    func applicationDidFinishLaunching(_ aNotification: Notification) {
        guard let calendar = getCalendarApp() else {
            print("unable to find calendar app")
            return
        }
        print("my pid is \(getpid())")
        print("calendar is \(calendar), pid is \(calendar.processIdentifier)")
        guard let proc = TWEProcess(pid: calendar.processIdentifier) else {
            print("oh no, proc is nil!")
            return
        }
        let tree = proc.get_layers()!
        print("tree is \(tree)")
        // Create the SwiftUI view that provides the window contents.
        let contentView = ContentView(tree: tree)

        // Create the window and set the content view. 
        window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 480, height: 300),
            styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
            backing: .buffered, defer: false)
        window.center()
        window.setFrameAutosaveName("Main Window")
        window.contentView = NSHostingView(rootView: contentView)
        window.makeKeyAndOrderFront(nil)
    }

    func applicationWillTerminate(_ aNotification: Notification) {
        // Insert code here to tear down your application
    }


}

