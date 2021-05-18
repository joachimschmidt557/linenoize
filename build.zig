const Builder = @import("std").build.Builder;

pub fn build(b: *Builder) void {
    // Standard release options allow the person running `zig build` to select
    // between Debug, ReleaseSafe, ReleaseFast, and ReleaseSmall.
    const mode = b.standardReleaseOptions();

    // Static library
    const lib = b.addStaticLibrary("zig-linenoise", "src/c.zig");
    lib.setBuildMode(mode);
    lib.linkLibC();
    lib.install();

    const lib_step = b.step("library", "Build static library");
    lib_step.dependOn(&lib.step);

    // Tests
    var main_tests = b.addTest("src/main.zig");
    main_tests.setBuildMode(mode);

    const test_step = b.step("test", "Run library tests");
    test_step.dependOn(&main_tests.step);

    // Zig example
    var example = b.addExecutable("example", "examples/example.zig");
    example.addPackagePath("linenoise", "src/main.zig");
    example.setBuildMode(mode);

    var example_run = example.run();

    const example_step = b.step("example", "Run example");
    example_step.dependOn(&example_run.step);

    // C example
    var c_example = b.addExecutable("example", "examples/example.c");
    c_example.addIncludeDir("include");
    c_example.linkLibC();
    c_example.linkLibrary(lib);
    c_example.setBuildMode(mode);

    var c_example_run = c_example.run();

    const c_example_step = b.step("c-example", "Run C example");
    c_example_step.dependOn(&c_example_run.step);
    c_example_step.dependOn(&lib.step);
}
