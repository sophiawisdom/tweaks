//
//  INJXPCListenerDelegate.m
//  daemon
//
//  Created by Sophia Wisdom on 3/3/20.
//  Copyright © 2020 Sophia Wisdom. All rights reserved.
//

#import "INJXPCListenerDelegate.h"
#import <os/log.h>

@implementation INJXPCListenerDelegate

- (BOOL)listener:(NSXPCListener *)listener shouldAcceptNewConnection:(NSXPCConnection *)newConnection {
    os_log(OS_LOG_DEFAULT, "Accepting new connection %@", newConnection);
    return true;
}

@end
