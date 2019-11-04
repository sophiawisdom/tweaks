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

unsigned char * readProcessMemory (task_t task, mach_vm_address_t addr, mach_msg_type_number_t *size) {
    vm_offset_t readMem;
    // Use vm_read, rather than mach_vm_read, since the latter is different
    // in iOS.

    MACH_CALL(vm_read(task, // vm_map_t target_task,
                 addr,               // mach_vm_address_t address,
                 *size,              // mach_vm_size_t size
                 &readMem,           // vm_offset_t *data,
                 size), FALSE);              // mach_msg_type_number_t *dataCnt

    return ( (unsigned char *) readMem);

}


/**
 * Get all the dylibs in a task. dyld_image_info has a
 */
struct dyld_image_info * get_dylibs(task_t task, int *size) {
    task_dyld_info_data_t task_dyld_info;
    mach_msg_type_number_t count = TASK_DYLD_INFO_COUNT;
    
    MACH_CALL(task_info(task, TASK_DYLD_INFO, (task_info_t)&task_dyld_info, &count), FALSE);
    // If you call task_info with the TASK_DYLD_INFO flavor, it'll give you information about dyld - specifically, where is the struct
    // that lists out the location of all the dylibs in the other process' memory. I think this can eventually be painfully discovered
    // using mmap, but this way is much easier.
    
    unsigned int dyld_all_image_infos_size = sizeof(struct dyld_all_image_infos);
    
    // Every time there's a pointer, we have to read out the resulting data structure.
    struct dyld_all_image_infos *dyldaii = (struct dyld_all_image_infos *) readProcessMemory(task, task_dyld_info.all_image_info_addr, &dyld_all_image_infos_size);
    
    
    int imageCount = dyldaii->infoArrayCount;
    mach_msg_type_number_t dataCnt = imageCount * sizeof(struct dyld_image_info);
    struct dyld_image_info * dii = (struct dyld_image_info *) readProcessMemory(task, (mach_vm_address_t) dyldaii->infoArray, &dataCnt);
    if (!dii) { return NULL;}
    
    // This one will only have images with a name
    struct dyld_image_info *images = (struct dyld_image_info *) malloc(dataCnt);
    int images_index = 0;
    
    for (int i = 0; i < imageCount; i++) {
        dataCnt = 1024;
        char *imageName = (char *) readProcessMemory(task, (mach_vm_address_t) dii[i].imageFilePath, &dataCnt);
        if (imageName) {
            images[images_index].imageFilePath = imageName;
            images[images_index].imageLoadAddress = dii[i].imageLoadAddress;
            images_index++;
        }
    }
    
    // In theory we should be freeing dii and dyldaii, but it's not malloc'd, so I'd need to use mach_vm_deallocate or something, which I don't care about.
    // This function probably leaks memory, but I'm not super sure.
    
    *size = images_index;
    
    return images;
}

mach_vm_address_t find_dylib(struct dyld_image_info * dyld_image_info, int size, const char *image_name) {
    for (int i = 0; i < size; i++) {
        if (strcmp(image_name, dyld_image_info[i].imageFilePath) == 0) {
            return (mach_vm_address_t) dyld_image_info[i].imageLoadAddress;
        }
    }
    return -1;
}

int pause_threads(task_t task) {
    thread_act_port_array_t threadList;
    mach_msg_type_number_t threadCount;
    
    int kret = task_threads(task, &threadList, &threadCount);
    if (kret!=KERN_SUCCESS) {
        return kret;
    }
    
    printf("Suspending threads.\n");
    
    for (int i = 0; i < threadCount; i++) {
        kret = thread_suspend((thread_t) threadList[i]);
        if (kret!=KERN_SUCCESS) {
            return kret;
        }
    }
    
    return KERN_SUCCESS;
}

int resume_threads(task_t task) {
    thread_act_port_array_t threadList;
    mach_msg_type_number_t threadCount;
    
    int kret = task_threads(task, &threadList, &threadCount);
    if (kret!=KERN_SUCCESS) {
        return kret;
    }
    
    printf("Resuming threads.\n");
    
    for (int i = 0; i < threadCount; i++) {
        kret = thread_resume((thread_t) threadList[i]);
        if (kret!=KERN_SUCCESS) {
            printf("Failed on thread %d (%d)\n", i, threadList[i]);
            return kret;
        }
    }
    
    return KERN_SUCCESS;
}

void printRegisterState(x86_thread_state64_t *thread_state) {
    printf("rax: %llx\trbx: %llx\trcx: %llx\trdx: %llx\trdi: %llx\trsi: %llx\trbp: %llx\trsp: %llx\tr8: %llx\tr9: %llx\tr10: %llx\tr11: %llx\tr12: %llx\tr13: %llx\tr14: %llx\tr15: %llx\n", thread_state -> __rax, thread_state -> __rbx, thread_state -> __rcx, thread_state -> __rdx, thread_state -> __rdi, thread_state -> __rsi, thread_state -> __rbp, thread_state -> __rsp, thread_state -> __r8, thread_state -> __r9, thread_state -> __r10, thread_state -> __r11, thread_state -> __r12, thread_state -> __r13, thread_state -> __r14, thread_state -> __r15);
}

int get_symbol_offset(const char *dylib_path, const char *symbol_name) {
    void *handle = dlopen(dylib_path, RTLD_LAZY);
    void *sym_loc = dlsym(handle, symbol_name);
    Dl_info info;
    int result = dladdr(sym_loc, &info);
    if (result == 0) {
        printf("dladdr call failed: %d\n", result);
        return -1;
    }
    dlclose(handle);
    return sym_loc - info.dli_fbase;
}

int execute_symbol_with_args(task_t task, const char *dylib, const char *symbol, unsigned long long arg1, unsigned long long arg2, unsigned long long arg3) {
    MACH_CALL(pause_threads(task), TRUE);
    
    int size = 0;
    struct dyld_image_info * dylibs = get_dylibs(task, &size);
    if (dylibs == NULL) {
        printf("Getting dylibs failed.\n");
        return -1;
    }
    
    mach_vm_address_t dylib_address = find_dylib(dylibs, size, dylib);
    if (dylib_address == -1) {
        printf("Getting libSystem_address failed\n");
        return -1;
    }
    
    int offset = get_symbol_offset(dylib, symbol);
    mach_vm_address_t dylib_symbol_address = dylib_address + offset;
        
    thread_act_t thread_port;
    // Create thread
    MACH_CALL(thread_create(task, &thread_port), TRUE);
    
    vm_address_t stack_bottom;
    // Allocate stack
    MACH_CALL(vm_allocate(task, &stack_bottom, 2*1024*1024, TRUE), TRUE); // 2MB of stack
    vm_address_t stack_top = stack_bottom + 2*1024*1024; // stack starts at top
    // copy stack_top and then decrement it when writing.
    
    vm_address_t code_address;
    // Last vm_allocate parameter is the flags, which only has one value, "anywhere". defined here: https://purplefish.apple.com/index.php?action=search_cached&path=osfmk%2Fvm%2Fvm_user.c&version=xnu-6153.2.3&project=xnu&q=mach_vm_allocate_external&language=all&index=Yukon#line176
    MACH_CALL(vm_allocate(task, &code_address, 1024, TRUE), TRUE); // 1kb of code
    char instructions[3] = { 0x41, 0xFF, 0xE7 }; // jmp r15; from https://defuse.ca/online-x86-assembler.htm
    MACH_CALL(vm_write(task, code_address, (vm_offset_t) instructions, sizeof(instructions)), TRUE);

    x86_thread_state64_t *thread_state = calloc(1, x86_THREAD_STATE64_COUNT);
    
    printRegisterState(thread_state);
    
    // General register setting
    thread_state -> __rsp = stack_top;
    thread_state -> __rbp = stack_top; // Pretty sure we start out with rsp == rbp
    thread_state -> __rip = code_address;
    thread_state -> __r15 = dylib_symbol_address; // Address of symbol in dylib in other task
    thread_state -> __cs = dylib_symbol_address;
            
    // Emulate C calling convention
    thread_state -> __rdi = arg1;
    thread_state -> __rsi = arg2;
    thread_state -> __rdx = arg3;
    // TODO: do more of the C calling convention.
    
    printRegisterState(thread_state);
        
    MACH_CALL(thread_set_state(thread_port, x86_THREAD_STATE64, (thread_state_t) thread_state, x86_THREAD_STATE64_COUNT), TRUE);
    
    MACH_CALL(resume_threads(task), TRUE);
    return 0;
}

int main(int argc, char **argv) {
    int pid = 0;
    if (argc > 1) {
        pid = atoi(argv[1]);
    }
    if (pid == 0) {
        printf("Input PID to pause: ");
        scanf("%d", &pid);
    }
    
    printf("PID is: %d\n", pid);
    
    mach_port_name_t task = MACH_PORT_NULL;
    MACH_CALL(task_for_pid(mach_task_self(), pid, &task), TRUE);
    
    vm_address_t play_memory;
    MACH_CALL(vm_allocate(task, &play_memory, 0x800, TRUE), TRUE); // 2KB of scratch space
    printf("Allocated 2KB of play memory at address %p\n", (void *)play_memory);
    
    char *sentence = "One small step for mach and one s\n";
    int sentence_len = strlen(sentence);
    MACH_CALL(vm_write(task, play_memory, (vm_offset_t) sentence, sentence_len), TRUE);
    
    execute_symbol_with_args(task, "/usr/lib/system/libsystem_kernel.dylib", "write", 1, play_memory, sentence_len);
}
