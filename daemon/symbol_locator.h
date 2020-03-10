//
//  symbol_locator.h
//  daemon
//
//  Created by Sophia Wisdom on 2/29/20.
//  Copyright © 2020 Sophia Wisdom. All rights reserved.
//

#ifndef symbol_locator_h
#define symbol_locator_h

#include <stdio.h>
#include <mach/mach_types.h>
#import <Foundation/Foundation.h>

// Caller must free this when done
struct dyld_image_info * get_dylibs(task_t task, int *size);
mach_vm_address_t get_dylib_address(task_t task, char *dylib);
mach_vm_address_t get_symbol(struct dyld_image_info * dylibs, int size, char *dylib, char *symbol);
NSArray<NSString *> *getApplicationImages(task_t task);

#endif /* symbol_locator_h */
