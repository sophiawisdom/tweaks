//
//  injected_library.h
//  daemon
//
//  Created by Sophia Wisdom on 3/1/20.
//  Copyright © 2020 Sophia Wisdom. All rights reserved.
//

#ifndef injected_library_h
#define injected_library_h

void * data_loc;
uint64_t diff_indicator; // When this value changes, there is new data in data_loc.
uint64_t update_received; // When this value changes, the injected library has recognized the new value.

#endif /* injected_library_h */
