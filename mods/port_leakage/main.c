//
//  main.c
//  port_leakage
//
//  Created by William Wisdom on 1/17/20.
//  Copyright © 2020 William Wisdom. All rights reserved.
//

#include <stdio.h>
#include <unistd.h>
#include <stdlib.h>

#include <mach/port.h>
#include <mach/message.h>
#include <mach/mach_port.h>
#include <mach/mach_traps.h>

int port_count(mach_port_name_t task) {
    mach_port_name_array_t ports;
    mach_msg_type_number_t num_ports;
    mach_port_type_array_t types;
    mach_msg_type_number_t num_types;
    int kret = mach_port_names(task, &ports, &num_ports, &types, &num_types);
    if (kret != KERN_SUCCESS) {
        printf("Error with mach_port_names!\n");
        exit(1);
    }

    return num_ports;
}

int main(int argc, const char * argv[]) {
    pid_t child_pid = fork();
    if (child_pid == 0) {
        char output[5];
        read(0, output, 5); // dummy process
    }

    mach_port_name_t task = MACH_PORT_NULL;
    int kret = task_for_pid(task_self_trap(), child_pid, &task);
    if (kret != KERN_SUCCESS) {
        printf("Error with task_for_pid!\n");
        exit(1);
    }

    printf("Found %d ports before\n", port_count(task));

    char *shell_invocation;
    asprintf(&shell_invocation, "/usr/bin/sample %d .1 1", child_pid); // sample it only once
    int result = system(shell_invocation);
    if (result != 0) {
        printf("Got result %d from system\n", result);
        exit(1);
    }

    printf("Found %d ports after\n", port_count(task));
}
