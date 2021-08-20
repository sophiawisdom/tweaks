//
//  ContentView.swift
//  modifier
//
//  Created by Sophia Wisdom on 8/10/20.
//  Copyright © 2020 Sophia Wisdom. All rights reserved.
//

import SwiftUI
import AppKit

struct ContentView: View {
    @State private var pid: pid_t = 0
    @State private var currentApp:pid_t?
    
    var body: some View {
        VStack {
            AppInputView(currentApp: $currentApp)
            if currentApp != nil {
                Text("current app is \(currentApp!)")
            } else {
                Text("no current app yet")
            }
        }.frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}


struct ContentView_Previews: PreviewProvider {
    static var previews: some View {
        ContentView()
    }
}
