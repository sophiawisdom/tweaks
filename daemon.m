#include <stdio.h>
#include <stdlib.h>

#import <Foundation/Foundation.h>
#import <os/log.h>

#import "Process.h"

#define MACH_CALL(kret) if (kret != 0) {\
printf("Mach call on line %d failed with error #%d \"%s\".\n", __LINE__, kret, mach_error_string(kret));\
exit(1);\
}

// TODO: mount -uw / + killall Finder every time the app launches so we can create "usr/lib/injection" and put all our stuff there
// Be clear that the reason why is to get around potential sandboxing issues, especially prevalent with platform binaries.
// Also add a mention in the README that SIP is required to be disabled.

NSTimeInterval printTimeSince(NSDate *begin) {
    NSDate *injectionEnd = [NSDate date];
    return [injectionEnd timeIntervalSinceDate:begin];
}

int main(int argc, char **argv) {
    
    printf("Location is %s\n", argv[0]);
    
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
    
    Process *proc = [[Process alloc] initWithPid:pid];
    
    if (proc == nil) {
        printf("Got back error for process\n");
        return 1;
    }
    
    fprintf(stderr, "Took %f to get to sending first command after target started waiting on semaphore\n", printTimeSince(injectionBegin));
    
    NSLog(@"Begin inputting commands. Options are:\nget_images (no args).\nget_classes_for_image (arg image name)\nget_methods_for_class (arg class name)\nget_superclass_for_class (arg class name)\nget_executable_image (no args)\nload_dylib (arg image name)\n> ");
    
    char *input = NULL;
    size_t line = 0;
    getline(&input, &line, stdin); // initial get is for the newline when entering PID
    // Input loop
    while (1) {
        getline(&input, &line, stdin);
        
        injectionBegin = [NSDate date];
        
        NSArray<NSString *>* initialWords = [[NSString stringWithUTF8String:input] componentsSeparatedByCharactersInSet :[NSCharacterSet whitespaceAndNewlineCharacterSet]];
        NSMutableArray<NSString *> *words = [[NSMutableArray alloc] init];
        for (NSString *str in initialWords) {
            if ([str length] > 0) {
                [words addObject:str];
            }
        }
        
        NSString *mainInput = [words objectAtIndex:0];
        if ([mainInput isEqualToString:@"get_images"]) {
            NSLog(@"Images: %@", [proc getImages]);
        } else if ([mainInput isEqualToString:@"get_executable_image"]) {
            NSLog(@"Images: %@", [proc getExecutableImage]);
        } else if ([mainInput isEqualToString:@"get_classes_for_image"]) {
            NSString *image = [[words subarrayWithRange:(NSRange){.location=1, .length=[words count]-1}] componentsJoinedByString:@" "]; // Can be multiple words
            NSLog(@"Classes for image \"%@\": %@", image, [proc getClassesForImage:image]);
        } else if ([mainInput isEqualToString:@"get_methods_for_class"]) {
            NSString *class = [words objectAtIndex:1];
            NSLog(@"Methods for class \"%@\": %@", class, [proc getMethodsForClass:class]);
        } else if ([mainInput isEqualToString:@"get_superclass_for_class"]) {
            NSString *class = [words objectAtIndex:1];
            NSLog(@"Superclass for class \"%@\": %@", class, [proc getSuperclassForClass:class]);
        } else {
            printf("Unknown command\n");
            continue;
        }
        
        fprintf(stderr, "Took %f to get back data from first command\n", printTimeSince(injectionBegin));
    }
    
    // TODO: consider adding objc_addLoadImageFunc so we can see any new images loaded? Or otherwise adding hooks
    
    return 0;
}
