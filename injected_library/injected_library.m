//
//  injected_library.m
//  injected_library
//
//  Created by Sophia Wisdom on 2/29/20.
//  Copyright © 2020 Sophia Wisdom. All rights reserved.
//

#import <Foundation/Foundation.h>

#include <time.h>

void * data_loc = NULL;
uint64_t diff_indicator = 0; // When this value changes, there is new data in data_loc.
uint64_t update_received = 0; // When this value changes, the injected library has recognized the new value.

void async_main() {
    printf("Code run with dispatch_async\n");
    
    while (1) {
        if (update_received == diff_indicator || data_loc == NULL) {
            struct timespec one_ms = {.tv_sec = 0, .tv_nsec=NSEC_PER_MSEC};
            nanosleep(&one_ms, NULL); // Ideally not too high CPU usage.
            continue;
        }
        
        // new value
        printf("New data value: \"%s\"\n", data_loc);
        update_received = diff_indicator;
    }
}

__attribute__((constructor))
void bain() { // big guy, etc.
    // If we do something like sleep() during the constructor phase, the dylib is never considered loaded into the process.
    dispatch_queue_t new_queue = dispatch_queue_create("injected_queue", DISPATCH_QUEUE_SERIAL);
    dispatch_async(new_queue, ^{
        async_main();
    });
}
