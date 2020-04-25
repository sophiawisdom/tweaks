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

- (instancetype)initWithImg:(NSBitmapImageRep *)img rect:(NSRect)rect {
    if (self = [super init]) {
        self.img = img;
//        self.path = path;
        self.rect = rect;
    }
    return self;
}

- (instancetype)initWithLayer:(CALayer *)layer {
    if (self = [super init]) {
        _layer = layer;
        _img = [self _drawLayer];
        _rect = [layer frame];
        NSMutableArray<SerializedLayerTree *> *sublayers = [[NSMutableArray alloc] init];
        for (CALayer *sublayer in layer.sublayers) {
            if ([self _isOkLayer:sublayer]) {
                SerializedLayerTree *serializedSublayer = [[SerializedLayerTree alloc] initWithLayer:sublayer];
                [sublayers addObject:serializedSublayer];
            }
        }
        _sublayers = [NSArray arrayWithArray:sublayers];
    }
    return self;
}

- (bool)_isOkLayer:(CALayer *)layer {
    NSSize frameSize = [layer frame].size;
    
    if (frameSize.width * frameSize.height == 0) {
        os_log_debug(logger, "rejecting layer %@ because width or height is 0", layer);
        return NO;
    }
    
    if (frameSize.height > 10000 || frameSize.width > 10000) {
        // Ok so i never quite got why this was but sometimes there are layers that are really big,
        // like width and height each 2^20 or width 2^22. Trying to draw & serialize those layers
        // gums up the works and makes the process take 20x longer. If we just skip them, nothing
        // much is really missed and now this way of doing it is viable.
        // os_log_info(logger, "encountered really weird layer %{public}@. Layer has frame %{public}@. sublayers are: %{public}@", _layer, CGRectCreateDictionaryRepresentation(_layer.frame), _layer.sublayers);
        os_log_debug(logger, "rejecting layer %@ because width or height is >10k", layer);
        return NO;
    }
    
    if (layer.hidden) {
        os_log_debug(logger, "rejecting layer %@ because layer is hidden", layer);
        return NO;
    }

    return YES;
}

- (NSBitmapImageRep *)_drawLayer {
    NSSize frameSize = [_layer frame].size;
    
    NSBitmapImageRep *img = emptyImageForDrawing(frameSize);
    NSGraphicsContext *context = [NSGraphicsContext graphicsContextWithBitmapImageRep:img];
    [NSGraphicsContext setCurrentContext:context];
    
    if (_layer.contentsAreFlipped) {
        CGAffineTransform reverseFlip = CGAffineTransformMake(1, 0, 0, -1, 0, frameSize.height);
        CGContextConcatCTM(context.CGContext, reverseFlip);
    }
    
    [_layer drawInContext:context.CGContext];
    [context flushGraphics];
    
    return img;
}

- (void)renderAtPoint:(NSPoint)point {
    point.x += _rect.origin.x;
    point.y += _rect.origin.y;
    /*
    NSPoint ourPoint = _rect.origin;
    NSRect ourRect = _rect;
    ourRect.origin.x += rect.origin.x;
    ourRect.origin.y += rect.origin.y;
    [_img drawInRect:ourRect];*/
    [_img drawAtPoint:point];
    for (SerializedLayerTree *subtree in _sublayers) {
        [subtree renderAtPoint:point];
        // [subtree renderInRect:ourRect];
    }
}

#pragma mark <NSSecureCoding> conformance

+ (BOOL)supportsSecureCoding {
    return true;
}

- (instancetype)initWithCoder:(NSCoder *)coder
{
    if (self = [super init]) {
        self.img = [NSBitmapImageRep imageRepWithData:[coder decodeObjectOfClass:[NSData class] forKey:@"img"]];
        NSSet<Class> *classes = [NSSet setWithArray:@[[NSArray class], [SerializedLayerTree class]]];
        self.sublayers = [coder decodeObjectOfClasses:classes forKey:@"sublayers"];
        self.rect = [coder decodeRectForKey:@"rect"];
    }
    return self;
}

- (void)encodeWithCoder:(NSCoder *)coder {
    [coder encodeObject:[self.img TIFFRepresentationUsingCompression:NSTIFFCompressionLZW factor:2] forKey:@"img"];
    [coder encodeObject:self.sublayers forKey:@"sublayers"];
    [coder encodeRect:self.rect forKey:@"rect"];
}

@end
