//
//  main.c
//  pthread_testingy
//
//  Created by Sophia Wisdom on 2/26/20.
//  Copyright © 2020 William Wisdom. All rights reserved.
//

#include <stdio.h>
#include <pthread.h>
#include <unistd.h>

void pthread_guy(void *arg) {
    int *newarg = (int *)arg;
    int num = *newarg;
}

int main(int argc, const char * argv[]) {
    printf("Once you press enter the program (%d) will start:", getpid());
    int r;
    scanf("%d", &r);
    
    pthread_t thread;
    pthread_create(&thread, NULL, pthread_guy, 0x123456);
    
    printf("Created thread. Waiting for 30 seconds.");
    
    sleep(1);
    return 0;
}
