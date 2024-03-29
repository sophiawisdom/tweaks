//
//  Process.m
//  daemon
//
//  Created by Sophia Wisdom on 3/14/20.
//  Copyright © 2020 Sophia Wisdom. All rights reserved.
//

#import <sys/time.h>
#import "TWEProcess.h"
#include "macho_parser.h"
#include "inject.h"
#import "internal_injection_interface.h"
#include "symbol_locator.h"
#include <dlfcn.h>

#import "SerializedLayerTree.h"

#include <mach-o/dyld_images.h>

#import <AppKit/AppKit.h>

// This is to get around sandboxing restrictions
char *library = "/usr/lib/injected/libinjected_library.dylib";
char *shmem_symbol = "_shmem_loc";

#define MACH_CALL(kret) if (kret != 0) {\
printf("Mach call on line %d of file %s failed with error #%d \"%s\".\n", __LINE__, __FILE__, kret, mach_error_string(kret));\
return nil;\
}

const struct timespec one_ms = {.tv_sec = 0, .tv_nsec = 1 * NSEC_PER_MSEC};

@implementation TWEProcess {
    task_t _remoteTask; // task port
    uint64_t _localShmemAddress; // shmem address on our side
    uint64_t _remoteShmemAddress; // shmem address on other side
    mach_port_t _shared_memory_handle; // handle for mach_vm_allocate()'d memory in remote process
    semaphore_t _sem; // semaphore used for communication
    mach_vm_address_t _dylib_addr; // Location of dylib on other side
}

- (instancetype)initWithPid:(pid_t)pid {
    self = [super init];
    if (!self) {
        return nil;
    }
        
    // It's a little bit inefficient to run this every time, but this should be run pretty rarely.
    mach_vm_offset_t shmem_sym_offset = getSymbolOffset(library, shmem_symbol); // We can't take the typical path of just
    // loading the dylib into this process and using dlsym() to get the offset because loading the dylib has side effects
    // for obvious reasons. Instead, we get the offset of the symbol from the dylib itself.
    if (!shmem_sym_offset) {
        fprintf(stderr, "Unable to get offset for symbol %s in dylib %s.\n", shmem_symbol, library);
        return nil;
    }
    
    mach_error_t kr = task_for_pid(mach_task_self(), pid, &_remoteTask);
    printf("task_for_pid for pid %d returns %d. remote task is %d\n", pid, kr, _remoteTask);
    if (kr != KERN_SUCCESS) {
        if (getuid() != 0) {
            fprintf(stderr, "task_for_pid call failed (error %s) due to not running as root. euid is %d", mach_error_string(kr), getuid());
        }
        fprintf(stderr, "Unable to call task_for_pid on pid %d: %s. Cannot continue!\n", pid, mach_error_string(kr));
        return nil;
    }
    
    MACH_CALL(semaphore_create(mach_task_self(), &_sem, SYNC_POLICY_FIFO, 0));
    kr = mach_port_insert_right(_remoteTask,
                           SEM_PORT_NAME, // Static port name (in header). This will be how the target task can access the semaphore.
                                          // In theory this could collide with an existing one but in practice this is unlikely.
                           _sem,
                           MACH_MSG_TYPE_COPY_SEND); // Semaphores give a send right (b/c receive in kernel)
    printf("initial insert attempt return %s %d\n", mach_error_string(kr), kr, KERN_NAME_EXISTS);

    if (kr == KERN_NAME_EXISTS) {
        mach_port_destroy(_remoteTask, SEM_PORT_NAME);
        kr = mach_port_insert_right(_remoteTask,
                               SEM_PORT_NAME, // Static port name (in header). This will be how the target task can access the semaphore.
                                              // In theory this could collide with an existing one but in practice this is unlikely.
                               _sem,
                               MACH_MSG_TYPE_COPY_SEND);
    }
    // What is the difference between destroy and destruct? unsure

    if (kr == KERN_NAME_EXISTS) { // "name exists" i.e. we have already injected into this process
        fprintf(stderr, "We have already injected into this process. injecting twice isn't supported yet\n");
        return nil;
    }
    MACH_CALL(kr);

    kr = inject(_remoteTask, library);
    // From this point, the process is running
    if (kr != 0) {
        fprintf(stderr, "Encountered error with injection: %s\n", mach_error_string(kr));
        return nil; // Error
    }
    
    // Allocate memory in the target process's address space. This memory will later be mapped
    // into our process as well to establish direct data transfer.
    _remoteShmemAddress = 0;
    memory_object_size_t remoteMemorySize = MAP_SIZE; // variable because we have to pass pointers to it
    MACH_CALL(mach_vm_allocate(_remoteTask, &_remoteShmemAddress, remoteMemorySize, true));
    
    // mach_vm_map takes memory handles (ports), not raw addresses, so we need to get
    // a handle to the memory we just allocated.
    _shared_memory_handle = MACH_PORT_NULL;
    MACH_CALL(mach_make_memory_entry_64(_remoteTask,
                              &remoteMemorySize,
                              _remoteShmemAddress, // Memory we're getting a handle for
                              VM_PROT_READ | VM_PROT_WRITE,
                              &_shared_memory_handle,
                              MACH_PORT_NULL)); // parent entry - for submaps?
    
    // Create the mapping between the memory we just allocated in the remote process
    // and our process.
    _localShmemAddress = 0;
    // https://flylib.com/books/en/3.126.1.89/1/ has some documentation on this
    MACH_CALL(mach_vm_map(mach_task_self(),
                &_localShmemAddress, // Address in this address space
                remoteMemorySize,
                0xfff, // Alignment bits - make it page aligned
                true, // Anywhere bit
                _shared_memory_handle,
                0,
                false, // not sure what this means
                VM_PROT_READ | VM_PROT_WRITE,
                VM_PROT_READ | VM_PROT_WRITE,
                VM_INHERIT_SHARE));
    
    // Getting the dylib address requires the dylib to be loaded in the target process,
    // which can take some time. The constructor itself is close to as minimal as possible
    // where we still have a foothold in the other process, but just loading it itself takes
    // time.
    int waits = 0;
    _dylib_addr = 0;
    while ((_dylib_addr = get_dylib_address(_remoteTask, library)) == 0) {
        [self sleepOneMs];
        if (waits++ > 1500) {
            fprintf(stderr, "unable to find dylib addr after 1500ms, something is going wrong.\n");
            return nil;
        }
    }
    
    // This is a working heuristic for now but doesn't work necessarily. Some applications have libraries that are
//     separate from the main binary but form most of the stuff that matters.
//    NSArray<NSString *> * applicationImages = getApplicationImages(remoteTask);
//    NSLog(@"Found application images: %@", applicationImages);
    
    // Typically takes <10ms to reach this point.
        
    unsigned long long *indicator = (unsigned long long *)_localShmemAddress;
    *indicator = 0x1;
    
    mach_vm_address_t shmem_sym_addr = _dylib_addr + shmem_sym_offset;
    MACH_CALL(mach_vm_write(_remoteTask, shmem_sym_addr, (vm_offset_t)&_remoteShmemAddress, sizeof(_remoteShmemAddress)));
    
    int num_waits = 0;
    while (*indicator != 0) { // This will be set to 0 once the target process has initialized. This means it is safe to use the semaphore.
        nanosleep(&one_ms, NULL);
        if (num_waits++ > 1000) {
            NSLog(@"Target process has not set indicator correctly, something has gone wrong.");
            return nil;
        }
    }

    return self;
}

#define ARG_OFFSET 0x1000

// WARNING: data returned from this function will be overwritten when this is called again!
// If you wish it to be preserved, copy the NSData.
- (NSData *)sendCommand:(command_type)cmd withArg:(id)arg {
    if (!_localShmemAddress) {
        return nil; // can't communicate without shmem buffer
    }
    
    NSError *err = nil;
    NSData *serializedData = arg ? [NSKeyedArchiver archivedDataWithRootObject:arg requiringSecureCoding:false error:&err] : nil;
    if (err) {
        NSLog(@"Encountered error while serializing data: %@", err);
        return nil;
    }
    
    // Copy passed arg into the shared memory buffer so the foreign process can access it
    if (serializedData && (MAP_SIZE - [serializedData length]) < ARG_OFFSET) {
        fprintf(stderr, "Passed command of size %lu, which is too large\n", [serializedData length]);
        return nil;
    }
    
    if (serializedData) {
        // We use this trick also on the output. Instead of a physical copy, just use VM tricks.
        // To be honest this is only more efficient on larger copies, but it's a fun trick IMO
        MACH_CALL(mach_vm_copy(mach_task_self(), (mach_vm_address_t)[serializedData bytes], [serializedData length], _localShmemAddress+ARG_OFFSET));
    }
    
    command_in *command = (command_in *)_localShmemAddress;
    command -> cmd = cmd;
    command -> arg = (data_out){.shmem_offset=ARG_OFFSET, .len=[serializedData length]};
    
    // Should be -1 here because injected_library should be waiting
    struct timeval wakeup;
    gettimeofday(&wakeup, NULL);
    printf("signalling semaphore: Seconds is %ld and microseconds is %d\n", wakeup.tv_sec, wakeup.tv_usec);
    // Latency from us calling semaphore_signal to the target process waking up is ~30µs, vs. ~1000µs with nanosleep() and checking memory value
    MACH_CALL(semaphore_signal(_sem));
        
    // begin waiting for response. Consider adding timeout for error checking?
    MACH_CALL(semaphore_wait(_sem));
    gettimeofday(&wakeup, NULL);
    printf("Seconds is %ld and microseconds is %d for exiting semaphore_wait\n", wakeup.tv_sec, wakeup.tv_usec);
    printf("Left semaphore_wait\n");
        
    data_out *response = (data_out *)_localShmemAddress;
    if (response -> shmem_offset == 0 && response -> len == 0) {
        if (cmd != DETACH_FROM_PROCESS) {
            fprintf(stderr, "Got null response back, even though sem has returned. cmd is %d, stack is %s\n", cmd, [[[NSThread callStackSymbols] description] UTF8String]);
        }
        return nil;
    } else if (response -> shmem_offset == -1) {
        printf("target has exited process control\n");
        return nil;
    }
    printf("shmem_offset is %llx and len is %llx\n", response ->shmem_offset, response -> len);
    
    void *response_loc = (void *)_localShmemAddress + response -> shmem_offset;
    // This way we're zero-copy all the way from serialization in the other process.
    // TODO: consider just mmap'ing all the objective-c runtime data in the other process into this process?
    // If they use whole pointers and not offsets, it won't match up on this side though...
    return [NSData dataWithBytesNoCopy:response_loc length:response -> len freeWhenDone:false];
}

- (void)sleepOneMs {
    nanosleep(&one_ms, NULL);
}

- (NSArray<NSString *> *)getImages {
    NSData *resp = [self sendCommand:GET_IMAGES withArg:nil];
    if (!resp) {
        return nil;
    }
    
    NSError *err = nil;
    NSSet<Class> *classes = [NSSet setWithArray:@[[NSArray class], [NSString class]]];
    NSArray<NSString *> *images = [NSKeyedUnarchiver unarchivedObjectOfClasses:classes fromData:resp error:&err];
    if (err) {
        NSLog(@"Encountered error in deserializing response dictionary: %@", err);
        return nil;
    }
    
    return images;
}

- (NSString *)getExecutableImage {
    NSData *resp = [self sendCommand:GET_EXECUTABLE_IMAGE withArg:nil];
    if (!resp) {
        return nil;
    }
    
    NSError *err = nil;
    NSString *image = [NSKeyedUnarchiver unarchivedObjectOfClass:[NSString class] fromData:resp error:&err];
    if (err) {
        NSLog(@"Encountered error in deserializing response dictionary: %@", err);
        return nil;
    }
    return image;
}

- (NSArray<NSString *> *)getClassesForImage:(NSString *)image {
    NSData *resp = [self sendCommand:GET_CLASSES_FOR_IMAGE withArg:image];
    if (!resp) {
        return nil;
    }
    
    NSError *err = nil;
    NSSet<Class> *archiveClasses = [NSSet setWithArray:@[[NSArray class], [NSString class]]];
    NSArray<NSString *> *classes = [NSKeyedUnarchiver unarchivedObjectOfClasses:archiveClasses fromData:resp error:&err];
    if (err) {
        NSLog(@"Encountered error in deserializing response dictionary: %@", err);
        return nil;
    }
    
    return classes;
}

- (NSArray<NSString *> *)getMethodsForClass:(NSString *)className {
    NSData *resp = [self sendCommand:GET_METHODS_FOR_CLASS withArg:className];
    if (!resp) {
        return nil;
    }
    
    NSError *err = nil;
    NSSet<Class> *archiveClasses = [NSSet setWithArray:@[[NSArray class], [NSString class], [NSDictionary class]]];
    NSArray<NSString *> *methods = [NSKeyedUnarchiver unarchivedObjectOfClasses:archiveClasses fromData:resp error:&err];
    if (err) {
        NSLog(@"Encountered error in deserializing response dictionary: %@", err);
        return nil;
    }
    
    return methods;
}

- (NSString *)getSuperclassForClass:(NSString *)className {
    NSData *resp = [self sendCommand:GET_SUPERCLASS_FOR_CLASS withArg:className];
    if (!resp) {
        return nil;
    }
    
    NSError *err = nil;
    NSString *superclass = [NSKeyedUnarchiver unarchivedObjectOfClass:[NSString class] fromData:resp error:&err];
    if (err) {
        NSLog(@"Encountered error in deserializing response dictionary: %@", err);
        return nil;
    }
    
    return superclass;
}

- (NSNumber *)getDylib:(NSString *)dylib {
    NSData *resp = [self sendCommand:GET_SUPERCLASS_FOR_CLASS withArg:dylib];
    if (!resp) {
        return nil;
    }
    
    NSError *err = nil;
    NSNumber *superclass = [NSKeyedUnarchiver unarchivedObjectOfClass:[NSNumber class] fromData:resp error:&err];
    if (err) {
        NSLog(@"Encountered error in deserializing response dictionary: %@", err);
        return nil;
    }
    
    return superclass;
}

- (NSArray<NSDictionary *> *)getPropertiesForClass:(NSString *)className {
    NSData *resp = [self sendCommand:GET_PROPERTIES_FOR_CLASS withArg:className];
    if (!resp) {
        return nil;
    }
    
    NSError *err = nil;
    NSSet<Class> *archiveClasses = [NSSet setWithArray:@[[NSArray class], [NSString class], [NSDictionary class]]];
    NSArray<NSDictionary *> *properties = [NSKeyedUnarchiver unarchivedObjectOfClasses:archiveClasses fromData:resp error:&err];
    if (err) {
        NSLog(@"Encountered error in deserializing response dictionary: %@", err);
        return nil;
    }
    
    return properties;
}

- (NSNumber *)load_dylib:(NSString *)dylib {
    NSData *resp = [self sendCommand:LOAD_DYLIB withArg:dylib];
    if (!resp) {
        return nil;
    }
    
    NSError *err = nil;
    NSNumber *handle = [NSKeyedUnarchiver unarchivedObjectOfClass:[NSNumber class] fromData:resp error:&err];
    if (err) {
        NSLog(@"Encountered error in deserializing response dictionary: %@", err);
        return nil;
    }
    
    return handle;
}

- (NSString *)replace_methods:(NSArray<NSDictionary<NSString *, id> *> *)switches {
    NSData *resp = [self sendCommand:REPLACE_METHODS withArg:switches];
    if (!resp) {
        return nil;
    }
    
    NSError *err = nil;
    NSString *handle = [NSKeyedUnarchiver unarchivedObjectOfClass:[NSString class] fromData:resp error:&err];
    if (err) {
        NSLog(@"Encountered error in deserializing response dictionary: %@", err);
        return nil;
    }
    
    return handle;
}

- (NSArray<NSArray *> *)get_ivars:(NSString *)class {
    NSData *resp = [self sendCommand:GET_IVARS withArg:class];
    if (!resp) {
        return nil;
    }
    
    NSError *err = nil;
    NSSet<Class> *archiveClasses = [NSSet setWithArray:@[[NSArray class], [NSString class], [NSDictionary class], [NSSet class], [NSNumber class]]];
    NSArray<NSArray *> *ivars = [NSKeyedUnarchiver unarchivedObjectOfClasses:archiveClasses fromData:resp error:&err];
    if (err) {
        NSLog(@"Encountered error in deserializing response dictionary: %@", err);
        return nil;
    }
    
    return ivars;
}

- (NSString *)get_image_for_class:(NSString *)cls {
    NSData *resp = [self sendCommand:GET_IMAGE_FOR_CLASS withArg:cls];
    if (!resp) {
        return nil;
    }
    
    NSError *err = nil;
    NSString *image = [NSKeyedUnarchiver unarchivedObjectOfClass:[NSNumber class] fromData:resp error:&err];
    if (err) {
        NSLog(@"Encountered error in deserializing response dictionary: %@", err);
        return nil;
    }
    
    return image;
}

- (SerializedLayerTree *)get_layers {
    NSData *resp = [self sendCommand:GET_LAYERS withArg:nil];
    if (!resp) {
        NSLog(@"Got null resp %@", resp);
        return nil;
    }
    
    NSError *err = nil;
    SerializedLayerTree *layerTree = [NSKeyedUnarchiver unarchivedObjectOfClass:[SerializedLayerTree class] fromData:resp error:&err];
    if (err) {
        NSLog(@"Encountered error in deserializing response dictionary: %@", err);
        return nil;
    }
    
    return layerTree;
}

- (NSBitmapImageRep *)get_window_picture {
    NSData *resp = [self sendCommand:GET_WINDOW_IMAGE withArg:nil];
    if (!resp) {
        NSLog(@"Got null resp %@", resp);
        return nil;
    }
    return [NSBitmapImageRep imageRepWithData:resp];    
}

- (CGSize)get_window_size {
    NSData *resp = [self sendCommand:GET_WINDOW_SIZE withArg:nil];
    if (!resp) {
        NSLog(@"Got null resp %@", resp);
        return CGSizeZero;
    }
    
    NSError *err = nil;
    NSValue *size = [NSKeyedUnarchiver unarchivedObjectOfClass:[NSValue class] fromData:resp error:&err];
    if (err) {
        NSLog(@"Encountered error in deserializing response dictionary: %@", err);
        return CGSizeZero;
    }
    
    return [size sizeValue];
}

- (nullable id)do_invocation:(NSInvocation *)invocation {
    return [self sendCommand:DO_INVOCATION withArg:invocation];
}

- (void)dealloc {
    NSLog(@"Doing dealloc");
    [self sendCommand:DETACH_FROM_PROCESS withArg:nil];
    [self cleanUp];
}

- (void)cleanUp {
    semaphore_destroy(mach_task_self_, _sem);
    // Will also remove mapping
    mach_vm_deallocate(_remoteTask, _remoteShmemAddress, MAP_SIZE);
}

@end
