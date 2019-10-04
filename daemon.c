#include <mach/mach_init.h>
#include <mach/thread_act.h>
#include <mach/task.h>
#include <mach/port.h>
#include <sys/wait.h>
#include <unistd.h>
#include <stdio.h>
#include <stdlib.h>
#include <mach/mach_vm.h>

void increaseIfNotPointer(__uint64_t *reg, mach_port_name_t task) {
    __uint64_t reg_value = *reg;
    if (reg_value > 0x100000000) {
        // if (pointer)
                
        vm_offset_t receiver = 0;
        mach_msg_type_number_t bytes_read = 0;
        mach_vm_size_t memory_read_size = 1;
        
        printf("About to mach_vm_read reg_value %llx\n", reg_value);
        
        mach_vm_read(task, reg_value, memory_read_size, &receiver, &bytes_read);
        ((char *)receiver)[0] += 1; // Increment the first byte of the memory by one
        mach_vm_write(task, reg_value, receiver, bytes_read);
        
//        printf("Size is %d. First eight bytes: %llx\n", bytes_read, *(unsigned long long*)receiver);
    }
}

void printRegisterState(x86_thread_state64_t *thread_state) {
    
}

void modify_thread_state(x86_thread_state64_t *thread_state, mach_port_name_t task) {
    increaseIfNotPointer(&(thread_state -> __rax), task);
    increaseIfNotPointer(&(thread_state -> __rbx), task);
    increaseIfNotPointer(&(thread_state -> __rcx), task);
    increaseIfNotPointer(&(thread_state -> __rdx), task);
    increaseIfNotPointer(&(thread_state -> __rdi), task);
    increaseIfNotPointer(&(thread_state -> __rsi), task);
    increaseIfNotPointer(&(thread_state -> __rbp), task);
    increaseIfNotPointer(&(thread_state -> __rsp), task);
    increaseIfNotPointer(&(thread_state -> __r8), task);
    increaseIfNotPointer(&(thread_state -> __r9), task);
    increaseIfNotPointer(&(thread_state -> __r10), task);
    increaseIfNotPointer(&(thread_state -> __r11), task);
    increaseIfNotPointer(&(thread_state -> __r12), task);
    increaseIfNotPointer(&(thread_state -> __r13), task);
    increaseIfNotPointer(&(thread_state -> __r14), task);
    increaseIfNotPointer(&(thread_state -> __r15), task);
}

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
    
    printf("PID is: %d\n", pid);

    kret = task_for_pid(mach_task_self(), pid, &task);
    if (kret != KERN_SUCCESS) {
        printf("task_for_pid() failed with error %d!\n",kret);
        exit(0);
    }
    
    mach_vm_region_recurse(
    
    // proc_regionfilename in libproc: https://opensource.apple.com/source/xnu/xnu-2422.1.72/libsyscall/wrappers/libproc/libproc.h.auto.html
    
    printf("Registers modified\n");
}
