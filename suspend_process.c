#include <mach/mach_init.h>
#include <mach/thread_act.h>
#include <mach/task.h>
#include <mach/port.h>
#include <sys/wait.h>
#include <unistd.h>
#include <stdio.h>
#include <stdlib.h>

int main() {
    int kret = 0;
    mach_port_name_t task = MACH_PORT_NULL;
    thread_act_port_array_t threadList;
    mach_msg_type_number_t threadCount;
    
    int pid = 0;
    printf("Input PID to pause: ");
    scanf("%d", &pid);

    kret = task_for_pid(mach_task_self(), pid, &task);
    if (kret != KERN_SUCCESS) {
        printf("task_for_pid() failed with error %d!\n",kret);
        exit(0);
    }
    
    kret = task_threads(task, &threadList, &threadCount);
    if (kret!=KERN_SUCCESS) {
        printf("task_threads() failed with error %d!\n", kret);
        exit(0);
    }
    
    printf("Suspending threads.\n");
    
    for (int i = 0; i < threadCount; i++) {
        kret = thread_suspend((thread_t) threadList[i]);
        if (kret!=KERN_SUCCESS) {
            printf("thread_suspend(%d) failed with error %d!\n", i, kret);
            exit(0);
        }
    }

    sleep(10);
    printf("Resuming threads.\n");
    
    for (int i = 0; i < threadCount; i++) {
        kret = thread_resume((thread_t) threadList[i]);
        if (kret!=KERN_SUCCESS) {
            printf("thread_suspend(%d) failed with error %d!\n", i, kret);
            exit(0);
        }
    }
}
