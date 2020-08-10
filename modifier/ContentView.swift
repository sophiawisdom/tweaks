//
//  ContentView.swift
//  modifier
//
//  Created by Sophia Wisdom on 8/10/20.
//  Copyright © 2020 Sophia Wisdom. All rights reserved.
//

import SwiftUI

struct ContentView: View {
    @State private var pid: pid_t = 0
    
    var body: some View {
        VStack {
            AppInputView()
        }.frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}


struct ContentView_Previews: PreviewProvider {
    static var previews: some View {
        ContentView()
    }
}
