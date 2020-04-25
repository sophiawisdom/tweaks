//
//  symbol_locator.c
//  daemon
//
//  Created by Sophia Wisdom on 2/29/20.
//  Copyright © 2020 Sophia Wisdom. All rights reserved.
//

#include "symbol_locator.h"

#include <mach/mach_types.h>
#include <dlfcn.h>
#include <mach-o/dyld_images.h>
#include <sys/syslimits.h>
#include <stdlib.h>

#import <Foundation/Foundation.h>

#define MACH_CALL(kret, critical) if (kret != 0) {\
printf("Mach call on line %d failed with error \"%s\".\n", __LINE__, mach_error_string(kret));\
if (critical) {exit(1);}\
}

unsigned char * readProcessMemory (task_t task, mach_vm_address_t addr, mach_msg_type_number_t *size) {
    vm_offset_t readMem;
    // Use vm_read, rather than mach_vm_read, since the latter is different
    // in iOS.
    
    MACH_CALL(vm_read(task,          // vm_map_t target_task,
                 addr,               // mach_vm_address_t address,
                 *size,              // mach_vm_size_t size
                 &readMem,           // vm_offset_t *data,
                 size), TRUE);       // mach_msg_type_number_t *dataCnt
    // TODO: This fails on Safari? Not known why.

    return ( (unsigned char *) readMem);

}

long get_symbol_offset(const char *dylib_path, const char *symbol_name) {
    void *handle = dlopen(dylib_path, RTLD_NOW);
    void *sym_loc = dlsym(handle, symbol_name);
    Dl_info info;
    int result = dladdr(sym_loc, &info);
    if (result == 0) {
        printf("dladdr call failed: %d\n", result);
        return -1;
    }
    dlclose(handle);
    
    return sym_loc - info.dli_fbase;
}

mach_vm_address_t find_dylib(struct dyld_image_info * dyld_image_info, int size, const char *image_name) {
    for (int i = 0; i < size; i++) {
        if (strcmp(image_name, dyld_image_info[i].imageFilePath) == 0) {
            return (mach_vm_address_t) dyld_image_info[i].imageLoadAddress;
        }
    }
    return -1;
}

struct dyld_image_info * get_dylibs(task_t task, int *size) {
    task_dyld_info_data_t task_dyld_info;
    mach_msg_type_number_t count = TASK_DYLD_INFO_COUNT;
    
    MACH_CALL(task_info(task, TASK_DYLD_INFO, (task_info_t)&task_dyld_info, &count), FALSE);
    // If you call task_info with the TASK_DYLD_INFO flavor, it'll give you information about dyld - specifically, where is the struct
    // that lists out the location of all the dylibs in the other process' memory. I think this can eventually be painfully discovered
    // using mmap, but this way is much easier.
    
    unsigned int dyld_all_image_infos_size = sizeof(struct dyld_all_image_infos);
    
    // Every time there's a pointer, we have to read out the resulting data structure.
    struct dyld_all_image_infos *dyldaii = (struct dyld_all_image_infos *) readProcessMemory(task, task_dyld_info.all_image_info_addr, &dyld_all_image_infos_size);
    
    
    int imageCount = dyldaii->infoArrayCount;
    mach_msg_type_number_t dataCnt = imageCount * sizeof(struct dyld_image_info);
    struct dyld_image_info * dii = (struct dyld_image_info *) readProcessMemory(task, (mach_vm_address_t) dyldaii->infoArray, &dataCnt);
    if (!dii) { return NULL;}

    // This one will only have images with a name
    struct dyld_image_info *images = (struct dyld_image_info *) malloc(dataCnt);
    int images_index = 0;
    
    for (int i = 0; i < imageCount; i++) {
        dataCnt = PATH_MAX;
        char *imageName = (char *) readProcessMemory(task, (mach_vm_address_t) dii[i].imageFilePath, &dataCnt);
        if (imageName) {
            images[images_index].imageFilePath = imageName;
            images[images_index].imageLoadAddress = dii[i].imageLoadAddress;
            images_index++;
        }
    }
    
    // In theory we should be freeing dii and dyldaii, but it's not malloc'd, so I'd need to use mach_vm_deallocate or something, which I don't care about.
    // This function probably leaks memory, but I'm not super sure.
    
    *size = images_index;
    
    return images;
}

NSArray<NSString *> *getApplicationImages(task_t task) {
    int size = 0;
    struct dyld_image_info * dylibs = get_dylibs(task, &size);
    NSMutableArray<NSString *> *applicationImages = [[NSMutableArray alloc] init];
    for (int i = 0; i < size; i++) {
        NSString *filepath = [NSString stringWithUTF8String:dylibs[i].imageFilePath];
        NSString *testingFilepath = [filepath lowercaseString];
        if ([testingFilepath hasPrefix:@"/usr/lib"] || // /usr/lib/libSystem.b.dylib for example
            [testingFilepath hasPrefix:@"/system/library"] || // /system/library/frameworks + /system/library/privateframeworks
            [testingFilepath hasSuffix:@"libinjected_library.dylib"]) {
            continue;
        }
        [applicationImages addObject:filepath];
    }
    return applicationImages;
}

mach_vm_address_t get_dylib_address(task_t task, char *dylib) {
    int size = 0;
    struct dyld_image_info * dylibs = get_dylibs(task, &size);
    mach_vm_address_t addr = find_dylib(dylibs, size, dylib);
    if (addr == -1) {
        return 0;
    }
    free(dylibs);
    return addr;
}

// This will only function correctly if DYLD_LIBRARY_PATH is set to
// /Users/sophiawisdom/Library/Developer/Xcode/DerivedData/mods-hiqpvfikerrvwrbgoskpjqwmglif/Build/Products/Debug:/usr/lib/system
mach_vm_address_t get_symbol(struct dyld_image_info * dylibs, int size, char *dylib, char *symbol) {
    mach_vm_address_t dylib_address = find_dylib(dylibs, size, dylib);
    if (dylib_address == -1) {
        printf("Getting address of dylib %s failed\n", dylib);
        return 0;
    }
    
    long offset = get_symbol_offset(dylib, symbol);
    printf("dylib_address was %p and offset was %ld for symbol %s and dylib %s\n", dylib_address, offset, symbol, dylib);
    return dylib_address + offset;
}
