#include "inject.h"
#include "symbol_locator.h"

#include <stdio.h>
#include <stdlib.h>

#import <Foundation/Foundation.h>
#import <os/log.h>
#import "INJXPCListenerDelegate.h"

#include "macho_parser/macho_parser.h"
#include "injection_interface.h"

#define MACH_CALL(kret) if (kret != 0) {\
printf("Mach call on line %d failed with error \"%s\".\n", __LINE__, mach_error_string(kret));\
exit(1);\
}

NSTimeInterval printTimeSince(NSDate *begin) {
    NSDate *injectionEnd = [NSDate date];
    return [injectionEnd timeIntervalSinceDate:begin];
}

const struct timespec one_ms = {.tv_sec = 0, .tv_nsec = 1 * NSEC_PER_MSEC};

int main(int argc, char **argv) {
    char *library = "/Users/sophiawisdom/Library/Developer/Xcode/DerivedData/mods-hiqpvfikerrvwrbgoskpjqwmglif/Build/Products/Debug/libinjected_library.dylib";
    char *shmem_symbol = "_shmem_loc";
    
    printf("Location is %s\n", argv[0]);
    
    mach_vm_offset_t shmem_sym_offset = getSymbolOffset(library, shmem_symbol); // We can't take the typical path of just
    // loading the dylib into memory and using dlsym() to get the offset because loading the dylib has side effects
    // for obvious reasons. Instead, we get the offset of the symbol from the dylib itself.
    if (!shmem_sym_offset) {
        fprintf(stderr, "Unable to get offset for symbol %s in dylib %s.\n", shmem_symbol, library);
        return 1;
    }
    
    int pid = 0;
    if (argc > 1) {
        pid = atoi(argv[1]);
    }
    if (pid == 0) {
        printf("Input PID to pause: ");
        scanf("%d", &pid);
    }
    
    NSDate *injectionBegin = [NSDate date];
    
    printf("Injecting into PID %d\n", pid);
        
    task_t remoteTask = inject(pid, library);
    if (remoteTask < 0) { // Shitty way of checking for error condition.
        fprintf(stderr, "Encountered error with injection: %d\n", remoteTask);
        return -1; // Error
    }
            
    mach_vm_address_t stringAddress = 0;
    mach_vm_allocate(remoteTask, &stringAddress, 4096, true); // Let address be relocatable
    
    // Allocate remote memory. This will be the location of the mapping in the target process
    mach_vm_address_t remoteShmemAddress = 0;
    memory_object_size_t remoteMemorySize = 0x10000000; // 256 MB, because the serialized return data can get big. For activity monitor, ~20MB
    // Also the memory won't be used unless we write to it.
    MACH_CALL(mach_vm_allocate(remoteTask, &remoteShmemAddress, remoteMemorySize, true));
    
    // Once we've created the memory, we need a handle to that memory so we can reference it in mach_vm_map.
    mach_port_t shared_memory_handle;
    MACH_CALL(mach_make_memory_entry_64(remoteTask,
                              &remoteMemorySize,
                              remoteShmemAddress, // Memory address
                              VM_PROT_READ | VM_PROT_WRITE,
                              &shared_memory_handle,
                              MACH_PORT_NULL)); // parent entry - for submaps?
        
    // Create the mapping between the objects.
    uint64_t localShmemAddress;
    // https://flylib.com/books/en/3.126.1.89/1/ has some documentation on this
    MACH_CALL(mach_vm_map(mach_task_self(),
                &localShmemAddress, // Address in this address space?
                remoteMemorySize, // size. Maybe worth allocating a direct data transfer space and then also opening a larger map?
                0xfff, // Alignment bits - make it page aligned
                true, // Anywhere bit
                shared_memory_handle,
                0,
                false, // not sure what this means
                VM_PROT_READ | VM_PROT_WRITE,
                VM_PROT_READ | VM_PROT_WRITE,
                VM_INHERIT_SHARE));
    
    unsigned long long *indicator = (unsigned long long *)localShmemAddress;
    command_in *cmd = (command_in *)(localShmemAddress+8);
    cmd -> cmd = GET_CLASSES;
    cmd -> arg = (data_out){0};
    *indicator = NEW_IN_DATA;
        
    // Getting the dylib address requires the dylib to be loaded in the target process,
    // which can take some time. The constructor itself is close to as minimal as possible
    // where we still have a foothold in the other process, but just loading it itself takes
    // time.
    int waits = 0;
    mach_vm_address_t dylib_addr = get_dylib_address(remoteTask, library);
    while ((dylib_addr = get_dylib_address(remoteTask, library)) == 0) {
        nanosleep(&one_ms, NULL);
        if (waits++ > 1500) {
            fprintf(stderr, "unable to find dylib addr after 1500ms, something is going wrong.\n");
            break;
        }
    }
    
    // Typically takes <10ms to reach this point.
        
    mach_vm_address_t shmem_sym_addr = dylib_addr + shmem_sym_offset;
    MACH_CALL(mach_vm_write(remoteTask, shmem_sym_addr, &remoteShmemAddress, sizeof(remoteShmemAddress)));
    
    // Typically takes about 300ms to get and then serialize objective-c data
    while (*indicator != NEW_OUT_DATA) {
        nanosleep(&one_ms, NULL);
    }
        
    data_out *response = (data_out *)(localShmemAddress+8);
    if (response -> shmem_offset == 0 && response -> len == 0) {
        printf("Got null response back, even though indicator is %llx\n", *indicator);
        return 1;
    }
    
    void *response_loc = localShmemAddress + response -> shmem_offset;
    // This way we're zero-copy all the way from serialization in the other process.
    // TODO: consider just mmap'ing all the objective-c runtime data in the other process into this process?
    // If they use whole pointers and not offsets, it won't match up on this side though...
    NSData *resp = [NSData dataWithBytesNoCopy:response_loc length:response -> len freeWhenDone:false];
    NSError *err = nil;
    NSSet<Class> *classes = [NSSet setWithArray:@[[NSDictionary class], [NSArray class], [NSString class]]];
    
    // This deserialization typically takes ~120ms
    printf("About to start deserialization\n");
    NSArray *result = [NSKeyedUnarchiver unarchivedObjectOfClasses:classes fromData:resp error:&err];
    printf("About to end deserialization\n");
    if (err) {
        NSLog(@"Encountered error in deserializing response dictionary: %@", err);
        return 1;
    }
    
    printf("result is of size %lu\n", [result count]);
    
    NSMutableDictionary<NSString *, NSMutableArray<NSString *> *> *classesByImage = [[NSMutableDictionary alloc] init];
    
    for (int i = 0; i < [result count]; i++) {
        NSDictionary<NSString *, id> *dict = [result objectAtIndex:i];
        NSString *name = [dict valueForKey:@"name"];
        NSString *image = [dict valueForKey:@"image"];
        if (![classesByImage objectForKey:image]) {
            [classesByImage setObject:[[NSMutableArray alloc] init] forKey:image];
        }
        [[classesByImage objectForKey:image] addObject:name];
//        NSLog(@"Following selectors are for class %@ (from image %@)", [dict valueForKey:@"name"], [dict valueForKey:@"image"]);
        NSArray *selectors = [dict valueForKey:@"selectors"];
        
//        NSLog(@"Selectors are %@", selectors);
    }
    
    NSArray *imagesBySize = [[classesByImage allKeys] sortedArrayUsingComparator:^NSComparisonResult(NSString *  _Nonnull firstImage, NSString *  _Nonnull secondImage) {
        NSInteger firstSize = [[classesByImage objectForKey:firstImage] count];
        NSInteger secondSize = [[classesByImage objectForKey:secondImage] count];
        if (firstSize > secondSize)
            return NSOrderedAscending;
        if (firstSize < secondSize)
            return NSOrderedDescending;
        return NSOrderedSame;
    }];
    
    for (NSString *image in imagesBySize) {
        NSLog(@"Image %@ has %lu classes.\n", image, [[classesByImage objectForKey:image] count]);
    }
    
    // TODO: consider adding objc_addLoadImageFunc so we can see any new images loaded? Or otherwise adding hooks
    
    return 0;
}
