//
//  injected_library.m
//  injected_library
//
//  Created by Sophia Wisdom on 2/29/20.
//  Copyright © 2020 Sophia Wisdom. All rights reserved.
//

#import <Foundation/Foundation.h>
#import <os/log.h>
#import "InjectedXPCDelegate.h"

#include <time.h>

void * endpoint_loc = NULL;
uint64_t endpoint_len = 0;

void async_main() {
    printf("Code run with dispatch_async\n");
    
    NSXPCListener *listener = [NSXPCListener anonymousListener];
    InjectedXPCDelegate *delegate = [[InjectedXPCDelegate alloc] init];
    listener.delegate = delegate;
    NSXPCListenerEndpoint *endpoint = listener.endpoint;

    NSError *error = nil;
    NSData *data = [[[NSXPCCoder alloc] init] encodeXPCObject:endpoint forKey:@"endpoint"];
    if (error) {
        NSLog(@"Got error when archiving endpoint: %@", error);
    }
    
    endpoint_loc = (void *) [data bytes];
    endpoint_len = [data length];
    printf("Wrote data to endpoint_loc (%p) and endpoint_len (%llx)\n", endpoint_loc, endpoint_len);
    
    [listener resume];
}

__attribute__((constructor))
void bain() { // big guy, etc.
    // If we do something like sleep() during the constructor phase, the dylib is never considered loaded into the process.
    dispatch_queue_t new_queue = dispatch_queue_create("injected_queue", DISPATCH_QUEUE_SERIAL);
    dispatch_async(new_queue, ^{
        async_main();
    });
}
