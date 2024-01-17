const Build = @import("std").Build;

pub fn build(b: *Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const wcwidth = b.dependency("wcwidth", .{
        .target = target,
        .optimize = optimize,
    }).module("wcwidth");

    const linenoise = b.addModule("linenoise", .{
        .root_source_file = .{ .path = "src/main.zig" },
        .imports = &.{
            .{
                .name = "wcwidth",
                .module = wcwidth,
            },
        },
    });

    // Static library
    const lib = b.addStaticLibrary(.{
        .name = "linenoise",
        .root_source_file = .{ .path = "src/c.zig" },
        .target = target,
        .optimize = optimize,
    });
    lib.root_module.addImport("wcwidth", wcwidth);
    lib.linkLibC();
    b.installArtifact(lib);

    // Tests
    const main_tests = b.addTest(.{
        .name = "main-tests",
        .root_source_file = .{ .path = "src/main.zig" },
        .target = target,
        .optimize = optimize,
    });

    const run_main_tests = b.addRunArtifact(main_tests);

    const test_step = b.step("test", "Run library tests");
    test_step.dependOn(&run_main_tests.step);

    // Zig example
    var example = b.addExecutable(.{
        .name = "example",
        .root_source_file = .{ .path = "examples/example.zig" },
        .target = target,
        .optimize = optimize,
    });
    example.root_module.addImport("linenoise", linenoise);

    var example_run = b.addRunArtifact(example);

    const example_step = b.step("example", "Run example");
    example_step.dependOn(&example_run.step);

    // C example
    var c_example = b.addExecutable(.{
        .name = "example",
        .target = target,
        .optimize = optimize,
    });
    c_example.root_module.addCSourceFile(.{ .file = .{ .path = "examples/example.c" } });
    c_example.addIncludePath(.{ .path = "include" });
    c_example.linkLibC();
    c_example.linkLibrary(lib);

    var c_example_run = b.addRunArtifact(c_example);

    const c_example_step = b.step("c-example", "Run C example");
    c_example_step.dependOn(&c_example_run.step);
    c_example_step.dependOn(&lib.step);
}
