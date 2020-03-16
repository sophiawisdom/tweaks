//
//  main.m
//  testing_target
//
//  Created by Sophia Wisdom on 3/16/20.
//  Copyright © 2020 Sophia Wisdom. All rights reserved.
//

#import <Foundation/Foundation.h>

#import "tobeinjected.h"

const struct timespec half_s = {.tv_sec=0, .tv_nsec = NSEC_PER_MSEC*500};

int main(int argc, const char * argv[]) {
    @autoreleasepool {
        counter *counter = [[counter alloc] init];
        for (;;) {
            NSLog(@"Counter is %d", [counter getValue]);
            nanosleep(&half_s, NULL);
        }
    }
    return 0;
}
