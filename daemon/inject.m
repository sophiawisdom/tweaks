//
//  inject.c
//  daemon
//

// Stolen from https://gist.github.com/knightsc/45edfc4903a9d2fa9f5905f60b02ce5a


#include "inject.h"
#include "symbol_locator.h"

#include <dlfcn.h>
#include <stdio.h>
#include <unistd.h>
#include <sys/types.h>
#include <mach/mach.h>
#include <mach/error.h>
#include <errno.h>
#include <stdlib.h>
#include <sys/sysctl.h>
#include <sys/mman.h>

#include <sys/stat.h>
#include <pthread.h>
#include <mach/mach_vm.h>

#define STACK_SIZE 65536
#define CODE_SIZE 128

//
// Based on http://newosxbook.com/src.jl?tree=listings&file=inject.c
// Updated to work on Mojave by creating a stub mach thread that then
// creates a real pthread. Injected mach thread is terminated to clean
// up as well.
//
// Due to popular request:
//
// Simple injector example (and basis of coreruption tool).
//
// If you've looked into research on injection techniques in OS X, you
// probably know about mach_inject. This tool, part of Dino Dai Zovi's
// excellent "Mac Hacker's Handbook" (a must read - kudos, DDZ) was
// created to inject code in PPC and i386. Since I couldn't find anything
// for x86_64 or ARM, I ended up writing my own tool.

// Since, this tool has exploded in functionality - with many other features,
// including scriptable debugging, fault injection, function hooking, code
// decryption,  and what not - which comes in *really* handy on iOS.
//
// coreruption is still closed source, due its highly.. uhm.. useful
// nature. But I'm making this sample free, and I have fully annotated this.
// The rest of the stuff you need is in Chapters 11 and 12 MOXiI 1, with more
// to come in the 2nd Ed (..in time for iOS 9 :-)
//
// Go forth and spread your code :-)
//
// J (info@newosxbook.com) 02/05/2014
//
// v2: With ARM64 -  06/02/2015 NOTE - ONLY FOR **ARM64**, NOT ARM32!
// Get the full bundle at - http://NewOSXBook.com/files/injarm64.tar
// with sample dylib and with script to compile this neatly.
//
//**********************************************************************
// Note ARM code IS messy, and I left the addresses wide apart. That's
// intentional. Basic ARM64 assembly will enable you to tidy this up and
// make the code more compact.
//
// This is *not* meant to be neat - I'm just preparing this for TG's
// upcoming OS X/iOS RE course (http://technologeeks.com/OSXRE) and thought
// this would be interesting to share. See you all in MOXiI 2nd Ed!
//**********************************************************************

// This sample code calls pthread_set_self to promote the injected thread
// to a pthread first - otherwise dlopen and many other calls (which rely
// on pthread_self()) will crash.
// It then calls dlopen() to load the library specified - which will trigger
// the library's constructor (q.e.d as far as code injection is concerned)
// and sleep for a long time. You can of course replace the sleep with
// another function, such as pthread_exit(), etc.
//
// (For the constructor, use:
//
// static void whicheverfunc() _ _attribute__((constructor));
//
// in the library you inject)
//
// Note that the functions are shown here as "_PTHRDSS", "DLOPEN__" and "SLEEP___".
// Reason being, that the above are merely placeholders which will be patched with
// the runtime addresses when code is actually injected.
char injectedCode[] =
    // "\xCC"                            // int3

    "\x55"                            // push       rbp
    "\x48\x89\xE5"                    // mov        rbp, rsp
    "\x48\x83\xEC\x10"                // sub        rsp, 0x10
    "\x48\x8D\x7D\xF8"                // lea        rdi, qword [rbp+var_8]
    "\x31\xC0"                        // xor        eax, eax
    "\x89\xC1"                        // mov        ecx, eax
    "\x48\x8D\x15\x21\x00\x00\x00"    // lea        rdx, qword ptr [rip + 0x21]
    "\x48\x89\xCE"                    // mov        rsi, rcx
    "\x48\xB8"                        // movabs     rax, pthread_create_from_mach_thread
    "PTHRDCRT"
    "\xFF\xD0"                        // call       rax
    "\x89\x45\xF4"                    // mov        dword [rbp+var_C], eax
    "\x48\x83\xC4\x10"                // add        rsp, 0x10
    "\x5D"                            // pop        rbp
    "\x48\xc7\xc0\x13\x0d\x00\x00"    // mov        rax, 0xD13
    "\xEB\xFE"                        // jmp        0x0
    "\xC3"                            // ret

    "\x55"                            // push       rbp
    "\x48\x89\xE5"                    // mov        rbp, rsp
    "\x48\x83\xEC\x10"                // sub        rsp, 0x10
    "\xBE\x01\x00\x00\x00"            // mov        esi, 0x1
    "\x48\x89\x7D\xF8"                // mov        qword [rbp+var_8], rdi
    "\x48\x8D\x3D\x1D\x00\x00\x00"    // lea        rdi, qword ptr [rip + 0x2c]
    "\x48\xB8"                        // movabs     rax, dlopen
    "DLOPEN__"
    "\xFF\xD0"                        // call       rax
    "\x31\xF6"                        // xor        esi, esi
    "\x89\xF7"                        // mov        edi, esi
    "\x48\x89\x45\xF0"                // mov        qword [rbp+var_10], rax
    "\x48\x89\xF8"                    // mov        rax, rdi
    "\x48\x83\xC4\x10"                // add        rsp, 0x10
    "\x5D"                            // pop        rbp
    "\xC3"                            // ret

    "LIBLIBLIBLIB"
    "\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00"
    "\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00"
    "\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00"
    "\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00"
    "\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00"
    "\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00"
    "\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00"
    "\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00"
    "\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00"
    "\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00"
    "\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00"
    "\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00"
    "\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00"
    "\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00"
    "\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00"
    "\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00"
    "\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00";

task_t inject(task_t remoteTask, const char *lib)
{
    struct stat buf;

    /**
     * First, check we have the library. Otherwise, we won't be able to inject..
     */
    int rc = stat(lib, &buf);
    if (rc != 0) {
        fprintf(stderr, "Unable to open library file %s (%s) - Cannot inject\n", lib, strerror(errno));
        //return (-9);
    }

    mach_error_t kr = 0;

    /**
     * From here on, it's pretty much straightforward -
     * Allocate stack and code. We don't really care *where* they get allocated. Just that they get allocated.
     * So, first, stack:
     */
    mach_vm_address_t remoteStack64 = (vm_address_t)NULL;
    mach_vm_address_t remoteCode64 = (vm_address_t)NULL;
    kr = mach_vm_allocate(remoteTask, &remoteStack64, STACK_SIZE, VM_FLAGS_ANYWHERE);
    if (kr != KERN_SUCCESS) {
        fprintf(stderr, "Unable to allocate memory for remote stack in thread: Error %s\n", mach_error_string(kr));
        return (-2);
    }
    
    /**
     * Then we allocate the memory for the thread
     */
    remoteCode64 = (vm_address_t)NULL;
    kr = mach_vm_allocate(remoteTask, &remoteCode64, CODE_SIZE, VM_FLAGS_ANYWHERE);
    if (kr != KERN_SUCCESS) {
        fprintf(stderr, "Unable to allocate memory for remote code in thread: Error %s\n", mach_error_string(kr));
        return (-2);
    }

    /**
     * Patch code before injecting: That is, insert correct function addresses (and lib name) into placeholders
     *
     * Since we use the same shared library cache as our victim, meaning we can use memory addresses from
     * OUR address space when we inject..
     */
    
    int size = 0;
    struct dyld_image_info * dylibs = get_dylibs(remoteTask, &size);
    mach_vm_address_t addrOfPthreadCreate = get_symbol(dylibs, size, "/usr/lib/system/libsystem_pthread.dylib", "pthread_create_from_mach_thread");
    mach_vm_address_t addrOfDlopen = get_symbol(dylibs, size, "/usr/lib/system/libdyld.dylib", "dlopen");
    //mach_vm_address_t addrOfPrintf = getSymbol(dylibs, size, "/usr/lib/system/libsystem_c.dylib", "printf");
    
    free(dylibs);

    int i = 0;
    char *possiblePatchLocation = (injectedCode);
    for (i = 0; i < 0x100; i++) {
        // Patching is crude, but works.
        //
        possiblePatchLocation++;

        if (memcmp(possiblePatchLocation, "PTHRDCRT", 8) == 0) {
            memcpy(possiblePatchLocation, &addrOfPthreadCreate, 8);
        }

        if (memcmp(possiblePatchLocation, "DLOPEN__", 6) == 0) {
            memcpy(possiblePatchLocation, &addrOfDlopen, sizeof(uint64_t));
        }

        if (memcmp(possiblePatchLocation, "LIBLIBLIB", 9) == 0) {
            strcpy(possiblePatchLocation, lib);
        }
    }

    /**
        * Write the (now patched) code
      */
    kr = mach_vm_write(remoteTask,                 // Task port
                       remoteCode64,               // Virtual Address (Destination)
                       (vm_address_t)injectedCode, // Source
                       sizeof(injectedCode));      // Length of the source

    if (kr != KERN_SUCCESS) {
        fprintf(stderr, "Unable to write remote thread memory: Error %s\n", mach_error_string(kr));
        return (-3);
    }

    /*
     * Mark code as executable - This also requires a workaround on iOS, btw.
     */
    kr = vm_protect(remoteTask, remoteCode64, sizeof(injectedCode), FALSE, VM_PROT_READ | VM_PROT_EXECUTE);

    /*
        * Mark stack as writable  - not really necessary
     */
    kr = vm_protect(remoteTask, remoteStack64, STACK_SIZE, TRUE, VM_PROT_READ | VM_PROT_WRITE);
    if (kr != KERN_SUCCESS) {
        fprintf(stderr, "Unable to set memory permissions for remote thread: Error %s\n", mach_error_string(kr));
        return (-4);
    }

    /*
     * Create thread - This is obviously hardware specific.
     */
    x86_thread_state64_t remoteThreadState64;

    thread_act_t remoteThread;

    memset(&remoteThreadState64, '\0', sizeof(remoteThreadState64));

    remoteStack64 += (STACK_SIZE / 2); // this is the real stack
                                       //remoteStack64 -= 8;  // need alignment of 16

    const char *p = (const char *)remoteCode64;

    remoteThreadState64.__rip = (u_int64_t)(vm_address_t)remoteCode64;

    // set remote Stack Pointer
    remoteThreadState64.__rsp = (u_int64_t)remoteStack64;
    remoteThreadState64.__rbp = (u_int64_t)remoteStack64;

    /*
     * create thread and launch it in one go
     */
    kr = thread_create_running(remoteTask, x86_THREAD_STATE64,
                               (thread_state_t)&remoteThreadState64, x86_THREAD_STATE64_COUNT, &remoteThread);
    if (kr != KERN_SUCCESS) {
        fprintf(stderr, "Unable to create remote thread: error %s", mach_error_string(kr));
        return (-3);
    }

    // Wait for mach thread to finish
    mach_msg_type_number_t thread_state_count = x86_THREAD_STATE64_COUNT;
    for (;;) {
        kr = thread_get_state(remoteThread, x86_THREAD_STATE64, (thread_state_t)&remoteThreadState64, &thread_state_count);
        if (kr != KERN_SUCCESS) {
            fprintf(stderr, "Error getting stub thread state: error %s", mach_error_string(kr));
            break;
        }
        
        if (remoteThreadState64.__rax == 0xD13) {
            kr = thread_terminate(remoteThread);
            if (kr != KERN_SUCCESS) {
                fprintf(stderr, "Error terminating stub thread: error %s", mach_error_string(kr));
            }
            break;
        }
    }

    return remoteTask;
}
