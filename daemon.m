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
    char *injection_in_symbol = "_injection_in";
    char *injection_out_symbol = "_injection_out";
    
    mach_vm_offset_t injection_in_offset = getSymbolOffset(library, injection_in_symbol); // We can't take the typical path of just
    // loading the dylib into memory and using dlsym() to get the offset because loading the dylib has side effects
    // for obvious reasons. Instead, we get the offset of the symbol from the dylib itself.
    mach_vm_offset_t injection_out_offset = getSymbolOffset(library, injection_out_symbol);
    if (!injection_in_offset || !injection_out_offset) {
        fprintf(stderr, "Unable to get offset for symbol %s in dylib %s.\n", injection_in_symbol, library);
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
    memory_object_size_t remoteMemorySize = 0x1000000; // 64MB
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
    unsigned long long * localShmemAddress;
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
    
    printf("Before sending shmem loc over, Mmap location on our side is %llx. First ull is %llx\n", localShmemAddress, *localShmemAddress);
    
    NSDictionary *dict = @{command_key: get_classes_key, @"shmem_address": [NSNumber numberWithLong:remoteShmemAddress]};
    NSError *err = nil;
    NSData *dict_data = [NSKeyedArchiver archivedDataWithRootObject:dict requiringSecureCoding:false error:&err];
    if (err) {
        os_log_error(OS_LOG_DEFAULT, "Got error while archiving dictionary: %@", err);
        return 1;
    }
    os_log(OS_LOG_DEFAULT, "dict_data is %@", dict_data);
    
    mach_vm_address_t dictionary_addr;
    MACH_CALL(mach_vm_allocate(remoteTask, &dictionary_addr, [dict_data length], true));
    MACH_CALL(mach_vm_write(remoteTask, dictionary_addr, [dict_data bytes], [dict_data length]));
        
    struct injection_struct data_to_inject = {
        .data_loc = (void *)dictionary_addr,
        .data_len = [dict_data length],
        .data_indicator = 1,
    };
    
    mach_vm_address_t injection_in_addr = dylib_addr + injection_in_offset;
    mach_vm_address_t injection_out_addr = dylib_addr + injection_out_offset;
    
    MACH_CALL(mach_vm_write(remoteTask, injection_in_addr, &data_to_inject, sizeof(data_to_inject)));
    
    sleep(1);
        
    __attribute__((aligned(4096)))
    struct injection_struct injection_out = {0};
    __attribute__((aligned(4096)))
    struct injection_struct empty_struct = {0};
    
    unsigned int bytesRead = 0;
    MACH_CALL(mach_vm_read(remoteTask, injection_in_addr, 24, &injection_out, &bytesRead));
    printf("injection_out in test is %llx, %llx, %llx. dataCnt is %d\n", injection_out.data_loc, injection_out.data_len, injection_out.data_indicator, bytesRead);

    mach_msg_type_number_t dataCnt = 0;
    while (1) {
        printf("reading remote address %llx to injection_out %llx\n", injection_out_addr, &injection_out);
        MACH_CALL(mach_vm_read(remoteTask, injection_out_addr, sizeof(struct injection_struct), &injection_out, &dataCnt));
        
        printf("injection_out is %llx, %llx, %llx. dataCnt is %d\n", injection_out.data_loc, injection_out.data_len, injection_out.data_indicator, dataCnt);
        
        if (injection_out.data_indicator != 0) break;
        
        nanosleep(&one_ms, NULL);
    }
    
    if (injection_out.data_indicator != 1) {
        printf("Got some kind of wrong injection_out, data_indicator is %llx instead of 1\n", injection_out.data_indicator);
    }
    
    void *raw_data = malloc(injection_out.data_len);
    
    mach_vm_read(remoteTask, injection_out.data_loc, injection_out.data_len, (mach_vm_offset_t) raw_data, &dataCnt);
    
    NSData *class_data = [NSData dataWithBytes:raw_data length:injection_out.data_len];
    
    err = nil;
    NSArray<NSDictionary *> *classes = [NSKeyedUnarchiver unarchivedObjectOfClass:[NSArray class] fromData:class_data error:&err];
    if (err) {
        NSLog(@"Got error while deserializing classes: %@", err);
    }
    
    NSLog(@"Got back class data: %@", classes);
    
    mach_vm_write(remoteTask, injection_out_addr, &empty_struct, sizeof(empty_struct)); // Signal we've received the response
    
    
}
