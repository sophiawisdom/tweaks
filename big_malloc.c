#include <stdio.h>
#include <stdlib.h>
#include <os/syscalls.h>

#define MACH_CALL(kret, critical) if (kret != 0) {\
printf("Mach call on line %d failed with error \"%s\".\n", __LINE__, mach_error_string(kret));\
if (critical) {exit(1);}\
}

int main() {
    vm_address_t big_memory;
    MACH_CALL(mach_vm_allocate(mach_task_self(), &big_memory, 0x1000000000, TRUE), TRUE);
    return 0;
}
