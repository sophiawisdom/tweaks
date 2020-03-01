//
//  injected_library.m
//  injected_library
//
//  Created by Sophia Wisdom on 2/29/20.
//  Copyright © 2020 William Wisdom. All rights reserved.
//

#include "stdio.h"
#include <unistd.h>

__attribute__((constructor))
void bain() { // big guy, etc.
    sleep(5);
    printf("Injected!");
}
