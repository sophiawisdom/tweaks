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
printf("Mach call on line %d failed with error #%d \"%s\".\n", __LINE__, kret, mach_error_string(kret));\
exit(1);\
}

NSTimeInterval printTimeSince(NSDate *begin) {
    NSDate *injectionEnd = [NSDate date];
    return [injectionEnd timeIntervalSinceDate:begin];
}

const struct timespec one_ms = {.tv_sec = 0, .tv_nsec = 1 * NSEC_PER_MSEC};

#define MAP_SIZE 0x10000000
// 256 MB, because the serialized return data can get big. For activity monitor, ~20MB
// Also the memory won't be used unless we write to it.

// WARNING: data returned from this function will be overwritten when this is called again!
// If you wish it to be preserved, copy the NSData.
NSData *sendCommand(uint64_t localShmemAddress, command_type cmd, NSData *arg, semaphore_t sem) {
    // Copy passed arg into the shared memory buffer so the foreign process can access it
    if ((MAP_SIZE - [arg length]) < 0x10000) {
        fprintf(stderr, "Passed command of size %lu, which is too large\n", [arg length]);
        return nil;
    }
    // We use this trick also on the output. Instead of a physical copy, just use VM tricks.
    // To be honest this is only more efficient on larger copies, but it's a fun trick IMO
    MACH_CALL(mach_vm_copy(mach_task_self(), (mach_vm_address_t)[arg bytes], [arg length], localShmemAddress+0x1000)); // generous padding
    
    command_in *command = (command_in *)localShmemAddress;
    command -> cmd = cmd;
    command -> arg = (data_out){.shmem_offset=0x1000, .len=[arg length]};
    
    // Should be -1 here because injected_library should be waiting
    struct timeval wakeup;
    gettimeofday(&wakeup, NULL);
    printf("signalling semaphore: Seconds is %ld and microseconds is %d\n", wakeup.tv_sec, wakeup.tv_usec);
    // Latency from us calling semaphore_signal to the target process waking up is ~30µs, vs. ~1000µs with nanosleep() and checking memory value
    MACH_CALL(semaphore_signal(sem));
        
    // begin waiting for response. Consider adding timeout for error checking?
    MACH_CALL(semaphore_wait(sem));
    gettimeofday(&wakeup, NULL);
    printf("Seconds is %ld and microseconds is %d for exiting semaphore_wait\n", wakeup.tv_sec, wakeup.tv_usec);
    printf("Left semaphore_wait\n");
        
    data_out *response = (data_out *)localShmemAddress;
    if (response -> shmem_offset == 0 && response -> len == 0) {
        printf("Got null response back, even though sem has returned\n");
        return nil;
    }
    printf("shmem_offset is %llx and len is %llx\n", response ->shmem_offset, response -> len);
    
    void *response_loc = (void *) localShmemAddress + response -> shmem_offset;
    // This way we're zero-copy all the way from serialization in the other process.
    // TODO: consider just mmap'ing all the objective-c runtime data in the other process into this process?
    // If they use whole pointers and not offsets, it won't match up on this side though...
    return [NSData dataWithBytesNoCopy:response_loc length:response -> len freeWhenDone:false];
}

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
    
    task_t remoteTask;
    mach_error_t kr = task_for_pid(mach_task_self(), pid, &remoteTask);
    if (kr != KERN_SUCCESS) {
        fprintf(stderr, "Unable to call task_for_pid on pid %d: %s. Cannot continue!\n", pid, mach_error_string(kr));
        return (-1);
    }
    
    semaphore_t sem;
    MACH_CALL(semaphore_create(mach_task_self(), &sem, SYNC_POLICY_FIFO, 0));
    MACH_CALL(mach_port_insert_right(remoteTask,
                           SEM_PORT_NAME, // Randomly generated port name. This will be how the target task can access the semaphore
                                          // In theory this could collide with an existing one but in practice this is unlikely.
                           sem, //
                           MACH_MSG_TYPE_COPY_SEND)); // Semaphores give a send right (b/c receive in kernel)

    kr = inject(remoteTask, library);
    if (kr < 0) {
        fprintf(stderr, "Encountered error with injection: %d\n", remoteTask);
        return -1; // Error
    }
    
    // Allocate remote memory. This will be the location of the mapping in the target process
    mach_vm_address_t remoteShmemAddress = 0;
    memory_object_size_t remoteMemorySize = MAP_SIZE;
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
    
    fprintf(stderr, "Took %f to inject and start waiting for dylib loading\n", printTimeSince(injectionBegin));
    // Getting the dylib address requires the dylib to be loaded in the target process,
    // which can take some time. The constructor itself is close to as minimal as possible
    // where we still have a foothold in the other process, but just loading it itself takes
    // time.
    int waits = 0;
    mach_vm_address_t dylib_addr;
    while ((dylib_addr = get_dylib_address(remoteTask, library)) == 0) {
        nanosleep(&one_ms, NULL);
        if (waits++ > 1500) {
            fprintf(stderr, "unable to find dylib addr after 1500ms, something is going wrong.\n");
            break;
        }
    }
    
    NSLog(@"Found application images: %@", getApplicationImages(remoteTask));
    
    // Typically takes <10ms to reach this point.
    
    memset(localShmemAddress, 0x22, 256); // So the target process can mark some of it as zero'd and we can tell the difference.
    
    mach_vm_address_t shmem_sym_addr = dylib_addr + shmem_sym_offset;
    MACH_CALL(mach_vm_write(remoteTask, shmem_sym_addr, (vm_offset_t)&remoteShmemAddress, sizeof(remoteShmemAddress)));
    
    fprintf(stderr, "Took %f to start waiting for target to wait on semaphore\n", printTimeSince(injectionBegin));
    
    unsigned long long *indicator = (unsigned long long *)localShmemAddress;
    while (*indicator != 0) { // This will be set to 0 once the target process has initialized. This means it is safe to use the semaphore.
        nanosleep(&one_ms, NULL);
    }
    
    fprintf(stderr, "Took %f to get to sending first command after target started waiting on semaphore\n", printTimeSince(injectionBegin));
    
    NSData *resp = sendCommand(localShmemAddress, GET_IMAGES, nil, sem);
    if (!resp) {
        fprintf(stderr, "Encountered error while sending command, exiting\n");
        return 1;
    }
    
    fprintf(stderr, "Took %f to get back data from first command\n", printTimeSince(injectionBegin));
    
    NSError *err = nil;
    NSSet<Class> *classes = [NSSet setWithArray:@[[NSArray class], [NSString class]]];
    NSArray<NSString *> *images = [NSKeyedUnarchiver unarchivedObjectOfClasses:classes fromData:resp error:&err];
    fprintf(stderr, "Finished initial deserialization at %f\n", printTimeSince(injectionBegin));
    if (err) {
        NSLog(@"Encountered error in deserializing response dictionary: %@", err);
        return 1;
    }
    
    NSLog(@"Images are %@", images);
    
    // TODO: consider adding objc_addLoadImageFunc so we can see any new images loaded? Or otherwise adding hooks
    
    return 0;
}
