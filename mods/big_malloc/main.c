#include <stdio.h>
#include <stdlib.h>
#include <unistd.h>
#include <fcntl.h>
#include <sys/time.h>

#include <mach/mach_vm.h>
#include <mach/mach_init.h>
#include <mach/thread_act.h>
#include <mach/task.h>
#include <mach/port.h>

char *mach_error_string(int kret);

#define MACH_CALL(kret, critical) if (kret != 0) {\
printf("Mach call on line %d failed with error \"%s\".\n", __LINE__, mach_error_string(kret));\
if (critical) {exit(1);}\
}

#define MEM_SIZE 0x100000000000
#define SET_SIZE 0x25000000

int main() {
    mach_vm_address_t mach_address;
    MACH_CALL(mach_vm_allocate(mach_task_self(), &mach_address, MEM_SIZE, TRUE), TRUE);
    void *mem_addr = (void *)mach_address;
    int fd = open("/dev/urandom", O_RDONLY);
    struct timeval start_time;
    gettimeofday(&start_time, NULL);
    struct timeval curr_time;
    printf("About to start reading\n");
    for (uint64_t i = 0; i < MEM_SIZE; i += SET_SIZE) {
        read(fd, &mem_addr[i], SET_SIZE);
        gettimeofday(&curr_time, NULL);
        double curr_time_ms = (curr_time.tv_sec * 1000000) + curr_time.tv_usec;
        double start_time_ms = (start_time.tv_sec * 1000000) + start_time.tv_usec;
        double time_diff = (curr_time_ms - start_time_ms)/1000000;
        start_time = curr_time;
        printf("Finished read of size %d from %p. took %g seconds.\n", SET_SIZE, &mem_addr[i], time_diff);
    }
    printf("Finished memsetting\n");
    char result[1000];
    read(0, result, 5);
    return 0;
}
