//
//  Process.h
//  daemon
//
//  Created by Sophia Wisdom on 3/14/20.
//  Copyright © 2020 Sophia Wisdom. All rights reserved.
//

#import <Foundation/Foundation.h>
#import "injection_interface.h"

NS_ASSUME_NONNULL_BEGIN

@interface Process : NSObject

- (instancetype)initWithPid:(pid_t)pid;

- (NSData *)sendCommand:(command_type)cmd withArg:(nullable id)arg;

@end

NS_ASSUME_NONNULL_END
