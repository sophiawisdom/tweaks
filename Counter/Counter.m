//
//  counter.m
//  Counter
//
//  Created by Sophia Wisdom on 3/16/20.
//  Copyright © 2020 Sophia Wisdom. All rights reserved.
//

#import "Counter.h"

@implementation Counter {
    int _counter;
}

- (instancetype)init
{
    self = [super init];
    if (self) {
        _counter = 0;
    }
    return self;
}

- (int)getValue {
    return _counter++;
}

@end
