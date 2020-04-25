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
    let tree: SerializedLayerTree?
    
    var body: some View {
        ScenekitView(tree: tree)
    }
}


struct ContentView_Previews: PreviewProvider {
    static var previews: some View {
        ContentView(tree: nil)
    }
}
