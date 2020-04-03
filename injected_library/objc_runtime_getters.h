//
//  objc_runtime_getters.h
//  injected_library
//
//  Created by Sophia Wisdom on 3/10/20.
//  Copyright © 2020 Sophia Wisdom. All rights reserved.
//

#include <stdio.h>
#import <Foundation/Foundation.h>

/**
 * This file is bound to the Process API. It represents bindings between the Process API and <objc/runtime.h>
 */

// TODO: add some kind of method to do several of these at once guided by predicates

// Returns NSArray<NSString *> * where strings are image names for process
NSArray<NSString *> * get_images(void);

// Returns NSArray<NSString *> * where strings are class names for given image.
// takes serialized NSString *
NSArray<NSString *> * get_classes_for_image(NSString *image);

// Returns NSArray<NSDictionary *> *, where the array is for each method on the class
// (not on the superclass) and the NSDictionary has three keys:
// 1: @"sel" - the selector for that method
// 2: @"type" - the objective c type string
// 3: @"imp" - the pointer to the implementation for that method. The end is not given
// by the objective-c runtime and must be determined by looking at the output.
NSArray<NSDictionary<NSString *, id> *> * get_methods_for_class(NSString *serializedClass);

// Get superclass for class. Takes NSString * class name and returns NSString * superclass name.
NSString * get_superclass_for_class(NSString *className);

NSString * get_executable_image(void);

NSNumber *load_dylib(NSString *dylib);

NSString *replace_methods(NSArray<NSDictionary<NSString *, id> *> *switches);

NSArray<NSDictionary *> * get_properties_for_class(NSString *className);

NSString *print_windows(void);

NSArray<NSArray<id> *> *getIvars(NSString *class);
