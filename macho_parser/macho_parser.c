//
//  macho_parser.c
//  macho-parser
//
//  Created by Sophia Wisdom on 3/1/20.
//  Copyright © 2020 Sophia Wisdom. All rights reserved.
//

#include "macho_parser.h"

#include <assert.h>
#include <fcntl.h>
#include <pwd.h>
#include <stdarg.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/mman.h>
#include <sys/stat.h>
#include <sys/types.h>
#include <time.h>
#include <unistd.h>

#include <mach-o/arch.h>
#include <mach-o/fat.h>
#include <mach-o/loader.h>
#include <mach-o/nlist.h>
#include <mach-o/swap.h>
#include <mach-o/stab.h>

int check_magic(uint32_t magic) {
    return !(magic == MH_MAGIC || magic == MH_CIGAM ||
             magic == MH_MAGIC_64 || magic == MH_CIGAM_64 ||
             magic == FAT_MAGIC || magic == FAT_CIGAM);
}

char *getNameForDylib(struct dylib_command *load_command) {
    struct dylib dyl = load_command -> dylib;
    return (char *)load_command + dyl.name.offset;
}

uint64_t getSymbolOffset(const char *dylib, char *symbol) {
    int fd;
    if ((fd = open(dylib, O_RDONLY)) < 0) {
        fprintf(stderr, "[-] could not open() %s...\n", dylib);
        return 0;
    }
    
    lseek(fd, 0, SEEK_SET);
    struct stat st;
    if (fstat(fd, &st) < 0) {
        fprintf(stderr, "[-] unable to stat().\n");
        return 0;
    }
    
    void* map = mmap(NULL, st.st_size, PROT_READ, MAP_PRIVATE, fd, 0);
    if (map == MAP_FAILED) {
        fprintf(stderr, "[-] could not mmap().\n");
        return 0;
    }
    
    uint32_t magic_number;
    read(fd, &magic_number, sizeof magic_number);
    printf("Magic number is %d\n", magic_number);
    if (check_magic(magic_number)) {
        fprintf(stderr, "[-] not a mach-o binary file.\n");
        return 0;
    }
        
    struct mach_header_64 *header = (struct mach_header_64 *)map; // Add parsing for this later
        
    struct load_command *current_command = (uint64_t)header + sizeof(struct mach_header_64);
    for (int i = 0; i < header -> ncmds; i++) {
        int cmd = current_command -> cmd;
        if (cmd == LC_SYMTAB) {
            struct symtab_command *symbols = current_command;
            char *string_list = (char *)header + symbols -> stroff;
            struct nlist_64 *nlist = (uint64_t)header + symbols -> symoff; // Symbol offset is from the header...
            for (int j = 0; j < symbols -> nsyms; j++) {
                char *sym = string_list + nlist -> n_un.n_strx;
                if (strcmp(sym, symbol) == 0 && nlist -> n_value != 0) {
                    uint64_t val = nlist -> n_value; // disappears after munmap()
                    if ((j+1) < symbols -> nsyms) {
                        uint64_t next_val = (nlist+1) -> n_value;
                        printf("val extends from %llu to %llu (size %lld)\n", val, next_val, next_val - val);
                    }
                    close(fd);
                    munmap(map, st.st_size);
                    return val;
                }
                
                nlist++; // maybe do something clever with initializing this with the for loop
            }
        } else {
            printf("got a command of type %d\n", cmd);
        }
        
        current_command = (uint64_t)current_command + current_command -> cmdsize;
    }
    
    fprintf(stderr, "Unable to find symbol\n");
    
    close(fd);
    munmap(map, st.st_size);
    
    return 0;
}
