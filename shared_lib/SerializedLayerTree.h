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

@property NSRect rect;
@property NSString *viewClassName;
@property void *viewClassLocation;
@property NSArray<SerializedLayerTree *> *sublayers;

- (instancetype)initWithLayer:(CALayer *)layer;

- (void)drawRectFromPoint:(NSPoint)point scale:(CGFloat)scale;

@end

NS_ASSUME_NONNULL_END
