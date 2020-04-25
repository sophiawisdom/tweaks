#include <stdio.h>
#include <stdlib.h>

#import <Foundation/Foundation.h>
#import <os/log.h>

#import "Process.h"

#import "macho_parser.h"

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
    
    usleep(500000);

    while (pid == 0) {
        printf("\nInput PID to pause: ");
        int retval = scanf("%d", &pid);
        if (retval == EOF) {
            printf("Reached EOF\n");
            return 1;
        }
    }
    
    NSDate *injectionBegin = [NSDate date];
    
    printf("Injecting into PID %d\n", pid);
    
    Process *proc = [[Process alloc] initWithPid:pid];
    
    if (proc == nil) {
        printf("Got back error for process\n");
        return 1;
    }
        
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
        
        if ([words count] == 0) {
            fprintf(stderr, "Unknown command\n");
            continue;
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
        } else if ([mainInput isEqualToString:@"get_properties_for_class"]) {
            NSString *class = [words objectAtIndex:1];
            NSLog(@"properties for class \"%@\": %@", class, [proc getPropertiesForClass:class]);
        } else if ([mainInput isEqualToString:@"load_dylib"]) {
            NSString *dylib = [[words subarrayWithRange:(NSRange){.location=1, .length=[words count]-1}] componentsJoinedByString:@" "]; // Can be multiple words
            NSLog(@"Handle for dylib \"%@\" is %@", dylib, [proc load_dylib:dylib]);
        } else if ([mainInput isEqualToString:@"switch"]) {
            if ([words count] < 4) {
                printf("need more words... only %ld", [words count]);
                continue;
            }
            printf("count is %ld\n", [words count]);
            NSString *oldClass = [words objectAtIndex:1];
            NSString *newClass = [words objectAtIndex:2];
            NSArray<NSString *> *selectors = [words subarrayWithRange:(NSRange){.location=3, .length=[words count]-3}];
            NSLog(@"Replacing selectors on old class %@ with selectors on new class %@. selectors are %@", oldClass, newClass, selectors);
            NSDictionary *switc = @{
                @"oldClass": oldClass,
                @"newClass": newClass,
                @"selectors": selectors
            };
            NSLog(@"Got back result: %@", [proc replace_methods:@[switc]]);
        } else if ([mainInput isEqualToString:@"get_windows"]) {
            NSLog(@"Got back result: %@", [proc get_windows]);
        } else if ([mainInput isEqualToString:@"get_ivars"]) {
            NSLog(@"Ivars are: %@", [proc get_ivars:[words objectAtIndex:1]]);
        } else if ([mainInput isEqualToString:@"get_image_for_class"]) {
            NSLog(@"image is: %@", [proc get_image_for_class:[words objectAtIndex:1]]);
        } else if ([mainInput isEqualToString:@"draw_layers"]) {
            NSLog(@"Starting to draw layers. this will take a while.");
            [proc draw_layers];
            NSLog(@"Done drawing layers");
        } else {
            printf("Unknown command\n");
            continue;
        }
        
        fprintf(stderr, "Took %f to get back data from first command\n", printTimeSince(injectionBegin));
    }
    
    // TODO: consider adding objc_addLoadImageFunc so we can see any new images loaded? Or otherwise adding hooks
    
    return 0;
}
