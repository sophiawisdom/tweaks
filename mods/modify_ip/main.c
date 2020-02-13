#include <mach/mach_init.h>
#include <mach/thread_act.h>
#include <mach/task.h>
#include <mach/port.h>
#include <sys/wait.h>
#include <unistd.h>
#include <stdio.h>
#include <stdlib.h>
#include <mach/mach_vm.h>

#define DEFAULT_OFFSET 8

int main(int argc, char **argv) {
    int kret = 0;
    mach_port_name_t task = MACH_PORT_NULL;
    thread_act_port_array_t threadList;
    mach_msg_type_number_t threadCount;

    int pid = 0;
    if (argc > 1) {
        pid = atoi(argv[1]);
    }
    if (pid == 0) {
        printf("Input PID to pause: ");
        scanf("%d", &pid);
    }

    int offset = DEFAULT_OFFSET;
    if (argc > 2) {
        offset = atoi(argv[2]);
    }

    printf("PID is: %d. Offset is %d\n", pid, offset);

    // Get access to the task port
    kret = task_for_pid(mach_task_self(), pid, &task);
    if (kret != KERN_SUCCESS) {
        printf("task_for_pid() failed with error %d!\n",kret);
        exit(0);
    }

    // Get all threads
    kret = task_threads(task, &threadList, &threadCount);
    if (kret!=KERN_SUCCESS) {
        printf("task_threads() failed with error %d!\n", kret);
        exit(0);
    }

    printf("Modifying registers\n");

    for (int i = 0; i < threadCount; i++) {
        kret = thread_suspend((thread_t) threadList[i]);
        if (kret!=KERN_SUCCESS) {
            printf("thread_suspend(%d) failed with error %d!\n", i, kret);
            exit(0);
        }

        x86_thread_state64_t thread_state;
        mach_msg_type_number_t stateCount = x86_THREAD_STATE64_COUNT;

        thread_get_state(threadList[i], x86_THREAD_STATE64, (thread_state_t) &thread_state, &stateCount);
        if (kret!=KERN_SUCCESS) {
            printf("thread_get_state(%d) failed with error %d!\n", i, kret);
            exit(0);
        }

        printf("old __rip for %d is %llx\n", i, thread_state.__rip);
        thread_state.__rip += offset;
        printf("new __rip for %d is %llx\n", i, thread_state.__rip);

        thread_set_state(threadList[i], x86_THREAD_STATE64, (thread_state_t) &thread_state, stateCount);
        if (kret!=KERN_SUCCESS) {
            printf("thread_set_state(%d) failed with error %d!\n", i, kret);
            exit(0);
        }

        kret = thread_resume((thread_t) threadList[i]);
        if (kret!=KERN_SUCCESS) {
            printf("thread_resume(%d) failed with error %d!\n", i, kret);
            exit(0);
        }
    }

    printf("Instruction pointer modified\n");
}
