# Tweaks

The goal of this project is to be able to modify the programs you use, even if you don't have access to the source code. Being able to modify the system around you was one of the best attributes of the smalltalk systems, and made significantly easier by object-oriented programming because of the boundaries between objects. Because Objective-C was inspired by smalltalk, it retains some of the dynamic capabilities of smalltalk (most notably swizzling). Mach is also designed to let tasks control other tasks. Most Mach APIs (such as [mach_vm_allocate](https://developer.apple.com/documentation/kernel/1402376-mach_vm_allocate?language=objc), [vm_protect](https://developer.apple.com/documentation/kernel/1585294-vm_protect?language=objc) and [thread_create_running](https://developer.apple.com/documentation/kernel/1537886-thread_create_running?language=objc)) take as their first argument the task the operation is to be performed on, making it relatively trivial to modify another task's memory and rights.

There are many projects that are intended for reverse-engineering, such as [Frida](https://frida.re/) or [IDA](https://www.hex-rays.com/products/ida/). This project will contain/does contain pieces that are intended for that. Most of it, however, is about modifying the programs themselves. When I worked at Apple, one of the things I really loved was having a feeling of agency over the software I used on a day-to-day basis. I was frustrated with how crash reports were logged as regular severity reports, so I filed a bug about it -- and it got fixed. Someone I know modified the camera app on their phone to have infinite zoom. My team made prototypes of various things on iOS, so instead of these things feeling sent from above and immutable they were something we could really think about and improve. I wanted to do something similar once I left, and that was what this project came out of.

In the long term I intend to have a UI based around something similar to the "capture view hierarchy" tool in Xcode where you can look at the entire view hierarchy and then modify any piece of it.

# Technical description

The main interface between the host and target processes can be found in the [Process class](injector_lib/Process.m). The Process class contains a number of methods that communicate to the target process and call one of the functions defined in [objc_runtime_getters.h](injected_library/objc_runtime_getters.h).

Currently, the main interface to talk to use the functions defined in the Process class is a simple CLI defined [here](daemon.m#L80). Eventually, there will be a UI that uses the Process class as its backend.

The code is fairly dirty most places because it is still in the works - once i have some kind of working UI I intend to clean it up more and do more things with it.

# Building

In order to build the project, you must disable SIP and then run `sudo mount -uw /`. This is necessary because the way we run code in the target process is with a dynamic library, and that library is put in `/usr/lib` to avoid sandboxing issues. In the future it may not be necessary to do this if you want to modify unsandboxed processes, but for the moment that is necessary. Also, you must create the directory `/usr/lib/injected` because that is where XCode is currently set to place the injected dylib.
