//
//  SerializedLayer.h
//  shared_lib
//
//  Created by Sophia Wisdom on 4/19/20.
//  Copyright © 2020 Sophia Wisdom. All rights reserved.
//

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@class CALayer;
@class NSGraphicsContext;
@class SCNNode;

@interface SerializedLayerTree : NSObject <NSSecureCoding>

@property(readonly) NSRect rect;
@property(readonly) NSString *viewClassName;
@property(readonly) void *viewLocation;
@property(readonly) NSArray<SerializedLayerTree *> *sublayers;

- (instancetype)initWithLayer:(CALayer *)layer;

- (void)drawRectFromPoint:(NSPoint)point scale:(CGFloat)scale;

- (void)drawRectWithContext:(CGContextRef)ref fromPoint:(NSPoint)point;

@end

NS_ASSUME_NONNULL_END
