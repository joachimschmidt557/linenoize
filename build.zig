const Builder = @import("std").build.Builder;

pub fn build(b: *Builder) void {
    const mode = b.standardReleaseOptions();
    const lib = b.addStaticLibrary("zig-linenoise", "src/main.zig");
    lib.setBuildMode(mode);
    lib.install();

    var main_tests = b.addTest("src/main.zig");
    main_tests.setBuildMode(mode);

    var example = b.addExecutable("example", "example.zig");

    const test_step = b.step("test", "Run library tests");
    test_step.dependOn(&main_tests.step);
}
