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

#include <mach/vm_map.h>

#define MACH_CALL(kret) if (kret != 0) {printf("Mach call on line %d failed with error \"%s\".\n", __LINE__, mach_error_string(kret));}

unsigned char * readProcessMemory (task_t task, mach_vm_address_t addr, mach_msg_type_number_t *size) {
    vm_offset_t readMem;
    // Use vm_read, rather than mach_vm_read, since the latter is different
    // in iOS.

    kern_return_t kr = vm_read(task,        // vm_map_t target_task,
                 addr,     // mach_vm_address_t address,
                 *size,     // mach_vm_size_t size
                 &readMem,     //vm_offset_t *data,
                 size);     // mach_msg_type_number_t *dataCnt

    if (kr) {
        // DANG..
        fprintf (stderr, "Unable to read target task's memory @%p - kr 0x%x\n" , (void *)addr, kr);
        return NULL;
    }

    return ( (unsigned char *) readMem);

}

struct dyld_image_info * get_dylibs(task_t task, int *size) {
    task_dyld_info_data_t task_dyld_info;
    mach_msg_type_number_t count = TASK_DYLD_INFO_COUNT;
    
    MACH_CALL(task_info(task, TASK_DYLD_INFO, (task_info_t)&task_dyld_info, &count));
    
    unsigned int dyld_all_image_infos_size = sizeof(struct dyld_all_image_infos);
    struct dyld_all_image_infos *dyldaii = (struct dyld_all_image_infos *) readProcessMemory(task, task_dyld_info.all_image_info_addr, &dyld_all_image_infos_size);
    
    
    printf ("Version: %d, %d images at offset %p\n", dyldaii->version, dyldaii->infoArrayCount, dyldaii->infoArray);
    int imageCount = dyldaii->infoArrayCount;
    mach_msg_type_number_t dataCnt = imageCount * sizeof(struct dyld_image_info);
    unsigned char * readData = readProcessMemory(task, (mach_vm_address_t) dyldaii->infoArray, &dataCnt);
    if (!readData) { return NULL;}

    struct dyld_image_info *dii = (struct dyld_image_info *) readData;
    
    // This one will only have images with a name
    struct dyld_image_info *images = (struct dyld_image_info *) malloc(dataCnt);
    int images_index = 0;
    
    for (int i = 0; i < imageCount; i++) {
        dataCnt = 1024;
        char *imageName = (char *) readProcessMemory (task, (mach_vm_address_t) dii[i].imageFilePath, &dataCnt);
        if (imageName) {
            printf("Found image: %s\n", imageName);
            images[images_index].imageFilePath = imageName;
            images[images_index].imageLoadAddress = dii[i].imageLoadAddress;
            images_index++;
        }
    }
    
    // In theory we should be freeing readData and dyldaii, but it's not malloc'd, so I'd need to use mach_vm_deallocate, which I don't care about.
    // I'm pretty sure this function leaks memory, but I'm not sure.
    
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
        printf("task_threads() failed with error %d!\n", kret);
        return -1;
    }
    
    printf("Suspending threads.\n");
    
    for (int i = 0; i < threadCount; i++) {
        kret = thread_suspend((thread_t) threadList[i]);
        if (kret!=KERN_SUCCESS) {
            printf("thread_suspend(%d) failed with error %d!\n", i, kret);
            return -1;
        }
    }
    
    return 0;
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
    printf("info fname is %s\n", info.dli_fname);
    return sym_loc - info.dli_fbase;
}

// 1a78

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
    
    /*if (pause_threads(task) != 0) {
        printf("pause_threads failed!\n");
        exit(1);
    }*/
    
    int size = 0;
    struct dyld_image_info * dylibs = get_dylibs(task, &size);
    printf("Got %d dylibs\n", size);
    if (dylibs == NULL) {
        printf("Getting dylibs failed.\n");
        exit(1);
    }
    mach_vm_address_t libSystem_address = find_dylib(dylibs, size, "/usr/lib/system/libsystem_kernel.dylib");
    printf("Got libsystem address\n");
    if (libSystem_address == -1) {
        printf("Getting libSystem_address failed\n");
        exit(1);
    }
    
    int offset = get_symbol_offset("/usr/lib/system/libsystem_kernel.dylib", "write");
    printf("Discovered offset to be %d. Regular one is %d.\n", offset, 0x1a78);
    mach_vm_address_t write_address = libSystem_address + offset; // There's some kind of syscall for determining this, but I determined this with `nm -gU`
    
    printf("write_address is %p\n", (void *) write_address);
    
    thread_act_t thread_port;
    // Create thread
    MACH_CALL(thread_create(task, &thread_port));
    printf("Created thread %d\n", thread_port);
    
    vm_address_t stack_address;
    // Allocate stack
    MACH_CALL(vm_allocate(task, &stack_address, 0x200000, TRUE)); // 2MB of stack
    printf("Allocated stack at address %p\n", (void *)stack_address);
    
    vm_address_t play_memory;
    MACH_CALL(vm_allocate(task, &play_memory, 0x800, TRUE)); // 2KB of scratch space
    printf("Allocated 2KB of play memory at address %p\n", (void *)play_memory);
    
    char *sentence = "One small step for computer, etc. etc.\n";
    int sentence_len = strlen(sentence);
    vm_write(task, play_memory, (vm_offset_t) sentence, sentence_len);
        
    x86_thread_state64_t *thread_state = calloc(1, x86_THREAD_STATE64_COUNT);
    
    printRegisterState(thread_state);
    
    // General register setting
    thread_state -> __rsp = stack_address;
    thread_state -> __rbp = stack_address; // Pretty sure we start out with rsp == rbp
    thread_state -> __rip = write_address; // Address of write function in libSystem
    thread_state -> __cs = stack_address;
    
    // ssize_t write(int fildes, const void *buf, size_t nbyte);
    
    // Emulate C calling convention
    thread_state -> __rdi = 1; // fildes = stdout
    thread_state -> __rsi = play_memory; // buf = beginning of sentence
    thread_state -> __rdx = sentence_len; // nbyte = sentence length
    
    printRegisterState(thread_state);
        
    thread_set_state(thread_port, x86_THREAD_STATE64, (thread_state_t) thread_state, x86_THREAD_STATE64_COUNT);
    
    thread_resume(thread_port);
}
