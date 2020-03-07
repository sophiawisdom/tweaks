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
__attribute__((aligned(4096)))
struct injection_struct injection_in = {0}; // Host process to target
__attribute__((aligned(4096)))
struct injection_struct injection_out = {0}; // Target process to host (response)

const struct timespec one_msec = {.tv_sec = 0, .tv_nsec = NSEC_PER_MSEC};

// Data in data_loc will be free()d after message has been received.

struct injection_struct get_classes() {
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
        return (struct injection_struct) {0};
    }
    
    // When will serialized_classes get freed? Not to worry now, but TODO: look for memory leaks. probably several.
    // does/can autoreleasing know about data in structs?
                
    return (struct injection_struct){.data_loc=[serialized_classes bytes], .data_len=[serialized_classes length], .data_indicator = 1};
}

void async_main() {
    printf("Code run with dispatch_async\n");
    
    printf("injection_out addr is %llx\n", &injection_out);
    
    while (1) {
        if (injection_in.data_indicator == 0) {
            nanosleep(&one_msec, NULL);
            continue;
        }
        
        printf("Injection point is %p. data_loc is %p, data_len is 0x%x, data_indicator is %llu\n", &injection_in, injection_in.data_loc, injection_in.data_len, injection_in.data_indicator);
        
        NSData *data = [[NSData alloc] initWithBytes:injection_in.data_loc length:injection_in.data_len];
        NSError *err = nil;
        NSDictionary *result = [NSKeyedUnarchiver unarchivedObjectOfClass:[NSDictionary class] fromData:data error:&err];
        if (err) {
            NSLog(@"Got error when unarchiving object received from injection: %@", err);
            return;
        }
        
        NSLog(@"Got result back - %@", result);
        NSNumber *shmem_num = [result objectForKey:@"shmem_address"];
        void *shmem_addr = (void *)[shmem_num longValue];
        memset(shmem_addr, 0x69, 4096);
        printf("Wrote a bunch of stuff to shmem_addr on our side, %llx\n", shmem_addr);
        
        memset(&injection_in, 0, sizeof(injection_in));
        
        if ([[result objectForKey:command_key] isEqualToString:get_classes_key]) {
            struct injection_struct result = get_classes();
            memcpy(&injection_out, &result, sizeof(injection_out));
        } else {
            printf("Unable to understand command\n");
        }
        
        printf("injection_out is %llx, %llx, %llx. writing now.\n", injection_out.data_len, injection_out.data_loc, injection_out.data_indicator);
        printf("Sent out data, waiting for response. data_indicator location is %p\n", &injection_out.data_indicator);
        while (injection_out.data_indicator) {
            nanosleep(&one_msec, NULL);
        }
        printf("Out data received\n");
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
