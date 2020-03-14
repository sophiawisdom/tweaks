//
//  injected_library.h
//  daemon
//
//  Created by Sophia Wisdom on 3/1/20.
//  Copyright © 2020 Sophia Wisdom. All rights reserved.
//

#ifndef injected_library_h
#define injected_library_h

// Defined more in objc_runtime_getters.h
typedef enum {
    NO_COMMAND,
    GET_IMAGES,
    GET_CLASSES_FOR_IMAGE,
    GET_METHODS_FOR_CLASS,
    GET_SUPERCLASS_FOR_CLASS
} command_type;

// Once this is set, target process will begin processing data
#define NEW_IN_DATA 0x12345678
// Once this is set, the target process' response has completed
#define NEW_OUT_DATA 0x87654321

#define SEM_PORT_NAME 0x83452 // Randomly generated port name. This will be how the target task can access the semaphore

// First bytes of output shmem will be this.
typedef struct data_out {
    uint64_t shmem_offset; // Offset from *shmem_loc
    uint64_t len;
} data_out;

// The first
typedef struct command_in {
    command_type cmd; // Type indicating how this command should be processed.
    
    // Pseudo NSData
    data_out arg;
} command_in;

uint64_t shmem_loc; // Shared memory address in target process. The correct value of this will be injected by the host process.

// First 8 bytes are for the data indicator
// 0 until there is a new command, whereupon it is set to not-0.
// When the command has been processed, set back to 0 again.

#endif /* injected_library_h */
