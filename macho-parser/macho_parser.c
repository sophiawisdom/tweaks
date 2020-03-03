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
    if (check_magic(magic_number)) {
        fprintf(stderr, "[-] not a mach-o binary file.\n");
        return 0;
    }
        
    struct mach_header_64 *header = (struct mach_header_64 *)map; // Add parsing for this later
    
//    printf("running\n");
    
    struct load_command *current_command = (uint64_t)header + sizeof(struct mach_header_64);
    for (int i = 0; i < header -> ncmds; i++) {
        int cmd = current_command -> cmd;
        if (cmd == LC_SEGMENT_64) {
            struct segment_command_64 *seg_command = current_command;
            struct section_64 * section = ((uint64_t)seg_command + sizeof(struct segment_command_64));
            for (int j = 0; j < seg_command -> nsects; j++) {
//                printf("Found section %s,%s ", seg_command -> segname, section -> sectname);
                if ((section -> flags & SECTION_TYPE) == S_LAZY_SYMBOL_POINTERS) {
//                    printf("Offset is %x\n", section -> reserved1);
                }
//                printf("Section type: 0x%x. Section flags: 0x%x. Total flags 0x%x\n", section -> flags & SECTION_TYPE, section -> flags & SECTION_ATTRIBUTES, section -> flags);
                section++;
            }
        } else if (cmd == LC_LOAD_DYLIB /* potentially add weak dylib etc. */) {
        } else if (cmd == LC_ID_DYLIB) {
        } else if (cmd == LC_SYMTAB) {
            struct symtab_command *symbols = current_command;
            char *string_list = (uint64_t)header + symbols -> stroff;
            struct nlist_64 *nlist = (uint64_t)header + symbols -> symoff; // Symbol offset is from the header...
//            printf("Hit symtab\n");
            for (int j = 0; j < symbols -> nsyms; j++) {
                char *sym = string_list + nlist -> n_un.n_strx;
                if (strcmp(sym, symbol) == 0 && nlist -> n_value != 0) {
                    uint64_t val = nlist -> n_value; // disappears after munmap()
                    close(fd);
                    munmap(map, st.st_size);
                    return val;
                }
                nlist++; // maybe do something clever with initializing this with the for loop
            }
        } else if (cmd == LC_DYSYMTAB) {
            // printf("Encountered dsymtab\n");
        }
        
        current_command = (uint64_t)current_command + current_command -> cmdsize;
    }
    
    fprintf(stderr, "Unable to find symbol\n");
    
    close(fd);
    munmap(map, st.st_size);
    
    return 0;
}
