//
//  SerializedLayer.m
//  shared_lib
//
//  Created by Sophia Wisdom on 4/19/20.
//  Copyright © 2020 Sophia Wisdom. All rights reserved.
//

#import "SerializedLayerTree.h"

#import <os/log.h>

#import <AppKit/AppKit.h>

#import <SceneKit/SceneKit.h>

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

os_log_t logger;

@implementation SerializedLayerTree {
    CALayer *_layer; // Layer if it exists
}

+ (void)load {
    logger = os_log_create("com.tweaks.injected", "SerializedLayerTree");
}

- (instancetype)initWithLayer:(CALayer *)layer {
    if (self = [super init]) {
        _layer = layer;
        _rect = [layer frame];
        id delegate = [layer delegate];
        _viewClassName = NSStringFromClass([delegate class]);
        _viewClassLocation = (__bridge void *)delegate; // for feeding into llvm etc.
        
        NSMutableArray<SerializedLayerTree *> *sublayers = [[NSMutableArray alloc] init];
        for (CALayer *sublayer in layer.sublayers) {
            SerializedLayerTree *serializedSublayer = [[SerializedLayerTree alloc] initWithLayer:sublayer];
            [sublayers addObject:serializedSublayer];
        }
        _sublayers = [NSArray arrayWithArray:sublayers];
    }
    return self;
}

// Draws rect for class in current class
- (void)drawRectFromPoint:(NSPoint)point scale:(CGFloat)scale {
    NSPoint newPoint = NSMakePoint(point.x + _rect.origin.x, point.y + _rect.origin.y);
    NSFrameRect(NSMakeRect((newPoint.x)/scale, (newPoint.y)/scale, (_rect.size.width)/scale, (_rect.size.height)/scale));
    for (SerializedLayerTree *sublayer in _sublayers) {
        [sublayer drawRectFromPoint:newPoint scale:scale];
    }
}

#pragma mark <NSSecureCoding> conformance

+ (BOOL)supportsSecureCoding {
    return true;
}

- (instancetype)initWithCoder:(NSCoder *)coder
{
    if (self = [super init]) {
        NSSet<Class> *classes = [NSSet setWithArray:@[[NSArray class], [SerializedLayerTree class]]];
        _sublayers = [coder decodeObjectOfClasses:classes forKey:@"sublayers"];
        _rect = [coder decodeRectForKey:@"rect"];
        _viewClassName = [coder decodeObjectOfClass:[NSString class] forKey:@"viewClassName"];
        _viewClassLocation = (void *)[coder decodeInt64ForKey:@"viewClassLocation"];
    }
    return self;
}

- (void)encodeWithCoder:(NSCoder *)coder {
    [coder encodeObject:_sublayers forKey:@"sublayers"];
    [coder encodeRect:_rect forKey:@"rect"];
    [coder encodeObject:_viewClassName forKey:@"viewName"];
    [coder encodeInt64:(int64_t)_viewClassLocation forKey:@"viewClassLocation"];
}

@end
