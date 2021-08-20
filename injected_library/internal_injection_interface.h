//
//  injected_library.h
//  daemon
//
//  Created by Sophia Wisdom on 3/1/20.
//  Copyright © 2020 Sophia Wisdom. All rights reserved.
//

#ifndef injected_library_h
#define injected_library_h

// Something to keep in mind is that if this links anything, those things have to be in /usr/lib/injected because otherwise there
// will be sandbox violations in sandboxed apps. injected_library and injector_lib are already set up to look in /usr/lib/injected
// for libraries, so that should be all you have to add.

// Defined more in objc_runtime_getters.h
typedef enum {
    NO_COMMAND,
    GET_IMAGES,
    GET_CLASSES_FOR_IMAGE,
    GET_METHODS_FOR_CLASS,
    GET_SUPERCLASS_FOR_CLASS,
    GET_EXECUTABLE_IMAGE,
    LOAD_DYLIB,
    REPLACE_METHODS,
    GET_PROPERTIES_FOR_CLASS,
    GET_WINDOWS,
    GET_IVARS,
    GET_IMAGE_FOR_CLASS,
    GET_LAYERS,
    DETACH_FROM_PROCESS,
    GET_WINDOW_IMAGE,
    DO_INVOCATION,
    GET_WINDOW_SIZE
} command_type;


// #define'd because this header is used in multiple object files straight up
#define layerImagesKey @"layerImages"
#define layerArrayKey @"layerArray"

// Once this is set, target process will begin processing data
#define NEW_IN_DATA 0x12345678
// Once this is set, the target process' response has completed
#define NEW_OUT_DATA 0x87654321

// TODO: consider changing this to be randomly generated per shared_inj build
#define SEM_PORT_NAME 0x834522 // Randomly generated port name. This will be how the target task can access the semaphore

// Full 4GB, so it's large enough for full TIFF layer outputs.
// No real cost to making it larger - memory won't be used unless we write to it.
#define MAP_SIZE 0x10000000

// First bytes of output shmem will be this.
typedef struct data_out {
    int64_t shmem_offset; // Offset from *shmem_loc
    int64_t len;
} data_out;

// The first
typedef struct command_in {
    command_type cmd; // Type indicating how this command should be processed.
    
    // Pseudo NSData
    data_out arg;
} command_in;

extern uint64_t shmem_loc; // Shared memory address in target process. The correct value of this will be injected by the host process.

#endif /* injected_library_h */
