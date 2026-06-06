# C source layout

- `app/`: program entry points and command startup code.
- `core/`: platform, filesystem, process, path, and Lua integration modules.
- `include/`: public headers shared by C modules.

Keep this tree shallow unless a module grows enough implementation detail to need its own directory.
