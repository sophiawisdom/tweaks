//
//  injected_library.h
//  daemon
//
//  Created by Sophia Wisdom on 3/1/20.
//  Copyright © 2020 Sophia Wisdom. All rights reserved.
//

#ifndef injected_library_h
#define injected_library_h

struct injection_struct {
    void * data_loc;
    uint64_t data_len;
    uint64_t data_indicator;
};

struct injection_struct injection_in; // Host process to target
struct injection_struct injection_out; // Target process to host (response) 

NSString *command_key = @"command";
NSString *get_classes_key = @"get_classes";

#endif /* injected_library_h */
