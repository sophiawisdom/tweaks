//
//  inject.h
//  daemon
//
//  Created by Sophia Wisdom on 2/29/20.
//  Copyright © 2020 Sophia Wisdom. All rights reserved.
//

#ifndef inject_h
#define inject_h

#include <sys/types.h>
#include <mach/mach_types.h>

task_t inject(task_t pid, const char *lib);

#endif /* inject_h */
