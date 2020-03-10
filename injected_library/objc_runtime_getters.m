//
//  objc_runtime_getters.c
//  injected_library
//
//  Created by Sophia Wisdom on 3/10/20.
//  Copyright © 2020 Sophia Wisdom. All rights reserved.
//

#import "logging.h"
#include "objc_runtime_getters.h"

#import <objc/runtime.h>

// The reason why it's structured like this, with multiple levels to get down
// to a particular selector, is because for applications that link a lot of frameworks
// the raw size of all the data can take significant amounts of time to extract and
// serialize. Activity Monitor, for example, had some 20,000 classes ~= 20MB of data.
// Gathering and serializing this took ~1-2s. I feel it's better to have <100ms times
// for each dylib than 1-2s times to get all the data, because in the former case there
// won't be perceptible lag.

NSData * get_images() {
    unsigned int numImages = 0;
    const char * _Nonnull * _Nonnull classes = objc_copyImageNames(&numImages);
    if (!classes) {
        os_log_error(logger, "Unable to get image names");
        return nil;
    }
    
    NSMutableArray<NSString *> *images = [NSMutableArray arrayWithCapacity:numImages];
    for (int i = 0; i < numImages; i++) {
        [images setObject:[NSString stringWithUTF8String:classes[i]] atIndexedSubscript:i];
    }

    free(classes);
    
    NSError *err = nil;
    NSData * archivedImages = [NSKeyedArchiver archivedDataWithRootObject:images requiringSecureCoding:false error:&err];
    if (err) {
        os_log_error(logger, "encountered error when archiving images: %@", err);
        return nil;
    }
    return archivedImages;
}

NSData * get_classes_for_image(NSData *serializedImage) {
    NSError *err = nil;
    NSString *image = [NSKeyedUnarchiver unarchivedObjectOfClass:[NSString class] fromData:serializedImage error:&err];
    if (err) {
        os_log_error(logger, "encountered error when deserializing arg for get_classes_for_image: %@", err);
    }
    
    unsigned int numClasses = 0;
    const char ** images = objc_copyClassNamesForImage([image UTF8String], &numClasses);
    
    NSMutableArray<NSString *> *classNames = [[NSMutableArray alloc] initWithCapacity:numClasses];
    for (int i = 0; i < numClasses; i++) {
        [classNames setObject:[NSString stringWithUTF8String:images[i]] atIndexedSubscript:i];
    }
    
    NSData * archivedClasses = [NSKeyedArchiver archivedDataWithRootObject:classNames requiringSecureCoding:false error:&err];
    if (err) {
        os_log_error(logger, "encountered error when archiving classes: %@", err);
        return nil;
    }
    return archivedClasses;
}

NSData * get_superclass_for_class(NSData *serializedClass) {
    NSError *err = nil;
    NSString *className = [NSKeyedUnarchiver unarchivedObjectOfClass:[NSString class] fromData:serializedClass error:&err];
    if (err) {
        os_log_error(logger, "encountered error when deserializing serializedClass for get_superclass_for_class: %@", err);
    }

    Class superClass = class_getSuperclass(NSClassFromString(className));

    NSData * archivedSuperclass = [NSKeyedArchiver archivedDataWithRootObject:NSStringFromClass(superClass) requiringSecureCoding:false error:&err];
    if (err) {
        os_log_error(logger, "encountered error when archiving selectors for get_superclass_for_class: %@", err);
        return nil;
    }
    return archivedSuperclass;
}

NSData * get_methods_for_class(NSData *serializedClass) {
    NSError *err = nil;
    NSString *className = [NSKeyedUnarchiver unarchivedObjectOfClass:[NSString class] fromData:serializedClass error:&err];
    if (err) {
        os_log_error(logger, "encountered error when deserializing serializedClass for get_methods_for_class: %@", err);
    }
    
    // TODO: Implement getting methods of superclasses as well? For e.g. NSView or whatever.
    
    unsigned int numMethods = 0;
    Method *methods = class_copyMethodList(NSClassFromString(className), &numMethods);
    
    NSMutableArray<NSDictionary *> *selectors = [[NSMutableArray alloc] initWithCapacity:numMethods];
    for (int i = 0; i < numMethods; i++) {
        struct objc_method_description *desc = method_getDescription(methods[i]);
        uint64_t implementation = (uint64_t)method_getImplementation(methods[i]); // It's ok this is just a pointer
        // because this is all the data the objc runtime will send us anyway. If we just send the pointer over,
        // we can read the memory out on the other side and do the disassembly there.
        NSDictionary *method = @{@"sel": NSStringFromSelector(desc -> name), @"type": [NSString stringWithUTF8String:desc -> types], @"imp": @(implementation)};
        
        [selectors setObject:method atIndexedSubscript:i];
    }
    
    NSData * archivedSelectors = [NSKeyedArchiver archivedDataWithRootObject:selectors requiringSecureCoding:false error:&err];
    if (err) {
        os_log_error(logger, "encountered error when archiving selectors for get_methods_for_class: %@", err);
        return nil;
    }
    return archivedSelectors;
}
