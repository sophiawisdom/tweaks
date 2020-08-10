//
//  objc_runtime_getters.c
//  injected_library
//
//  Created by Sophia Wisdom on 3/10/20.
//  Copyright © 2020 Sophia Wisdom. All rights reserved.
//

#import "logging.h"
#include "objc_runtime_getters.h"

#import "internal_injection_interface.h"

#import <Foundation/Foundation.h>
#import <AppKit/AppKit.h>
#include <mach-o/dyld.h>
#import <objc/runtime.h>
#import <dlfcn.h>
#import <CoreGraphics/CoreGraphics.h>

#import "SerializedLayerTree.h"

// The reason why it's structured like this, with multiple levels to get down
// to a particular selector, is because for applications that link a lot of frameworks
// the raw size of all the data can take significant amounts of time to extract and
// serialize. Activity Monitor, for example, had some 20,000 classes ~= 20MB of data.
// Gathering and serializing this took ~1-2s. I feel it's better to have <100ms times
// for each dylib than 1-2s times to get all the data, because in the former case there
// won't be perceptible lag.

NSArray<NSString *> * get_images() {
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
    
    return images;
}

NSArray<NSString *> * get_classes_for_image(NSString *image) {
    unsigned int numClasses = 0;
    const char ** images = objc_copyClassNamesForImage([image UTF8String], &numClasses);
    os_log(logger, "Got %{public}d results back for copyClassNamesForImage on image \"%{public}s\"", numClasses, [image UTF8String]);
    
    NSMutableArray<NSString *> *classNames = [[NSMutableArray alloc] initWithCapacity:numClasses];
    for (int i = 0; i < numClasses; i++) {
        [classNames setObject:[NSString stringWithUTF8String:images[i]] atIndexedSubscript:i];
    }
    
    return classNames;
}

NSString *get_image_for_class(NSString *class) {
    Class cls = NSClassFromString(class);
    os_log(logger, "class is %{public}@ for string %{public}@", cls, class);
    const char *image = class_getImageName(cls);
    if (!image) {
        return nil;
    }
    return [NSString stringWithUTF8String:image];
}

NSString * get_superclass_for_class(NSString *className) {
    Class cls = NSClassFromString(className);
    os_log(logger, "Class is %{public}@, %{public}p", cls, cls);
    return NSStringFromClass(class_getSuperclass(cls));
}

// As of now, this only gets instance methods. TODO: handle class methods also with class_copyMethodList(object_getClass(cls), &count)
NSArray<NSDictionary *> * get_methods_for_class(NSString *className) {
    Class cls = NSClassFromString(className);
    if (cls == nil) {
        os_log_error(logger, "Unable to find class %{public}@ - got nil from NSClassFromString", className);
        return nil;
    }
    
    os_log(logger, "Getting methods for class name \"%{public}@\" class %{public}@", className, cls);
    
    // TODO: Implement getting methods of superclasses as well? For e.g. NSView or whatever.
    unsigned int numMethods = 0;
    Method * methods = class_copyMethodList(cls, &numMethods);
    
    os_log(logger, "Getting methods for class \"%{public}@\". Got back that there were %{public}d", className, numMethods);
        
    NSMutableArray<NSDictionary *> *selectors = [[NSMutableArray alloc] init];
    for (int i = 0; i < numMethods; i++) {
        struct objc_method_description *desc = method_getDescription(methods[i]);
        if (!desc -> name) {
            os_log_error(logger, "Got selector with null name");
            continue;
        }
        
        // Special destructor used for dealloc() purposes. hmm... not sure what to do if someone wants to override dealloc().
        if (strcmp(desc -> name, ".cxx_destruct") == 0) {
            continue;
        }
        uint64_t implementation = (uint64_t)method_getImplementation(methods[i]); // It's ok this is just a pointer
        // because this is all the data the objc runtime will send us anyway. If we just send the pointer over,
        // we can read the memory out on the other side and do the disassembly there.
        NSDictionary *method = @{@"sel": NSStringFromSelector(desc -> name), @"type": [NSString stringWithUTF8String:desc -> types], @"imp": @(implementation)};
        
        [selectors addObject:method];
    }
    
    os_log(logger, "Return dict for class was %{public}@", selectors);
    
    return [NSArray arrayWithArray:selectors];
}

NSArray<NSDictionary *> * get_properties_for_class(NSString *className) {
    Class cls = NSClassFromString(className);
    if (cls == nil) {
        os_log_error(logger, "Unable to find class %{public}@ - got nil from NSClassFromString", className);
        return nil;
    }
    
    unsigned int numProperties = 0;
    objc_property_t *props = class_copyPropertyList(cls, &numProperties);
    NSMutableArray<NSDictionary *> *arr = [NSMutableArray arrayWithCapacity:numProperties];
    for (int i = 0; i < numProperties; i++) {
        const char *name = property_getName(props[i]);
        if (!name) {
            os_log_error(logger, "property #%{public}d is null on class %{public}@", i, className);
            continue;
        }
        
        unsigned int numAttrs = 0;
        objc_property_attribute_t *attrs = property_copyAttributeList(props[i], &numAttrs);
        NSMutableArray<NSArray<NSString *> *> *atts = [NSMutableArray arrayWithCapacity:numAttrs];
        for (int j = 0; j < numAttrs; j++) {
            if (!attrs[j].name) {
                os_log_error(logger, "Attribute #%{public}d is null on property %{public}s", j, name);
                continue;
            }
            
            NSString *attrName = [NSString stringWithUTF8String:attrs[j].name];
            
            if (attrs[j].value) {
                [atts setObject:@[attrName, [NSString stringWithUTF8String:attrs[j].value]] atIndexedSubscript:j];
            } else {
                [atts setObject:@[attrName] atIndexedSubscript:j];
            }
        }
        
        [arr setObject:@{@"name": [NSString stringWithUTF8String:name], @"attrs": atts} atIndexedSubscript:i];
    }
    
    return arr;
}

NSString * get_executable_image() {
    unsigned int bufsize = 1024;
    char *executablePath = malloc(bufsize);
    _NSGetExecutablePath(executablePath, &bufsize);
    NSString *strWithExecutablePath = [NSString stringWithUTF8String:executablePath];
    free(executablePath);
    return strWithExecutablePath;
}

NSNumber *load_dylib(NSString *dylib) {
    void * handle = dlopen([dylib UTF8String], RTLD_NOW | RTLD_GLOBAL);
    os_log(logger, "Got back handle %{public}p. dlerror() is %{public}s", handle, dlerror());
    return [NSNumber numberWithUnsignedLong:(unsigned long)handle];
}


// Not going to handle deleting selectors... seems kinda silly. Only handle add and switch. For switch, new selector == old selector.
void switching(NSDictionary<NSString *, id> *options) {
    NSString *class = [options objectForKey:@"newClass"];
    Class newCls = NSClassFromString(class);
    
    NSArray<NSString *> * selectors = [options objectForKey:@"selectors"];
    
    Class oldCls = NSClassFromString([options objectForKey:@"oldClass"]);
        
    for (NSString *selector in selectors) {
        const char *selbytes = [selector UTF8String];
        SEL selector = sel_registerName(selbytes); // Get canonical pointer value
        Method newMeth = class_getInstanceMethod(newCls, selector); // necessary to get types
        IMP newImp = method_getImplementation(newMeth);
        if (!newImp) {
            os_log_error(logger, "No new implementation for sel %{public}s on class %{public}@", selbytes, class);
            continue;
        }
        
        class_replaceMethod(oldCls, selector, newImp, method_getTypeEncoding(newMeth));
    }
}

// Takes NSArray<NSDictionary<NSString *, id> *>
NSString *replace_methods(NSArray<NSDictionary<NSString *, id> *> *switches) {
    for (NSDictionary *params in switches) {
        switching(params);
    }
    
    return @"successful";
}

NSArray<NSView *> *getOccurencesOfClassInSubviews(Class cls, NSView *view) {
    NSMutableArray<NSView *> *arr = [[NSMutableArray alloc] init];
    os_log(logger, "subviews of %{public}@ are %{public}@", view, [view subviews]);
    for (NSView *subview in [view subviews]) {
        os_log(logger, "found subview %@ of class %@", subview, [subview class]);
        if ([subview isKindOfClass:cls]) {
            [arr addObject:subview];
        }
        [arr addObjectsFromArray:getOccurencesOfClassInSubviews(cls, subview)];
    }
    return arr;
}

void turnBackgroundGreen(NSView *view) {
    NSColor *green = [NSColor colorWithCalibratedRed:0.0 green:1.0 blue:0.0 alpha:1.0f];
    [view layer].backgroundColor = [green CGColor];
    [view display];
    [view updateLayer];
}

NSArray<NSView *> *spiderView(NSView *view) {
    NSValue *packedParentPosition = (NSValue *)objc_getAssociatedObject([view superview], 691214);
    CGPoint parentPosition;
    [packedParentPosition getValue:&parentPosition];
    CGPoint myRelativePosition = [[view layer] position];
    CGPoint myPosition = {.x = parentPosition.x + myRelativePosition.x, .y = parentPosition.y + myRelativePosition.y};
    
    objc_setAssociatedObject(view, 691214, [NSValue valueWithBytes:&myPosition objCType:@encode(CGPoint)], OBJC_ASSOCIATION_COPY_NONATOMIC);
    NSMutableArray<NSView *> *views = [[NSMutableArray alloc] initWithArray:[view subviews]];
    for (NSView *subview in [view subviews]) {
        [views addObjectsFromArray:spiderView(subview)];
    }
    return views;
}

// if this become bottleneck, you could pass a single NSMutableArray reference throughout
NSArray<CALayer *> *spider_layers(CALayer *layer) {
    NSMutableArray<CALayer *> *layers = [[NSMutableArray alloc] initWithArray:@[layer]];
    NSArray<CALayer *> *sublayers = layer.sublayers;
    for (unsigned int i = 0; i < sublayers.count; i++) {
        CALayer *subLayer = [sublayers objectAtIndex:i];
        [layers addObjectsFromArray:spider_layers(subLayer)];
    }
    return layers;
}

CALayer *get_main_layer() {
    NSApplication *app = [NSApplication sharedApplication];
    return app.windows.firstObject.contentView.superview.layer; // [app mainWindow] and [app keyWindow] are often null
}

NSArray<NSString *> *get_layer_images() {
    NSArray<CALayer *> *layers = get_layers();
    NSMutableSet<NSString *> *images = [[NSMutableSet alloc] init];
    for (CALayer *layer in layers) {
        [images addObject:get_image_for_class(NSStringFromClass([layer class]))];
    }
    return [images allObjects];
}

NSArray<CALayer *> *get_layers() {
    return spider_layers(get_main_layer());
}

SerializedLayerTree *get_serialized_layers() {
    [NSGraphicsContext saveGraphicsState];
    SerializedLayerTree *tree = [[SerializedLayerTree alloc] initWithLayer:get_main_layer()];
    [NSGraphicsContext restoreGraphicsState];
    return tree;
}

NSArray<NSArray<id> *> *getIvars(NSString *class) {
    Class cls = NSClassFromString(class);
        
    unsigned int outCount = 0;
    Ivar *ivars = class_copyIvarList(cls, &outCount);
    NSMutableArray<NSArray<id> *> *arr = [NSMutableArray arrayWithCapacity:outCount];
    for (int i = 0; i < outCount; i++) {
        NSString *name = [NSString stringWithUTF8String:ivar_getName(ivars[i])];
        NSString *typeEncoding = [NSString stringWithUTF8String:ivar_getTypeEncoding(ivars[i])];
        NSNumber *offset = @(ivar_getOffset(ivars[i]));
        [arr setObject:@[name, typeEncoding, offset] atIndexedSubscript:i];
    }
    
    return arr;
}

NSData *get_window_picture() {
    uint64_t window_number = [[[[NSApplication sharedApplication] windows] firstObject] windowNumber];
    CGImageRef img = CGWindowListCreateImage(CGRectNull, kCGWindowListOptionIncludingWindow, window_number, kCGWindowImageBoundsIgnoreFraming);
    if (img == nil) { // sometimes possible. not sure what causes it but simple check
        return nil;
    }
    return [[[NSBitmapImageRep alloc] initWithCGImage:img] TIFFRepresentationUsingCompression:NSTIFFCompressionLZW factor:2];
}

NSValue *get_window_size() {
    return [NSValue valueWithSize:get_main_layer().preferredFrameSize];
}

static jmp_buf inv_buf;

void handle_segv(int sig) {
    // As far as I can tell, the question of exactly what functions
    // can be called in an async function is difficult to answer WRT
    // POSIX. However, we should be safe as long as execute_invocation
    // is not being called during exit() or the like (an unlikely scenario).
    longjmp(inv_buf, 1);
}

id execute_invocation(NSInvocation * pointer) {
    // The signal() and setjmp() stuff is necessary because if the NSInvocation's target is nonexistent,
    // this could throw off a SEGSEGV, which would crash the process.
    // I'm not very familiar with unix signal handling, so extra comments
    // to make things clear.
    
    // Here we say that when a SIGSEGV happens, call handle_segv.
    signal(SIGSEGV, handle_segv);
    
    // This setjmp() is crucial, because after the signal handler is completed,
    // execution will continue *at the same pc*, so there's no opportunity to
    // check or things like this.
    // setjmp() will first return 0, and then when it is longjmp() is called
    // with the same jmp_buf argument, it will return the second longjmp() parameter.
    id retval = nil;
    if (!setjmp(inv_buf)) {
        [pointer invoke]; // In the case that this errors, handle_segv is called, which then
        // brings us back to our setjmp() call, but this time `errored` is true, so we skip
        // running this again and just return `nil`.
        [pointer getReturnValue:&retval];
    }
    
    // SIG_DFL == 0, and just works as a signal to set it back to whatever it was before.
    signal(SIGSEGV, SIG_DFL);
    return retval;
}
