//
//  Process.h
//  daemon
//
//  Created by Sophia Wisdom on 3/14/20.
//  Copyright © 2020 Sophia Wisdom. All rights reserved.
//

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@class SerializedLayerTree;

@interface TWEProcess : NSObject

//
- (nullable instancetype)initWithPid:(pid_t)pid;

// For everything that takes a class parameter as a string, nil will be returned if the class can't be found.
// TODO: better error handling

// Gets all images loaded into the target process
// Binding for objc_copyImageNames()
- (NSArray<NSString *> *)getImages;

// Gets the executable image for the target process
// Binding for _NSGetExecutablePath()
- (NSString *)getExecutableImage;

// Gets all the classes contained in a particular image
// Binding for objc_copyClassNamesForImage()
- (nullable NSArray<NSString *> *)getClassesForImage:(NSString *)image;

// Gets all methods for a particular classes.
// Dictionary keys are "sel" for the selector, "type" for the objc method description (incl. types),
// "imp" for the location of the implementation start in the process' address space.
- (nullable NSArray<NSDictionary<NSString *, NSString *> *> *)getMethodsForClass:(NSString *)className;

// Gets the superclass for a class.
// Binding for class_getSuperclass()
- (nullable NSString *)getSuperclassForClass:(NSString *)className;

//
- (nullable NSArray<NSDictionary *> *)getPropertiesForClass:(NSString *)className;

// This is basically a simple binding for dlopen(dylib, RTLD_NOW | RTLD_GLOBAL)
- (NSNumber *)load_dylib:(NSString *)dylib;

// This replaces all the methods
- (NSString *)replace_methods:(NSArray<NSDictionary<NSString *, id> *> *)switches;

// This gets all the ivars on the class. This is basically a binding for class_copyIvarList.
- (NSArray<NSArray *> *)get_ivars:(NSString *)cls;

// This gets the executable image a certain class is in.
- (NSString *)get_image_for_class:(NSString *)cls;

// This draws the entire UI in the target process and then sends it over. This is very slow and inefficient
//
- (void)draw_layers;

- (nullable SerializedLayerTree *)get_layers;

@end

NS_ASSUME_NONNULL_END
