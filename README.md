# tweaks

*This project is very much not done yet.*

Final goal is to be able to do runtime code reloading in a process without that process being aware. This is objectively cursed, but it is technically possible (with `task_for_pid` and swizzling) so it must be done.

The injector app will do this for the simulator (so on your own app) but not on arbitrary apps like this aims to do. This can also run on iOS (in theory). The project originally came out of personal frustrations with developing on SpringBoard, which I felt would be easier if things could be interactively manipulable.

My long term goal is to have a sort of "process customizer" - something like the view debugger in XCode combined with some idea of the logic behind what's happening and a list of all classes and methods on those classes so processes can have arbitrary functionality added quickly. This added functionality can also be saved and sent across the network, similar to tweaks for jailbreaking.
