#include <mach/mach_init.h>
#include <mach/thread_act.h>
#include <mach/task.h>
#include <mach/port.h>
#include <libproc.h>
#include <sys/wait.h>
#include <unistd.h>
#include <stdio.h>
#include <stdlib.h>
#include <mach/mach_vm.h>
#include <mach-o/dyld_images.h>
#include <string.h>
#include <dlfcn.h>
#include <fcntl.h>

#include <mach/vm_map.h>

#define MACH_CALL(kret, critical) if (kret != 0) {\
printf("Mach call on line %d failed with error \"%s\".\n", __LINE__, mach_error_string(kret));\
if (critical) {exit(1);}\
}

x86_thread_state64_t get_thread_state(task_t task) {
    thread_act_port_array_t threadList;
    mach_msg_type_number_t threadCount;
    
    MACH_CALL(task_threads(task, &threadList, &threadCount), TRUE);
    
    x86_thread_state64_t old_state;
    mach_msg_type_number_t stateCount = x86_THREAD_STATE64_COUNT;
    
    MACH_CALL(thread_get_state(threadList[0], x86_THREAD_STATE64, (thread_state_t) &old_state, &stateCount), TRUE);
    
    return old_state;
}

void printRegisterState(x86_thread_state64_t *thread_state) {
    printf("rax: %llx\trbx: %llx\trcx: %llx\trdx: %llx\trdi: %llx\trsi: %llx\trbp: %llx\trsp: %llx\tr8: %llx\tr9: %llx\tr10: %llx\tr11: %llx\tr12: %llx\tr13: %llx\tr14: %llx\tr15: %llx\trip: %llx\tgs: %llx\t\n", thread_state -> __rax, thread_state -> __rbx, thread_state -> __rcx, thread_state -> __rdx, thread_state -> __rdi, thread_state -> __rsi, thread_state -> __rbp, thread_state -> __rsp, thread_state -> __r8, thread_state -> __r9, thread_state -> __r10, thread_state -> __r11, thread_state -> __r12, thread_state -> __r13, thread_state -> __r14, thread_state -> __r15, thread_state -> __rip, thread_state -> __gs);
}

int main(int argc, const char * argv[]) {
    x86_thread_state64_t thread_state = get_thread_state(mach_task_self());
    printRegisterState(&thread_state);
    
    dlopen("/users/williamwisdom/test.dylib", RTLD_NOW);
    
    thread_state = get_thread_state(mach_task_self());
    printRegisterState(&thread_state);
    
    thread_act_port_array_t threadList;
    mach_msg_type_number_t threadCount;
    
    MACH_CALL(task_threads(task, &threadList, &threadCount), TRUE);
    
    thread_state.__gs = 235235;
    
    thread_set_state(<#thread_act_t target_act#>, <#thread_state_flavor_t flavor#>, <#thread_state_t new_state#>, <#mach_msg_type_number_t new_stateCnt#>)
}
