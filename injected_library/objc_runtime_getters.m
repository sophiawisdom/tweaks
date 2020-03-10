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

NSData * get_selectors_for_class(NSData *serializedClass) {
    NSError *err = nil;
    NSString *className = [NSKeyedUnarchiver unarchivedObjectOfClass:[NSString class] fromData:serializedClass error:&err];
    if (err) {
        os_log_error(logger, "encountered error when deserializing serializedClass for get_selectors_for_class: %@", err);
    }
    
    // TODO: Implement getting methods of superclasses as well? For e.g. NSView or whatever.
    
    unsigned int numMethods = 0;
    Method *methods = class_copyMethodList(NSClassFromString(className), &numMethods);
    
    NSMutableArray<NSString *> *selectors = [[NSMutableArray alloc] initWithCapacity:numMethods];
    for (int i = 0; i < numMethods; i++) {
        SEL selector = method_getName(methods[i]);
        [selectors setObject:NSStringFromSelector(selector) atIndexedSubscript:i];
    }
    
    NSData * archivedSelectors = [NSKeyedArchiver archivedDataWithRootObject:selectors requiringSecureCoding:false error:&err];
    if (err) {
        os_log_error(logger, "encountered error when archiving selectors: %@", err);
        return nil;
    }
    return archivedSelectors;
}

NSData * set_methods(NSData *dat) {
    return nil;
}

NSData * get_classes() {
    unsigned int numClasses = 0;
    Class * classes = objc_copyClassList(&numClasses);
    os_log(logger, "Got %d classes\n", numClasses);
    // This ends up requiring an individual mach_vm_read for every class. In the future (and/or now)
    // it would be better to just get all the class names (and maybe methods?) and put them in a single
    // contiguous block.
    
    // class_copyMethodList and class_getName and method_getDescription. Potentially also get ivars/properties/weak ivars/protocols.
    
    /*Class *contiguousClasses = (__bridge Class *) malloc(sizeof(Class) * count);
    for (int i = 0; i < count; i++) {
        memcpy(&contiguousClasses[i], &classes[i], sizeof(Class));
        contiguousClasses[i];
    }*/
    
    NSMutableArray<NSDictionary *> *class_data = [[NSMutableArray alloc] initWithCapacity:numClasses];
    for (int i = 0; i < numClasses; i++) {
        Class cls = classes[i];
        
        NSString *name = [NSString stringWithUTF8String:class_getName(cls)];
        const char *c_name = class_getImageName(cls);
        if (!c_name) {
            os_log(logger, "Encountered class %s with null image name.", class_getName(cls));
            c_name = "(null)";
        }
        NSString *imageName = [NSString stringWithUTF8String:c_name];
        
        // Consider doing same with protocols/properties/ivars
        unsigned int numMethods = 0;
        Method * methods = class_copyMethodList(cls, &numMethods); // Does not look at superclasses
        NSMutableArray<NSString *> *selectorList = [[NSMutableArray alloc] initWithCapacity:numMethods];
        for (int j = 0; j < numMethods; j++) {
            SEL selector = method_getName(methods[j]);
            if (selector == nil) {
                os_log_error(logger, "Got null selector, idk what this means. class is %@", name);
                continue;
            }
            [selectorList setObject:NSStringFromSelector(selector) atIndexedSubscript:j];
        }
        
        [class_data setObject:@{@"selectors": selectorList, @"name":name, @"image":imageName} atIndexedSubscript:i];
    }
    
    NSError *err = nil;
    NSData *serialized_classes = [NSKeyedArchiver archivedDataWithRootObject:class_data requiringSecureCoding:false error:&err];
    if (err) {
        os_log_error(logger, "Got error archiving class data: %@", err);
        return nil;
    }
    
    os_log(logger, "serialized classes is of size %lu", [serialized_classes length]);
    
    // When will serialized_classes get freed? Not to worry now, but TODO: look for memory leaks. probably several.
    // does/can autoreleasing know about data in structs?
    
    return serialized_classes;
}
