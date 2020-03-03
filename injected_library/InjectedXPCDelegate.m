//
//  InjectedXPCDelegate.m
//  injected_library
//
//  Created by Sophia Wisdom on 3/1/20.
//  Copyright © 2020 Sophia Wisdom. All rights reserved.
//

#import "InjectedXPCDelegate.h"

@implementation InjectedXPCDelegate

- (instancetype)init
{
    self = [super init];
    if (self) {
    }
    return self;
}

- (BOOL)listener:(NSXPCListener *)listener shouldAcceptNewConnection:(NSXPCConnection *)newConnection {
    NSLog(@"Got a request to connect to listener %@ from connection %@", listener, newConnection);
    return true;
}
@end
