const Build = @import("std").Build;
const FileSource = Build.FileSource;

pub fn build(b: *Build) void {
    // Standard target options allows the person running `zig build` to choose
    // what target to build for. Here we do not override the defaults, which
    // means any target is allowed, and the default is native. Other options
    // for restricting supported target set are available.
    const target = b.standardTargetOptions(.{});

    // Standard release options allow the person running `zig build` to select
    // between Debug, ReleaseSafe, ReleaseFast, and ReleaseSmall.
    const optimize = b.standardOptimizeOption(.{});

    // Static library
    const lib = b.addStaticLibrary(.{
        .name = "linenoise",
        .root_source_file = FileSource.relative("src/c.zig"),
        .target = target,
        .optimize = optimize,
    });
    lib.linkLibC();
    lib.install();

    // Tests
    var main_tests = b.addTest(.{
        .name = "main-tests",
        .root_source_file = FileSource.relative("src/main.zig"),
        .target = target,
        .optimize = optimize,
    });

    const test_step = b.step("test", "Run library tests");
    test_step.dependOn(&main_tests.step);

    // Zig example
    var example = b.addExecutable(.{
        .name = "example",
        .root_source_file = FileSource.relative("examples/example.zig"),
        .target = target,
        .optimize = optimize,
    });
    example.addAnonymousModule("linenoise", .{
        .source_file = FileSource.relative("src/main.zig"),
    });

    var example_run = example.run();

    const example_step = b.step("example", "Run example");
    example_step.dependOn(&example_run.step);

    // C example
    var c_example = b.addExecutable(.{
        .name =  "example",
        .root_source_file = FileSource.relative("examples/example.c"),
        .target = target,
        .optimize = optimize,
    });
    c_example.addIncludePath("include");
    c_example.linkLibC();
    c_example.linkLibrary(lib);

    var c_example_run = c_example.run();

    const c_example_step = b.step("c-example", "Run C example");
    c_example_step.dependOn(&c_example_run.step);
    c_example_step.dependOn(&lib.step);
}
