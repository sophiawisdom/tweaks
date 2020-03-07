//
//  injected_library.m
//  injected_library
//
//  Created by Sophia Wisdom on 2/29/20.
//  Copyright © 2020 Sophia Wisdom. All rights reserved.
//

#import <Foundation/Foundation.h>
#import <os/log.h>
#import "InjectedXPCDelegate.h"

#import "injected_library.h"
#import <objc/runtime.h>

#include <time.h>

// "mach_vm API routines operate on page-aligned addresses" - that 2006 book
// This is used for bootstrapping shared memory. Correct value will be injected by the host process.
__attribute__((aligned(4096)))
uint64_t shmem_loc = 0;

const struct timespec one_msec = {.tv_sec = 0, .tv_nsec = NSEC_PER_MSEC};

// Data in data_loc will be free()d after message has been received.

NSData * get_classes() {
    unsigned int numClasses = 0;
    Class * classes = objc_copyClassList(&numClasses);
    printf("Got %d classes\n", numClasses);
    // This ends up requiring an individual mach_vm_read for every class. In the future (and/or now)
    // it would be better to just get all the class names (and maybe methods?) and put them in a single
    // contiguous block.
    
    // class_copyMethodList and class_getName and method_getDescription. Potentially also get ivars/properties/weak ivars/protocols.
    
    /*Class *contiguousClasses = (__bridge Class *) malloc(sizeof(Class) * count);
    for (int i = 0; i < count; i++) {
        memcpy(&contiguousClasses[i], &classes[i], sizeof(Class));
        contiguousClasses[i];
    }*/
    
    NSMutableArray<NSDictionary *> *class_data = [[NSMutableArray alloc] initWithCapacity:numClasses];
    for (int i = 0; i < numClasses; i++) {
        Class cls = classes[i];
        
        // Consider doing same with protocols/properties/ivars
        unsigned int numMethods = 0;
        Method * methods = class_copyMethodList(cls, &numMethods); // Does not look at superclasses
        NSMutableArray<NSDictionary *> *methodList = [[NSMutableArray alloc] initWithCapacity:numMethods];
        for (int j = 0; j < numMethods; j++) {
            struct objc_method_description *desc = method_getDescription(methods[j ]);
            if (desc -> name == NULL) {
                printf("Got null selector... Not sure what this means. Class is %s\n", class_getName(cls));
                continue;
            }
            [methodList setObject:@{@"name": [NSString stringWithUTF8String:desc -> name], @"types": [NSString stringWithUTF8String:desc -> types]} atIndexedSubscript:j];
        }
        
        NSString *name = [NSString stringWithUTF8String:class_getName(cls)];
        
        [class_data setObject:@{@"methods": methodList, @"name":name} atIndexedSubscript:i];
    }
    
    NSError *err = nil;
    NSData *serialized_classes = [NSKeyedArchiver archivedDataWithRootObject:class_data requiringSecureCoding:false error:&err];
    if (err) {
        printf("Something went wrong\n");
        NSLog(@"Got error archiving class data: %@", err);
        return nil;
    }
    
    // When will serialized_classes get freed? Not to worry now, but TODO: look for memory leaks. probably several.
    // does/can autoreleasing know about data in structs?
    
    return serialized_classes;
}

NSData * dispatch_command(command_in *command) {
    // The offset is rectified before it comes into us so we can use it as the loc.
    command_type cmd = command -> cmd;
    
    NSData *dat = [NSData dataWithBytesNoCopy:command -> arg.shmem_offset length:command -> arg.len freeWhenDone:false];
    
    switch (cmd) {
        case GET_CLASSES:
            return get_classes();
        default:
            printf("Received command with unknown command_type: %d\n", cmd);
            return nil;
    }
}

void async_main() {
    // Wait for bootstrap
    while (shmem_loc == 0) {
        nanosleep(&one_msec, NULL);
    }
    
    unsigned long long *indicator = (unsigned long long *)shmem_loc;
    command_in *command = (command_in *)(shmem_loc+8);
    // Shitty event loop equivalent
    while (1) {
        data_out output = {0};
        while (*indicator != NEW_IN_DATA) {
            nanosleep(&one_msec, NULL);
        }
        printf("Indicator is now %llx. command's offset from indicator is %llx\n", *indicator, (uint64_t)command - (uint64_t)indicator);
        
        // We have a message, now to interpret it.
        printf("Got new command. cmd is %x\n", command -> cmd);
        command -> arg.shmem_offset += shmem_loc; // Make suitable for processing
        NSData *command_output = dispatch_command(command);
        if (command_output == nil) {
            goto end;
        }
        
        // More efficient than memcpy(), though we incur syscall overhead. This could be >1MB though, so probably worthwhile.
        // In the ideal case, the NSData was just allocated in our map in the first place but I don't know how to do that.
        // TODO: check if command_output is bigger than shmem
        mach_vm_copy(mach_task_self(), [command_output bytes], [command_output length], shmem_loc+4096 /* page boundary */);
        output.shmem_offset = 4096;
        output.len = [command_output length];

end:
        memcpy(shmem_loc+8, &output, sizeof(output));
        *indicator = NEW_OUT_DATA; // indicate to host new data is ready
    }
}

__attribute__((constructor))
void bain() { // big guy, etc.
    // If we do something like sleep() during the constructor phase, the dylib is never considered loaded into the process.
    dispatch_queue_t new_queue = dispatch_queue_create("injected_queue", DISPATCH_QUEUE_SERIAL);
    dispatch_async(new_queue, ^{
        async_main();
    });
}
