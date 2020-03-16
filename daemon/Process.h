//
//  Process.h
//  daemon
//
//  Created by Sophia Wisdom on 3/14/20.
//  Copyright © 2020 Sophia Wisdom. All rights reserved.
//

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@interface Process : NSObject

- (instancetype)initWithPid:(pid_t)pid;

- (NSArray<NSString *> *)getImages;
- (NSString *)getExecutableImage;
- (nullable NSArray<NSString *> *)getClassesForImage:(NSString *)image;
- (nullable NSArray<NSString *> *)getMethodsForClass:(NSString *)className;
- (nullable NSString *)getSuperclassForClass:(NSString *)className;
- (nullable NSArray<NSDictionary *> *)getPropertiesForClass:(NSString *)className;
- (NSNumber *)load_dylib:(NSString *)dylib;
- (NSString *)replace_methods:(NSArray<NSDictionary<NSString *, id> *> *)switches;

@end

NS_ASSUME_NONNULL_END
