//
//  objc_runtime_getters.c
//  injected_library
//
//  Created by Sophia Wisdom on 3/10/20.
//  Copyright © 2020 Sophia Wisdom. All rights reserved.
//

#import "logging.h"
#include "objc_runtime_getters.h"

#import <Foundation/Foundation.h>
#import <AppKit/AppKit.h>
#include <mach-o/dyld.h>
#import <objc/runtime.h>
#import <dlfcn.h>
#import <CoreGraphics/CoreGraphics.h>

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

NSBitmapImageRep * emptyImageForDrawing(CGSize size) {
    return [[NSBitmapImageRep alloc]
     initWithBitmapDataPlanes:NULL
     pixelsWide:size.width
     pixelsHigh:size.height
     bitsPerSample:8
     samplesPerPixel:4 // with alpha this needs to be 4
     hasAlpha:YES
     isPlanar:NO
     colorSpaceName:NSDeviceRGBColorSpace
     bytesPerRow:0
     bitsPerPixel:0];
}

NSString *print_windows() {
    setenv("CG_CONTEXT_SHOW_BACKTRACE", "true", 1);
    
    NSApplication *app = [NSApplication sharedApplication];
    os_log(logger, "Main window is %{public}@, key window is %{public}@", [app mainWindow], [app keyWindow]);
    
    os_log(logger, "image is %{public}@", emptyImageForDrawing((CGSize){.height=100, .width=200}));
    
    for (NSWindow *window in [app windows]) {
        NSView *mainView = [[window contentView] superview];
        
        os_log(logger, "main content scale is %f", [[mainView layer] contentsScale]);
        
        CGPoint myPosition = [[mainView layer] position];
        objc_setAssociatedObject(mainView, 691214, [NSValue valueWithBytes:&myPosition objCType:@encode(CGPoint)], OBJC_ASSOCIATION_COPY_NONATOMIC);
        
        NSArray<NSView *> * views = spiderView(mainView);
        // views = [views subarrayWithRange:NSMakeRange(0, 50)];
                        
        CGImageRef image = CGWindowListCreateImage(CGRectNull, kCGWindowListOptionIncludingWindow, (CGWindowID)[window windowNumber], kCGWindowImageBoundsIgnoreFraming);
        NSImage *img = [[NSImage alloc] initWithCGImage:image size:NSZeroSize];
        
        NSMutableArray<NSValue *> *rects = [[NSMutableArray alloc] initWithCapacity:views.count];
        
        NSMutableArray<NSBitmapImageRep *> *reps = [[NSMutableArray alloc] init];
        NSMutableArray<NSData *> *datas = [[NSMutableArray alloc] init];
        
        NSMutableSet<Class> *classes = [[NSMutableSet alloc] init];
        // possibly would be better to iterate through all classes to see if they are subclasses...
        Class cls = [NSTextField class];
        
        struct timeval start, end;
        gettimeofday(&start, NULL);
        
        [NSGraphicsContext saveGraphicsState];
        
        for (NSView *view in views) {
            // os_log(logger, "Got view %{public}@", view);
            if ([[view class] isSubclassOfClass:cls]) {
                [classes addObject:[view class]];
            }
            
            NSSize frameSize = [view frame].size;
            if (frameSize.width * frameSize.height == 0) {
                continue;
            }
            
            /*
            NSRect rect = [view frame]; // also plausible - [view visibleArea]
            NSBitmapImageRep *cachedView = [view bitmapImageRepForCachingDisplayInRect:rect];
            
            // in a sane world, we would be using [NSView cacheDisplayInRect:toBitmapImageRep:]
            // However, that calls (through a sequence of things) -[NSView _layoutSubtreeIfNeededAndAllowTemporaryEngine:]
            // and because we are not on the main thread we cannot do UI work (like layout subtrees).
            
            [view setNeedsLayout:NO];
            [view cacheDisplayInRect:rect toBitmapImageRep:cachedView];
            [reps addObject:cachedView];
            continue;
             */
                        
            os_log(logger, "width is %f, height is %f", frameSize.width, frameSize.height);
            NSBitmapImageRep *rep = emptyImageForDrawing(frameSize);
            os_log(logger, "created rep %{public}@", rep);
            // there are more efficient ways of doing this...
            NSMutableData *dat = [[NSMutableData alloc] initWithCapacity:1024*1024*64/*frameSize.width*frameSize.height*8*/];
            os_log(logger, "allocated data %{public}@", dat);
            NSGraphicsContext *context = [NSGraphicsContext graphicsContextWithAttributes:@{
                NSGraphicsContextDestinationAttributeName: dat,
                NSGraphicsContextRepresentationFormatAttributeName: NSGraphicsContextPDFFormat
            }];
            os_log(logger, "graphics context is %{public}@", context);
            // NSGraphicsContext *context = [NSGraphicsContext graphicsContextWithBitmapImageRep:rep];
            [NSGraphicsContext setCurrentContext:context];
            
            /*
             let transform = NSAffineTransform()
             transform.translateX(by: flipHorizontally ? size.width : 0, yBy: flipVertically ? size.height : 0)
             transform.scaleX(by: flipHorizontally ? -1 : 1, yBy: flipVertically ? -1 : 1)
             transform.concat()
             */
            
            NSAffineTransform *flipTransform = [[NSAffineTransform alloc] init];
            [flipTransform translateXBy:frameSize.width yBy:0];
            [flipTransform scaleXBy:-1 yBy:1];
            [flipTransform concat];
            [[view layer] drawInContext:context.CGContext];
            
            [context flushGraphics];
            os_log(logger, "just wrote to mutable data: %{public}@", dat);
            [reps addObject:rep];

            gettimeofday(&start, NULL);
            // unsigned char *rawBitmapData = [rep bitmapData];
            // NSData *bitmapData = [[NSData alloc] initWithBytesNoCopy:rawBitmapData length:4*frameSize.width*frameSize.height freeWhenDone:false];
            os_log(logger, "sending back data %{public}@ (bitmap data isn't)", dat);
            
            os_log(logger, "reps is about to add object %{public}@", rep);
            [reps addObject:rep];
            
            NSValue *packedPosition = (NSValue *)objc_getAssociatedObject([view superview], 691214);
            CGPoint pos;
            [packedPosition getValue:&pos];
            
            CGRect viewRect = [view frame];
            viewRect.origin = (CGPoint){.x = viewRect.origin.x + pos.x, .y = viewRect.origin.y + pos.y};
            float scale = [[view layer] contentsScale];
            viewRect.origin = (CGPoint){.x = viewRect.origin.x*[[view layer] contentsScale], .y=viewRect.origin.y*[[view layer] contentsScale]};
            viewRect.size = (CGSize){.width=viewRect.size.width *[[view layer] contentsScale], .height=viewRect.size.height*[[view layer] contentsScale]};
            
            [rects addObject:[NSValue valueWithRect:viewRect]];
                        
            os_log(logger, "[[view layer] class] is %{public}@", [[view layer] class]);
            // [view layer].backgroundColor = CGColorCreateGenericRGB(1, 0, 0, 1);
             
            /*
            if ([view isKindOfClass:[NSTextField class]]) {
                NSTextField *control = (NSTextField *)view;
                [control setStringValue:@"penis"];
              // running twice causes crash, i think because it tries to deallocate a constant string?
            }*/
        }
        
        [NSGraphicsContext restoreGraphicsState];
        
        gettimeofday(&end, NULL);
        float diff = (end.tv_usec - start.tv_usec) + ((end.tv_sec - start.tv_sec)*1000000);
        diff /= 1000000;
        os_log(logger, "Took %f seconds to get all reps", diff);
        
        // NSData *result = [NSBitmapImageRep representationOfImageRepsInArray:reps usingType:NSBitmapImageFileTypePNG properties:nil];
        gettimeofday(&start, NULL);
        unsigned long long sz = 0;
        for (NSData *dat in datas) {
            sz += [dat length];
        }
        gettimeofday(&end, NULL);
        diff = (end.tv_usec - start.tv_usec) + ((end.tv_sec - start.tv_sec)*1000000);
        diff /= 1000000;
        os_log(logger, "Took %f seconds to get all tiff datas. total size is %llu", diff, sz);
        
        /*
        // NSData *dat = [NSBitmapImageRep representationOfImageRepsInArray:reps usingType:NSBitmapImageFileTypeTIFF properties:nil];
        NSData *dat = [NSBitmapImageRep TIFFRepresentationOfImageRepsInArray:reps usingCompression:NSTIFFCompressionLZW factor:2];
         */
        return @"hey!";
        //os_log(logger, "sending back data %{public}@", dat);
        // return dat;
        
        unsigned long long size = 0;
        for (NSData *dat in reps) {
            size += [dat length];
        }
        
        os_log(logger, "size is %{public}llu", size);
        
        mach_vm_address_t addr;
        // mach_vm_allocate(mach_task_self(), &addr, size+4096, <#int flags#>)
        
        return reps;
        
        os_log(logger, "classes are %{public}@", classes);
        
        os_log(logger, "rects are %{public}@", rects);
        
        NSImage *imgWithFrames = [NSImage imageWithSize:[img size] flipped:false drawingHandler:^BOOL(NSRect dstRect) {
            [img drawInRect:dstRect];
            
            for (NSValue *rect in rects) {
                NSRect r = [rect rectValue];
                NSFrameRect(r);
            }
            
            return YES;
        }];
        
        os_log(logger, "image %{public}@", imgWithFrames);
        
        NSBitmapImageRep *rep = (NSBitmapImageRep *)[imgWithFrames.representations firstObject];
        
        os_log(logger, "rep %{public}@. planar is %{public}d. numberOfPlanes is %{public}ld", rep, rep.planar, rep.numberOfPlanes);
        
        while (imgWithFrames.representations.count > 1) {
            [imgWithFrames removeRepresentation:[imgWithFrames.representations lastObject]];
            [imgWithFrames removeRepresentation:[imgWithFrames.representations lastObject]];
        }
        
        os_log(logger, "image %{public}@", imgWithFrames);
        
        return [imgWithFrames.representations firstObject];
        
        os_log(logger, "image %{public}@", imgWithFrames);
        NSData *tiffData = [imgWithFrames TIFFRepresentation];
        int fd = open("window.tiff", O_WRONLY | O_CREAT);

        os_log(logger, "Error is %{public}s", strerror(errno));
        write(fd, [tiffData bytes], [tiffData length]);
        close(fd);
    }
    
    return @"successful";
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

/*
id callMethod(NSDictionary *options) {
    NSNumber *objNum = [options objectForKey:@"target"];
    void * objPtr = [objNum unsignedLongValue];
    id obj = (__bridge id)objPtr;
    SEL *selector = sel_registerName([[options objectForKey:@"selector"] UTF8String]);
    
    [obj performSelector:selector];
}
 */
