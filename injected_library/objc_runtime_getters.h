//
//  objc_runtime_getters.h
//  injected_library
//
//  Created by Sophia Wisdom on 3/10/20.
//  Copyright © 2020 Sophia Wisdom. All rights reserved.
//

#ifndef objc_runtime_getters_h
#define objc_runtime_getters_h

#include <stdio.h>
#import <Foundation/Foundation.h>

NSData * get_images(void);
NSData * get_classes_for_image(NSData *serializedImage);
NSData * get_selectors_for_class(NSData *serializedClass);
NSData * get_classes(void);

#endif /* objc_runtime_getters_h */
