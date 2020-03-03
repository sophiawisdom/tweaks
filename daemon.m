#include "inject.h"
#include "symbol_locator.h"

#include <stdio.h>
#include <stdlib.h>

#import <Foundation/Foundation.h>
#import <os/log.h>
#import "INJXPCListenerDelegate.h"

#include "macho-parser/macho_parser.h"

#define MACH_CALL(kret) if (kret != 0) {\
printf("Mach call on line %d failed with error \"%s\".\n", __LINE__, mach_error_string(kret));\
exit(1);\
}

int main(int argc, char **argv) {
    char *library = "/Users/sophiawisdom/Library/Developer/Xcode/DerivedData/mods-hiqpvfikerrvwrbgoskpjqwmglif/Build/Products/Debug/libinjected_library.dylib";
    char *data_loc_symbol = "_endpoint_loc";
    char *data_len_symbol = "_endpoint_len";
    
    mach_vm_offset_t data_loc_offset = getSymbolOffset(library, data_loc_symbol); // We can't take the typical path of just
    // loading the dylib into memory and using dlsym() to get the offset because loading the dylib has side effects
    // for obvious reasons. Instead, we get the offset of the symbol from the dylib itself.
    mach_vm_offset_t data_len_offset = getSymbolOffset(library, data_len_symbol);
    if (!data_loc_offset || !data_len_offset) {
        fprintf(stderr, "Unable to get offset for symbol %s in dylib %s.\n", data_loc_symbol, library);
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
    
    mach_vm_address_t data_loc_sym_addr = dylib_addr + data_loc_offset;
    mach_vm_address_t data_len_sym_addr = dylib_addr + data_len_offset;
    
    mach_vm_address_t data_loc_addr = 0;
    mach_msg_type_number_t dataCnt;
    
    mach_vm_read(remoteTask, data_loc_sym_addr, sizeof(data_loc_addr), &data_loc_addr, &dataCnt);
    while (data_loc_addr == 0) {
        struct timespec rqtp = {.tv_nsec = NSEC_PER_MSEC, .tv_sec = 0};
        nanosleep(&rqtp, NULL);

        mach_vm_read(remoteTask, data_loc_sym_addr, sizeof(data_loc_addr), &data_loc_addr, &dataCnt);
    }
    
    printf("Got data loc addr %llx\n", data_loc_addr);
    
    mach_vm_address_t data_len = 0;
    mach_vm_read(remoteTask, data_len_sym_addr, sizeof(data_len), &data_len, &dataCnt);
    
    printf("Got data len %llx\n", data_len);
    
    void *endpoint_raw_data = malloc(data_len);
    mach_vm_read(remoteTask, data_loc_addr, data_len, endpoint_raw_data, &dataCnt);
    
    NSData *endpoint_data = [[NSData alloc] initWithBytes:endpoint_raw_data length:data_len];
    NSError *error = nil;
    [NSKeyedUnarchiver unarchivedObjectOfClass:[NSXPCListenerEndpoint class] fromData:endpoint_data error:&error];
    if (error) {
        os_log_error(OS_LOG_DEFAULT, "Got error %@ when deserializing endpoint data", error);
    }
}
