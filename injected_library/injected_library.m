//
//  injected_library.m
//  injected_library
//
//  Created by Sophia Wisdom on 2/29/20.
//  Copyright © 2020 Sophia Wisdom. All rights reserved.
//

#include <time.h>
#import <Foundation/Foundation.h>
#import <os/log.h>
#import <objc/runtime.h>

#import "symbol_locator.h"
#import "internal_injection_interface.h"
#import "objc_runtime_getters.h"
#import "logging.h"

#define MACH_CALL(kret) if (kret != 0) {\
    os_log(logger, "Mach call on line %d failed with error #%d \"%s\".\n", __LINE__, kret, mach_error_string(kret));\
    exit(1);\
}

// "mach_vm API routines operate on page-aligned addresses" - that 2006 book
// This is used for bootstrapping shared memory. Correct value will be injected by the host process.
__attribute__((aligned(4096)))
uint64_t shmem_loc = 0;

os_log_t logger;
dispatch_queue_t injected_queue;

const struct timespec one_msec = {.tv_sec = 0, .tv_nsec = NSEC_PER_MSEC};

// Data in data_loc will be free()d after message has been received.

id runCommand(command_type cmd, id input) {
    switch (cmd) {
        case GET_IMAGES:
            return get_images();
        case GET_CLASSES_FOR_IMAGE:
            return get_classes_for_image(input);
        case GET_METHODS_FOR_CLASS:
            return get_methods_for_class(input);
        case GET_SUPERCLASS_FOR_CLASS:
            return get_superclass_for_class(input);
        case GET_EXECUTABLE_IMAGE:
            return get_executable_image();
        case LOAD_DYLIB:
            return load_dylib(input);
        case REPLACE_METHODS:
            return replace_methods(input);
        case GET_PROPERTIES_FOR_CLASS:
            return get_properties_for_class(input);
        case GET_WINDOWS:
            return get_layers();
        case GET_IVARS:
            return getIvars(input);
        case GET_IMAGE_FOR_CLASS:
            return get_image_for_class(input);
        case GET_LAYERS:
            return get_serialized_layers();
        default:
            os_log_error(logger, "Received command with unknown command_type: %d\n", cmd);
            return nil;
    }
}

NSData * dispatch_command(command_in *command) {
    // The offset is rectified before it comes into us so we can use it as the loc.
    
    // It's ok to not copy this because data is only written to the mach_vm_map'd area once the function has completed.
    // Even if the NSData was used directly it would be OK.
    id input = nil;
    if (command -> arg.len > 0) {
        NSData *dat = [NSData dataWithBytesNoCopy:command -> arg.shmem_offset length:command -> arg.len freeWhenDone:false];
//        NSSet<Class> *classes = [NSSet setWithArray:@[[NSString class], [NSArray class], [NSNumber class], [NSDictionary class]]];
        NSError *err = nil;
        // We use the unprotected version here because ideally we don't want to have to look
        // at this code in the future, and getting mysterious errors every time you send something
        // outside of the trivial classes listed is annoying. Also, security concerns themselves
        // aren't something i'm super worried about, as this data comes from a memory-mapped buffer
        // set up by the parent.
        input = [NSKeyedUnarchiver unarchiveTopLevelObjectWithData:dat error:&err];
//        input = [NSKeyedUnarchiver unarchivedObjectOfClasses:classes fromData:dat error:&err];
        if (err) {
            os_log_error(logger, "encountered error when deserializing data: %{public}@. data is %{public}@ input is %{public}@ ", err, dat, input);
            return nil;
        }
    }
    
    id<NSObject> retVal = runCommand(command -> cmd, input);
        
    if (retVal == nil) {
        return nil;
    } else if ([retVal isKindOfClass:[NSData class]]) {
        return (NSData *)retVal;
    }
    
    NSError *err = nil;
    NSData *archivedData = [NSKeyedArchiver archivedDataWithRootObject:retVal requiringSecureCoding:false error:&err];
    if (err) {
        os_log_error(logger, "encountered error %{public}@ when deserializing data %{public}@", err, retVal);
        return nil;
    }
    
    return archivedData;
}

void async_main() {
    logger = os_log_create("com.tweaks.injected", "injected");
    
    os_log_debug(logger, "Initial log! Waiting for shmem_loc to be populated now.");
    
    semaphore_t sem = SEM_PORT_NAME; // semaphores are just a port, which is created by the host and whose right is passed to the process on injection
    // There's a risk that these ports could overlap, but hopefully not too awful.
    while (shmem_loc == 0) { // wait until shmem is initialized. could do something fancy with semaphores, but this cost is paid once instead
        // of on every command so not important
        nanosleep(&one_msec, NULL);
    }
    *((unsigned long long *)shmem_loc) = 0;
    os_log_debug(logger, "shmem_loc has now been populated and the first eight bytes of the shared memory region have been set to 0. Beginning event loop.");
    command_in *command = (command_in *)(shmem_loc);
    data_out output = {0};
    // Event loop equivalent. In an ideal world, we would just hand off the semaphore to dispatch
    // and be able to do without all this stuff, but i don't know of a way as of yet to initialize
    // a dispatch semaphore from a mach semaphore -- though it may well be possible by hacking one
    // together.
    while (1) {
        int kr = semaphore_wait(sem);
        if (kr == KERN_TERMINATED) {
            // Host process has exited, so gracefully leave.
            break;
        }
        MACH_CALL(kr);
        
        // We have a message, now to interpret it.
        os_log_debug(logger, "Got new command. cmd is %x\n", command -> cmd);
        if (command -> cmd == DETACH_FROM_PROCESS) {
            break;
        }
        command -> arg.shmem_offset += shmem_loc; // Make suitable for processing
        NSData *command_output = dispatch_command(command);
        if (command_output == nil) {
            goto end;
        } else if ([command_output length] > MAP_SIZE) {
            os_log_error(logger, "Data length (%ld) was greater than map size (%d). Data is %@", [command_output length], MAP_SIZE, command_output);
            goto end;
        }
        
        // More efficient than memcpy(), though we incur syscall overhead. This could be >1MB though, so probably worthwhile.
        // In the ideal case, the NSData was just allocated in our map in the first place but I don't know how to do that.
        MACH_CALL(mach_vm_copy(mach_task_self(), [command_output bytes], [command_output length], shmem_loc+4096));
        output.shmem_offset = 4096;
        output.len = [command_output length];

end:
        memcpy(shmem_loc, &output, sizeof(output));
        memset(&output, 0, sizeof(output));
        semaphore_signal(sem);
    }
    
    // This is inneficient because it's designed for remote processes, but it's fine.
    void * handle = get_dylib_address(mach_task_self(), "/usr/lib/injected/libinjected_library.dylib");
    // The handle you get back from dlopen() is just the location the dylib was loaded at. We can figure this out by inspecting
    // the process
    dlclose(handle);
    
    os_log(logger, "Exiting process control");
    os_release(logger);
    
    dispatch_release(injected_queue);
    
    output = (data_out){.shmem_offset=-1, .len=-1};
    memcpy(shmem_loc, &output, sizeof(output));
    semaphore_signal(sem);
}

// Makes the function run when the library is loaded, so we only have to do
// dlopen() in the injected code section instead of dlopen() -> dlsym("bain")()
__attribute__((constructor)) void bain() { // big guy, etc.
    // If we run the event loop in this constructor phase, the dylib is never considered loaded in the process, which
    // isn't a state we want to be in for very long. Instead, we pass off control to dispatch as fast as possible.
     
     injected_queue = dispatch_queue_create("injected_queue", DISPATCH_QUEUE_SERIAL);
     dispatch_async(injected_queue, ^{
         async_main();
     });
}
