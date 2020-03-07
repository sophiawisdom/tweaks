#include "inject.h"
#include "symbol_locator.h"

#include <stdio.h>
#include <stdlib.h>

#import <Foundation/Foundation.h>
#import <os/log.h>
#import "INJXPCListenerDelegate.h"

#include "macho_parser/macho_parser.h"
#include "injected_library.h"

#define MACH_CALL(kret) if (kret != 0) {\
printf("Mach call on line %d failed with error \"%s\".\n", __LINE__, mach_error_string(kret));\
exit(1);\
}

const struct timespec one_ms = {.tv_sec = 0, .tv_nsec = 500 * NSEC_PER_MSEC};

int main(int argc, char **argv) {
    char *library = "/Users/sophiawisdom/Library/Developer/Xcode/DerivedData/mods-hiqpvfikerrvwrbgoskpjqwmglif/Build/Products/Debug/libinjected_library.dylib";
    char *shmem_symbol = "_shmem_loc";
    
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
    
    printf("Injecting into PID %d\n", pid);
        
    task_t remoteTask = inject(pid, library);
    if (remoteTask < 0) { // Shitty way of checking for error condition.
        fprintf(stderr, "Encountered error with injection: %d\n", remoteTask);
        return -1; // Error
    }
    
    sleep(1); // Probably ok to sleep less - .1 seconds even.
    
    mach_vm_address_t stringAddress = 0;
    mach_vm_allocate(remoteTask, &stringAddress, 4096, true); // Let address be relocatable
    
    mach_vm_address_t dylib_addr = get_dylib_address(remoteTask, library);
    if (dylib_addr == 0) {
        fprintf(stderr, "unable to find dylib addr\n");
    }
    
    // Allocate remote memory. This will be the location of the mapping in the target process
    mach_vm_address_t remoteShmemAddress = 0;
    memory_object_size_t remoteMemorySize = 0x1000000; // 64MB, because the serialized return data can get big.
    // Also the memory won't be used unless we write to it.
    MACH_CALL(mach_vm_allocate(remoteTask, &remoteShmemAddress, remoteMemorySize, true));
    
    // Once we've created the memory, we need a handle to that memory so we can reference it in mach_vm_map.
    mach_port_t shared_memory_handle;
    mach_make_memory_entry_64(remoteTask,
                              &remoteMemorySize,
                              remoteShmemAddress, // Memory address
                              VM_PROT_READ | VM_PROT_WRITE,
                              &shared_memory_handle,
                              MACH_PORT_NULL); // parent entry - for submaps?
    
    // Create the mapping between the objects.
    uint64_t localShmemAddress;
    // https://flylib.com/books/en/3.126.1.89/1/ has some documentation on this
    mach_vm_map(mach_task_self(),
                &localShmemAddress, // Address in this address space?
                4096, // size. Maybe worth allocating a direct data transfer space and then also opening a larger map?
                0xfff, // Alignment bits - make it page aligned
                true, // Anywhere bit
                shared_memory_handle,
                0,
                false, // not sure what this means
                VM_PROT_READ | VM_PROT_WRITE,
                VM_PROT_READ | VM_PROT_WRITE,
                VM_INHERIT_SHARE);
    
    mach_vm_address_t shmem_sym_addr = dylib_addr + shmem_sym_offset;
    MACH_CALL(mach_vm_write(remoteTask, shmem_sym_addr, &remoteShmemAddress, sizeof(remoteShmemAddress)));
    
    unsigned long long *indicator = (unsigned long long *)localShmemAddress;
    command_in *cmd = (command_in *)(localShmemAddress+8);
    cmd -> cmd = GET_CLASSES;
    cmd -> arg = (data_out){0};
    *indicator = NEW_IN_DATA;
    
    while (*indicator != NEW_OUT_DATA) {
        nanosleep(&one_ms, NULL);
    }
    
    data_out *response = (data_out *)(localShmemAddress+8);
    if (response -> shmem_offset == 0 && response -> len == 0) {
        printf("Got null response back, even though indicator is %llx\n", *indicator);
        return 1;
    }
    printf("Got back response with shmem offset %llx and len %llx\n", response -> shmem_offset, response -> len);
    void *response_loc = localShmemAddress + response -> shmem_offset;
    printf("response_loc is %llx\n", response_loc);
    NSData *resp = [NSData dataWithBytesNoCopy:response_loc length:response -> len freeWhenDone:false];
    NSLog(@"Got data %@ back", resp);
    NSError *err = nil;
    printf("Set err to nil\n");
    NSDictionary *result = [NSKeyedUnarchiver unarchivedObjectOfClass:[NSDictionary class] fromData:resp error:&err];
    printf("Just completed unarchiving\n");
    if (err) {
        NSLog(@"Encountered error in deserializing response dictionary: %@", err);
        return 1;
    }
    NSLog(@"Got new dictionary out. Keys are %@\n", [result allKeys]);
}
