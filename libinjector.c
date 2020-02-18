//
//  libinjector.c
//  injector
//
//  Created by William Wisdom on 2/16/20.
//  Copyright © 2020 William Wisdom. All rights reserved.
//

#include <stdio.h>

__attribute__((constructor))
void mainy() {
    printf("Got loaded baby!!\n");
}
