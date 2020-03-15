#include <stdio.h>
#include <stdlib.h>

#import <Foundation/Foundation.h>
#import <os/log.h>

#import "Process.h"

#define MACH_CALL(kret) if (kret != 0) {\
printf("Mach call on line %d failed with error #%d \"%s\".\n", __LINE__, kret, mach_error_string(kret));\
exit(1);\
}

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
    
    fprintf(stderr, "Took %f to get to sending first command after target started waiting on semaphore\n", printTimeSince(injectionBegin));
    
    NSLog(@"Begin inputting commands. Options are:\nget_images (no args).\nget_classes_for_image (arg image name)\nget_methods_for_class (arg class name)\nget_superclass_for_class (arg class name)\n> ");
    
    char *input = NULL;
    size_t line = 0;
    getline(&input, &line, stdin); // initial get is for the newline when entering PID
    // Input loop
    while (1) {
        getline(&input, &line, stdin);
        NSError *err = nil;
        
        injectionBegin = [NSDate date];
        
        NSArray<NSString *>* initialWords = [[NSString stringWithUTF8String:input] componentsSeparatedByCharactersInSet :[NSCharacterSet whitespaceAndNewlineCharacterSet]];
        NSMutableArray<NSString *> *words = [[NSMutableArray alloc] init];
        for (NSString *str in initialWords) {
            if ([str length] > 0) {
                [words addObject:str];
            }
        }
        NSLog(@"Words are %@", words);
        NSString *mainInput = [words objectAtIndex:0];
        if ([mainInput isEqualToString:@"get_images"]) {
            NSData *resp = [proc sendCommand:GET_IMAGES withArg:nil];
            if (!resp) {
                fprintf(stderr, "Encountered error while sending command, exiting\n");
                return 1;
            }
            
            fprintf(stderr, "Took %f to get back data from first command\n", printTimeSince(injectionBegin));
            
            NSSet<Class> *classes = [NSSet setWithArray:@[[NSArray class], [NSString class]]];
            NSArray<NSString *> *images = [NSKeyedUnarchiver unarchivedObjectOfClasses:classes fromData:resp error:&err];
            if (err) {
                NSLog(@"Encountered error in deserializing response dictionary: %@", err);
                return 1;
            }
            NSLog(@"Got images back: %@", images);
        } else if ([mainInput isEqualToString:@"get_executable_image"]) {
            NSData *resp = [proc sendCommand:GET_EXECUTABLE_IMAGE withArg:nil];
            if (!resp) {
                fprintf(stderr, "Encountered error while sending command, exiting\n");
                return 1;
            }
                        
            NSString *image = [NSKeyedUnarchiver unarchivedObjectOfClass:[NSString class] fromData:resp error:&err];
            if (err) {
                NSLog(@"Encountered error in deserializing response dictionary: %@", err);
                return 1;
            }
            NSLog(@"executable image: %@", image);
        } else if ([mainInput isEqualToString:@"get_classes_for_image"]) {
            NSString *image = [[words subarrayWithRange:(NSRange){.location=1, .length=[words count]-1}] componentsJoinedByString:@" "]; // Can be multiple words
            NSLog(@"Getting classes for image \"%@\"", image);
            
            NSData *resp = [proc sendCommand:GET_CLASSES_FOR_IMAGE withArg:image];
            if (!resp) {
                fprintf(stderr, "Encountered error while sending command, exiting\n");
                return 1;
            }
                        
            NSSet<Class> *archiveClasses = [NSSet setWithArray:@[[NSArray class], [NSString class]]];
            NSArray<NSString *> *classes = [NSKeyedUnarchiver unarchivedObjectOfClasses:archiveClasses fromData:resp error:&err];
            if (err) {
                NSLog(@"Encountered error in deserializing response dictionary: %@", err);
                return 1;
            }
            NSLog(@"got classes back: %@", classes);
        } else if ([mainInput isEqualToString:@"get_methods_for_class"]) {
            NSString *class = [words objectAtIndex:1];
            NSLog(@"Getting methods for clas \"%@\"", class);
            
            NSData *resp = [proc sendCommand:GET_METHODS_FOR_CLASS withArg:class];
            if (!resp) {
                fprintf(stderr, "Encountered error while sending command, exiting\n");
                return 1;
            }
                        
            NSSet<Class> *archiveClasses = [NSSet setWithArray:@[[NSArray class], [NSString class], [NSDictionary class]]];
            NSArray<NSString *> *methods = [NSKeyedUnarchiver unarchivedObjectOfClasses:archiveClasses fromData:resp error:&err];
            if (err) {
                NSLog(@"Encountered error in deserializing response dictionary: %@", err);
                return 1;
            }
            NSLog(@"got methods back: %@", methods);
        } else if ([mainInput isEqualToString:@"get_superclass_for_class"]) {
            NSString *class = [words objectAtIndex:1];
            NSLog(@"Getting supperclasses for class %@", class);
            
            NSData *resp = [proc sendCommand:GET_SUPERCLASS_FOR_CLASS withArg:class];
            if (!resp) {
                fprintf(stderr, "Encountered error while sending command, exiting\n");
                return 1;
            }
                        
            NSString *superclass = [NSKeyedUnarchiver unarchivedObjectOfClass:[NSString class] fromData:resp error:&err];
            if (err) {
                NSLog(@"Encountered error in deserializing response dictionary: %@", err);
                return 1;
            }
            NSLog(@"got superclass: %@", superclass);
        } else {
            printf("Unknown command\n");
            continue;
        }
        
        fprintf(stderr, "Took %f to get back data from first command\n", printTimeSince(injectionBegin));
    }
    
    // TODO: consider adding objc_addLoadImageFunc so we can see any new images loaded? Or otherwise adding hooks
    
    return 0;
}
