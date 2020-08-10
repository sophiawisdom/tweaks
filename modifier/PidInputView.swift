//
//  AppInputView.swift
//  modifier
//
//  Created by Sophia Wisdom on 8/10/20.
//  Copyright © 2020 Sophia Wisdom. All rights reserved.
//

import SwiftUI
import Combine

// For just getting raw PIDs the best way is to use the BSD APIs:
// https://stackoverflow.com/questions/37512486/osx-proc-pidinfo-returns-0-for-other-users-processes

struct PidInputView: View {
    @State private var pid_str: String = ""
    @State private var pid_num: pid_t = 0
    
    var body: some View {
        VStack {
            TextField("Enter your name", text: $pid_str)
                .foregroundColor(self.pid_num == -1 ? Color.red : Color.green)
                .onReceive(Just(pid_str)) { (newValue) in
                    guard let num = Int32(newValue) else {
                        self.pid_num = -1;
                        return
                    }
                    print("succeeded")
                    self.pid_num = num;
                    self.pid_str = newValue
            }
        }
    }
}

struct PidInputView_Previews: PreviewProvider {
    static var previews: some View {
        AppInputView()
    }
}
