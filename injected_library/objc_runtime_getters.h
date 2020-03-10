//
//  objc_runtime_getters.h
//  injected_library
//
//  Created by Sophia Wisdom on 3/10/20.
//  Copyright © 2020 Sophia Wisdom. All rights reserved.
//

#ifndef objc_runtime_getters_h
#define objc_runtime_getters_h

#include <stdio.h>
#import <Foundation/Foundation.h>

/**
 * This file is for bindings between the objective c runtime and the shim XPC API.
 */

// TODO: add some kind of method to do several of these at once guided by predicates

// Returns NSArray<NSString *> * where strings are image names for process
NSData * get_images(void);

// Returns NSArray<NSString *> * where strings are class names for given image.
// takes serialized NSString *
NSData * get_classes_for_image(NSData *serializedImage);

// Returns NSArray<NSDictionary *> *, where the array is for each method on the class
// (not on the superclass) and the NSDictionary has three keys:
// 1: @"sel" - the selector for that method
// 2: @"type" - the objective c type string
// 3: @"imp" - the pointer to the implementation for that method. The end is not given
// by the objective-c runtime and must be determined by looking at the output.
NSData * get_methods_for_class(NSData *serializedClass);

// Get superclass for class. Takes NSString * class name and returns NSString * superclass name.
NSData * get_superclass_for_class(NSData *serializedClass);

#endif /* objc_runtime_getters_h */
