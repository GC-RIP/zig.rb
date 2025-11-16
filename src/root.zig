const std = @import("std");
pub const crb = @import("crb.zig").crb;
const testing = std.testing;
const Allocator = std.mem.Allocator;
pub const RubyAllocator = @import("RubyAllocator.zig");

// Public exports
pub const Value = @import("Value.zig");
pub const TypedDataClass = @import("TypedDataClass.zig");
pub const Module = @import("Module.zig");
pub const Error = @import("Error.zig");
pub const Array = @import("Array.zig");
pub const Hash = @import("Hash.zig");
const ids = @import("ids.zig");

pub fn init() void {
    ids.init();
}

test {
    std.testing.log_level = .debug;

    _ = Value;
    _ = TypedDataClass;
    _ = Module;
    _ = Error;
    _ = Array;
    _ = Hash;
}

test "tests:beforeAll" {
    crb.ruby_init();
    ids.init();
}

test "tests:afterAll" {
    _ = crb.ruby_cleanup(0);
}
