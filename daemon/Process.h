//
//  Process.h
//  daemon
//
//  Created by Sophia Wisdom on 3/14/20.
//  Copyright © 2020 Sophia Wisdom. All rights reserved.
//

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN


// Dirty hack
#ifndef injected_library_h

typedef enum {
    NO_COMMAND,
    GET_IMAGES,
    GET_CLASSES_FOR_IMAGE,
    GET_METHODS_FOR_CLASS,
    GET_SUPERCLASS_FOR_CLASS,
    GET_EXECUTABLE_IMAGE
} command_type;

#endif

@interface Process : NSObject

- (instancetype)initWithPid:(pid_t)pid;

- (NSArray<NSString *> *)getImages;
- (NSString *)getExecutableImage;
- (NSArray<NSString *> *)getClassesForImage:(NSString *)image;
- (NSArray<NSString *> *)getMethodsForClass:(NSString *)className;
- (NSString *)getSuperclassForClass:(NSString *)className;

@end

NS_ASSUME_NONNULL_END
