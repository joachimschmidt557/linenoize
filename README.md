# zig-linenoise

A not 100%-accurate port of [linenoise](https://github.com/antirez/linenoise) to
zig. It currently relies on libc for `termios` and `ioctl`.

## ToDo

- [x] Line editing
- [x] Completions
- [x] Hints
- [x] History
- [ ] Multi line mode
- [x] Mask input mode
