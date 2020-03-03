#include "inject.h"
#include "symbol_locator.h"

#include <stdio.h>
#include <stdlib.h>

#import <Foundation/Foundation.h>
#import <os/log.h>

#include "macho-parser/macho_parser.h"

#define MACH_CALL(kret) if (kret != 0) {\
printf("Mach call on line %d failed with error \"%s\".\n", __LINE__, mach_error_string(kret));\
exit(1);\
}

int main(int argc, char **argv) {
    char *library = "/Users/sophiawisdom/Library/Developer/Xcode/DerivedData/mods-hiqpvfikerrvwrbgoskpjqwmglif/Build/Products/Debug/libinjected_library.dylib";
    char *injectionSymbol = "_data_loc";
    char *diffSymbol = "_diff_indicator";
    
    mach_vm_offset_t injection_offset = getSymbolOffset(library, injectionSymbol); // We can't take the typical path of just
    // loading the dylib into memory and using dlsym() to get the offset because loading the dylib has side effects
    // for obvious reasons. Instead, we get the offset of the symbol from the dylib itself.
    mach_vm_offset_t diff_indicator_offset = getSymbolOffset(library, diffSymbol);
    if (!injection_offset || !diff_indicator_offset) {
        fprintf(stderr, "Unable to get offset for symbol %s in dylib %s.\n", injectionSymbol, library);
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
    
    char exampleString[] = "Hello, this is an example injection string! Pretty wicked, I would say!!\0";
    mach_vm_write(remoteTask, stringAddress, (mach_vm_address_t) exampleString, sizeof(exampleString)); // Write string
    printf("Wrote string to address %p\n", stringAddress);
    
    mach_vm_address_t dylib_addr = get_dylib_address(remoteTask, library);
    if (dylib_addr == 0) {
        fprintf(stderr, "unable to find dylib addr\n");
    }
    mach_vm_address_t injection_addr = dylib_addr + injection_offset;
    mach_vm_address_t diff_indicator_addr = dylib_addr + diff_indicator_offset;
    printf("injection_addr is %llx. dylib_addr is %llx. injection_offset is %llx\n", injection_addr, dylib_addr, injection_offset);
    
    mach_vm_write(remoteTask, injection_addr, &stringAddress, 8); // This is writing the pointer
    printf("Set injection addr (%llx) to string address %llx\n", injection_addr, stringAddress);
    
    srandomdev();
    int total_ms = 0;
    for (int i = 0; i < 1000; i++) {
        int ms_to_wait = (random() & 63) + 5;
        struct timespec ten_ms = {.tv_sec = 0, .tv_nsec=NSEC_PER_MSEC*ms_to_wait};
        nanosleep(&ten_ms, NULL);
        total_ms += ms_to_wait;
        
        char *output = malloc(4096);
        sprintf(output, "Have now waited a total of %d milliseconds", total_ms);
        printf("Have now waited a total of %d milliseconds\n", total_ms); // Duplicating for newline
        
        MACH_CALL(mach_vm_write(remoteTask, stringAddress, output, 4096)); // write new string
        MACH_CALL(mach_vm_write(remoteTask, diff_indicator_addr, &i, sizeof(i))); // Write new pointer
    }
}
