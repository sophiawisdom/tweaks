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

#import "internal_injection_interface.h"
#import "objc_runtime_getters.h"
#import "logging.h"

#define MACH_CALL(kret) if (kret != 0) {\
    printf("Mach call on line %d failed with error #%d \"%s\".\n", __LINE__, kret, mach_error_string(kret));\
    exit(1);\
}

// "mach_vm API routines operate on page-aligned addresses" - that 2006 book
// This is used for bootstrapping shared memory. Correct value will be injected by the host process.
__attribute__((aligned(4096)))
uint64_t shmem_loc = 0;

os_log_t logger;

const struct timespec one_msec = {.tv_sec = 0, .tv_nsec = NSEC_PER_MSEC};

// Data in data_loc will be free()d after message has been received.

NSData * dispatch_command(command_in *command) {
    // The offset is rectified before it comes into us so we can use it as the loc.
    command_type cmd = command -> cmd;
    
    // It's ok to not copy this because data is only written to the mach_vm_map'd area once the function has completed.
    // Even if the NSData was used directly it would be OK.
    NSData *dat = [NSData dataWithBytesNoCopy:command -> arg.shmem_offset length:command -> arg.len freeWhenDone:false];
    
    switch (cmd) {
        case GET_IMAGES:
            return get_images();
        case GET_CLASSES_FOR_IMAGE:
            return get_classes_for_image(dat);
        case GET_METHODS_FOR_CLASS:
            return get_methods_for_class(dat);
        case GET_SUPERCLASS_FOR_CLASS:
            return get_superclass_for_class(dat);
        case GET_EXECUTABLE_IMAGE:
            return get_executable_image();
        default:
            os_log_error(logger, "Received command with unknown command_type: %d\n", cmd);
            return nil;
    }
}

void async_main() {
    logger = os_log_create("com.chrysler.porn", "injected");
    
    os_log(logger, "Initial log! Waiting for semaphore now");
    
    semaphore_t sem = SEM_PORT_NAME; // semaphores are just a port, which is created by the host and whose right is passed to the process on injection
    // There's a risk that these ports could overlap, but hopefully not too awful.
    while (shmem_loc == 0) { // wait until shmem is initialized. could do something fancy with semaphores, but this cost is paid once instead
        // of on every command so not worth it.
        nanosleep(&one_msec, NULL);
    }
    *((unsigned long long *)shmem_loc) = 0;
    command_in *command = (command_in *)(shmem_loc);
    data_out output = {0};
    // Event loop equivalent
    while (1) {
        int kr = semaphore_wait(sem);
        if (kr == KERN_TERMINATED) {
            // Host process has exited
            break;
        } else if (kr != KERN_SUCCESS) {
            MACH_CALL(kr);
        }
        struct timeval wakeup;
        gettimeofday(&wakeup, NULL);
        printf("Seconds is %ld and microseconds is %d\n", wakeup.tv_sec, wakeup.tv_usec);
        
        // We have a message, now to interpret it.
        os_log(logger, "Got new command. cmd is %x\n", command -> cmd);
        command -> arg.shmem_offset += shmem_loc; // Make suitable for processing
        NSData *command_output = dispatch_command(command);
        if (command_output == nil) {
            goto end;
        }
        
        // More efficient than memcpy(), though we incur syscall overhead. This could be >1MB though, so probably worthwhile.
        // In the ideal case, the NSData was just allocated in our map in the first place but I don't know how to do that.
        // TODO: check if command_output is bigger than shmem
        mach_vm_copy(mach_task_self(), [command_output bytes], [command_output length], shmem_loc+4096);
        output.shmem_offset = 4096;
        output.len = [command_output length];

end:
        memcpy(shmem_loc, &output, sizeof(output));
        memset(&output, 0, sizeof(output));
        semaphore_signal(sem);
        gettimeofday(&wakeup, NULL);
        printf("Seconds is %ld and microseconds is %d for signalling semaphore again\n", wakeup.tv_sec, wakeup.tv_usec);
    }
    
    os_log(logger, "Exiting process control");
}

__attribute__((constructor))
void bain() { // big guy, etc.
    // If we do something like sleep() during the constructor phase, the dylib is never considered loaded into the process.
    dispatch_queue_t new_queue = dispatch_queue_create("injected_queue", DISPATCH_QUEUE_SERIAL);
    dispatch_async(new_queue, ^{
        async_main();
    });
}
