const Build = @import("std").Build;
const FileSource = Build.FileSource;

pub fn build(b: *Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const wcwidth = b.dependency("wcwidth", .{
        .target = target,
        .optimize = optimize,
    }).module("wcwidth");

    const linenoise = b.addModule("linenoise", .{
        .source_file = .{ .path = "src/main.zig" },
        .dependencies = &.{
            .{
                .name = "wcwidth",
                .module = wcwidth,
            },
        },
    });

    // Static library
    const lib = b.addStaticLibrary(.{
        .name = "linenoise",
        .root_source_file = FileSource.relative("src/c.zig"),
        .target = target,
        .optimize = optimize,
    });
    lib.addModule("wcwidth", wcwidth);
    lib.linkLibC();
    b.installArtifact(lib);

    // Tests
    var main_tests = b.addTest(.{
        .name = "main-tests",
        .root_source_file = FileSource.relative("src/main.zig"),
        .target = target,
        .optimize = optimize,
    });

    const run_main_tests = b.addRunArtifact(main_tests);

    const test_step = b.step("test", "Run library tests");
    test_step.dependOn(&run_main_tests.step);

    // Zig example
    var example = b.addExecutable(.{
        .name = "example",
        .root_source_file = FileSource.relative("examples/example.zig"),
        .target = target,
        .optimize = optimize,
    });
    example.addModule("linenoise", linenoise);

    var example_run = b.addRunArtifact(example);

    const example_step = b.step("example", "Run example");
    example_step.dependOn(&example_run.step);

    // C example
    var c_example = b.addExecutable(.{
        .name = "example",
        .root_source_file = FileSource.relative("examples/example.c"),
        .target = target,
        .optimize = optimize,
    });
    c_example.addIncludePath("include");
    c_example.linkLibC();
    c_example.linkLibrary(lib);

    var c_example_run = b.addRunArtifact(c_example);

    const c_example_step = b.step("c-example", "Run C example");
    c_example_step.dependOn(&c_example_run.step);
    c_example_step.dependOn(&lib.step);
}
