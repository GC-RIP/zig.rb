const std = @import("std");
const crb = @import("crb.zig").crb;
const Value = @import("Value.zig");
const methods = @import("methods.zig");

raw: crb.VALUE,
const Self = @This();

pub fn fromRaw(raw: crb.VALUE) Self {
    return .{ .raw = raw };
}

pub fn define(comptime name: [:0]const u8) Self {
    return fromRaw(crb.rb_define_module(name));
}

pub fn defineConstant(self: Self, comptime name: [:0]const u8, value: Value) void {
    crb.rb_define_const(self.raw, name, value.toRaw());
}

pub fn defineConstants(self: Self, comptime Constants: type) void {
    switch (@typeInfo(Constants)) {
        .@"struct" => |info| {
            inline for (info.decls) |decl| {
                const const_name = decl.name;
                comptime var buf: [decl.name.len:0]u8 = undefined;
                const const_name_upper = comptime std.ascii.upperString(&buf, const_name);
                if (comptime std.mem.eql(u8, const_name, const_name_upper)) {
                    const const_field = @field(Constants, const_name);
                    self.defineConstant(const_name, Value.from(const_field));
                }
            }
        },
        else => @compileError("Constants must be a struct, got " ++ @typeName(Constants)),
    }
}

pub fn defineFunction(
    self: Self,
    comptime zig_func: anytype,
    comptime name: [:0]const u8,
) void {
    methods.validate(null, zig_func);
    const arity = comptime methods.getArity(zig_func);
    const wrapper = methods.wrap(null, zig_func, arity);
    crb.rb_define_module_function(self.raw, name, @ptrCast(wrapper), @intCast(arity));
}

pub fn defineFunctions(
    self: Self,
    comptime Functions: type,
) void {
    switch (@typeInfo(Functions)) {
        .@"struct" => |info| {
            inline for (info.decls) |decl| {
                const func = @field(Functions, decl.name);
                if (@typeInfo(@TypeOf(func)) == .@"fn") {
                    self.defineFunction(func, decl.name);
                }
            }
        },
        else => @compileError("Functions must be a struct, got " ++ @typeName(Functions)),
    }
}
