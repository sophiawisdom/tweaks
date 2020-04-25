//
//  SerializedLayer.h
//  shared_lib
//
//  Created by Sophia Wisdom on 4/19/20.
//  Copyright © 2020 Sophia Wisdom. All rights reserved.
//

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@class NSBitmapImageRep;
@class CALayer;
@class NSGraphicsContext;

@interface SerializedLayerTree : NSObject <NSSecureCoding>

@property NSBitmapImageRep *img;
//@property NSIndexPath *path;
@property NSRect rect;
@property NSArray<SerializedLayerTree *> *sublayers;

- (instancetype)initWithLayer:(CALayer *)layer;

//- (void)renderInRect:(NSRect)rect;

- (void)renderAtPoint:(NSPoint)point;

@end

NS_ASSUME_NONNULL_END
