const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    // Import the zig_rb dependency
    const zig_rb_dep = b.dependency("zig_rb", .{
        .target = target,
        .optimize = optimize,
    });

    // Get the zig_rb module from the dependency
    const zig_rb_module = zig_rb_dep.module("zig_rb");

    // Create a module for our extension that imports zig_rb
    const example_module = b.createModule(.{
        .root_source_file = b.path("ext/example/main.zig"),
        .target = target,
        .optimize = optimize,
        .imports = &.{
            .{ .name = "rb", .module = zig_rb_module },
        },
    });

    const ruby = @import("zig_rb").ruby;

    // Get Ruby configuration
    const ruby_config = ruby.getConfig(b) catch |err| {
        std.debug.print("Failed to get Ruby config: {}\n", .{err});
        return;
    };

    const example_ext = ruby.addExtension(
        b,
        &ruby_config,
        .{
            .name = "example",
            .root_module = example_module,
        },
    );

    // Install the extension to the proper gem path (lib/example/ruby_version/)
    // This follows Ruby gem conventions for native extensions
    // For development, install directly to lib/ directory
    ruby.installExtensionToLib(b, &ruby_config, example_ext, "example") catch |err| {
        std.debug.print("Failed to install Ruby extension: {}\n", .{err});
        // Fallback to default installation in zig-out/
        b.installArtifact(example_ext);
        return;
    };
}
