#import <Foundation/Foundation.h>
#import "Counter.h"

struct timespec tv = {.tv_sec=0, .tv_nsec = NSEC_PER_MSEC*500};

int main() {
    Counter *c = [[Counter alloc] init];
    for (;;) {
        NSLog(@"counter is %d!", [c getValue]);
        nanosleep(&tv, NULL);
    }
}
