//
//  ContentView.swift
//  tweaks
//
//  Created by Sophia Wisdom on 4/1/20.
//  Copyright © 2020 Sophia Wisdom. All rights reserved.
//

import SwiftUI
import Combine


struct ContentView: View {
    let tree: SerializedLayerTree
    let window: NSBitmapImageRep
    let windowSize: CGSize
    
    var body: some View {
        ImageView(tree: tree, windowImg: window, windowSize: windowSize)
        // Image(window.cgImage!, scale: 4, label: Text("window"))
    }
}


/*
struct ContentView_Previews: PreviewProvider {
    static var previews: some View {
        ContentView(tree: nil, window:nil)
    }
}
 */
