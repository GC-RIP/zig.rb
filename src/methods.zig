const std = @import("std");
const crb = @import("crb.zig").crb;
const Value = @import("Value.zig");

pub fn validate(comptime Data: ?type, comptime zig_func: anytype) void {
    const T = @TypeOf(zig_func);

    switch (@typeInfo(T)) {
        .@"fn" => |info| {
            if (info.return_type.? != Value) {
                @compileError("Method must return Value, got " ++ @typeName(info.return_type.?));
            }

            if (info.params.len < 1) {
                @compileError("Methods must at least have one argument");
            }

            if (Data) |Data_| {
                if (info.params[0].type.? != *Data_ and info.params[0].type.? != Value) {
                    @compileError("First parameter must be *" ++ @typeName(Data) ++ " or Value");
                }
            } else {
                if (info.params[0].type.? != Value) {
                    @compileError("First parameter must be Value");
                }
            }

            inline for (info.params, 0..) |param, i| {
                if (i > 0 and param.type.? != Value) {
                    @compileError("Method parameters must be Value, got " ++ @typeName(param.type.?));
                }
            }
        },
        else => @compileError("Expected function, got " ++ @typeName(T)),
    }
}

pub fn getArity(comptime zig_func: anytype) usize {
    const T = @TypeOf(zig_func);
    const info = @typeInfo(T).@"fn";

    const arity = info.params.len - 1;

    if (arity > 15) {
        @compileError("Methods can have at most 15 parameters (excluding self)");
    }

    return arity;
}

/// Generate a C-callable wrapper for a Zig method
/// See https://github.com/ruby/ruby/blob/f4b6a5191ceb0ed0cd7a3e3c8bab24cc0dd15736/include/ruby/internal/anyargs.h
/// I guess there is no way to comptime generate funcations of varying arity?
pub fn wrap(
    comptime Data: ?type,
    comptime zig_func: anytype,
    comptime arity: usize,
) *const anyopaque {
    const func_info = @typeInfo(@TypeOf(zig_func)).@"fn";
    const FirstParamType = func_info.params[0].type.?;

    const uses_data_ptr = Data != null and FirstParamType == *Data.?;

    const Wrapper = struct {
        inline fn callZigFunc(comptime n: usize, rb_self: crb.VALUE, rb_args: anytype) crb.VALUE {
            const call_arg_types = if (uses_data_ptr)
                std.meta.Tuple(&[_]type{*Data.?} ++ [_]type{Value} ** n)
            else
                std.meta.Tuple(&[_]type{Value} ** (n + 1));

            var call_args: call_arg_types = undefined;
            if (uses_data_ptr) {
                call_args[0] = Data.?.ruby_type.unwrap(rb_self);
            } else {
                call_args[0] = Value.fromRaw(rb_self);
            }
            inline for (0..n) |i| {
                call_args[i + 1] = Value.fromRaw(rb_args[i]);
            }
            const result = @call(.auto, zig_func, call_args);
            return result.toRaw();
        }
    };

    return switch (arity) {
        0 => @ptrCast(&struct {
            fn wrapper(rb_self: crb.VALUE) callconv(.c) crb.VALUE {
                return Wrapper.callZigFunc(0, rb_self, .{});
            }
        }.wrapper),
        1 => @ptrCast(&struct {
            fn wrapper(rb_self: crb.VALUE, a0: crb.VALUE) callconv(.c) crb.VALUE {
                return Wrapper.callZigFunc(1, rb_self, .{a0});
            }
        }.wrapper),
        2 => @ptrCast(&struct {
            fn wrapper(rb_self: crb.VALUE, a0: crb.VALUE, a1: crb.VALUE) callconv(.c) crb.VALUE {
                return Wrapper.callZigFunc(2, rb_self, .{ a0, a1 });
            }
        }.wrapper),
        3 => @ptrCast(&struct {
            fn wrapper(rb_self: crb.VALUE, a0: crb.VALUE, a1: crb.VALUE, a2: crb.VALUE) callconv(.c) crb.VALUE {
                return Wrapper.callZigFunc(3, rb_self, .{ a0, a1, a2 });
            }
        }.wrapper),
        4 => @ptrCast(&struct {
            fn wrapper(rb_self: crb.VALUE, a0: crb.VALUE, a1: crb.VALUE, a2: crb.VALUE, a3: crb.VALUE) callconv(.c) crb.VALUE {
                return Wrapper.callZigFunc(4, rb_self, .{ a0, a1, a2, a3 });
            }
        }.wrapper),
        5 => @ptrCast(&struct {
            fn wrapper(rb_self: crb.VALUE, a0: crb.VALUE, a1: crb.VALUE, a2: crb.VALUE, a3: crb.VALUE, a4: crb.VALUE) callconv(.c) crb.VALUE {
                return Wrapper.callZigFunc(5, rb_self, .{ a0, a1, a2, a3, a4 });
            }
        }.wrapper),
        6 => @ptrCast(&struct {
            fn wrapper(rb_self: crb.VALUE, a0: crb.VALUE, a1: crb.VALUE, a2: crb.VALUE, a3: crb.VALUE, a4: crb.VALUE, a5: crb.VALUE) callconv(.c) crb.VALUE {
                return Wrapper.callZigFunc(6, rb_self, .{ a0, a1, a2, a3, a4, a5 });
            }
        }.wrapper),
        7 => @ptrCast(&struct {
            fn wrapper(rb_self: crb.VALUE, a0: crb.VALUE, a1: crb.VALUE, a2: crb.VALUE, a3: crb.VALUE, a4: crb.VALUE, a5: crb.VALUE, a6: crb.VALUE) callconv(.c) crb.VALUE {
                return Wrapper.callZigFunc(7, rb_self, .{ a0, a1, a2, a3, a4, a5, a6 });
            }
        }.wrapper),
        8 => @ptrCast(&struct {
            fn wrapper(rb_self: crb.VALUE, a0: crb.VALUE, a1: crb.VALUE, a2: crb.VALUE, a3: crb.VALUE, a4: crb.VALUE, a5: crb.VALUE, a6: crb.VALUE, a7: crb.VALUE) callconv(.c) crb.VALUE {
                return Wrapper.callZigFunc(8, rb_self, .{ a0, a1, a2, a3, a4, a5, a6, a7 });
            }
        }.wrapper),
        9 => @ptrCast(&struct {
            fn wrapper(rb_self: crb.VALUE, a0: crb.VALUE, a1: crb.VALUE, a2: crb.VALUE, a3: crb.VALUE, a4: crb.VALUE, a5: crb.VALUE, a6: crb.VALUE, a7: crb.VALUE, a8: crb.VALUE) callconv(.c) crb.VALUE {
                return Wrapper.callZigFunc(9, rb_self, .{ a0, a1, a2, a3, a4, a5, a6, a7, a8 });
            }
        }.wrapper),
        10 => @ptrCast(&struct {
            fn wrapper(rb_self: crb.VALUE, a0: crb.VALUE, a1: crb.VALUE, a2: crb.VALUE, a3: crb.VALUE, a4: crb.VALUE, a5: crb.VALUE, a6: crb.VALUE, a7: crb.VALUE, a8: crb.VALUE, a9: crb.VALUE) callconv(.c) crb.VALUE {
                return Wrapper.callZigFunc(10, rb_self, .{ a0, a1, a2, a3, a4, a5, a6, a7, a8, a9 });
            }
        }.wrapper),
        11 => @ptrCast(&struct {
            fn wrapper(rb_self: crb.VALUE, a0: crb.VALUE, a1: crb.VALUE, a2: crb.VALUE, a3: crb.VALUE, a4: crb.VALUE, a5: crb.VALUE, a6: crb.VALUE, a7: crb.VALUE, a8: crb.VALUE, a9: crb.VALUE, a10: crb.VALUE) callconv(.c) crb.VALUE {
                return Wrapper.callZigFunc(11, rb_self, .{ a0, a1, a2, a3, a4, a5, a6, a7, a8, a9, a10 });
            }
        }.wrapper),
        12 => @ptrCast(&struct {
            fn wrapper(rb_self: crb.VALUE, a0: crb.VALUE, a1: crb.VALUE, a2: crb.VALUE, a3: crb.VALUE, a4: crb.VALUE, a5: crb.VALUE, a6: crb.VALUE, a7: crb.VALUE, a8: crb.VALUE, a9: crb.VALUE, a10: crb.VALUE, a11: crb.VALUE) callconv(.c) crb.VALUE {
                return Wrapper.callZigFunc(12, rb_self, .{ a0, a1, a2, a3, a4, a5, a6, a7, a8, a9, a10, a11 });
            }
        }.wrapper),
        13 => @ptrCast(&struct {
            fn wrapper(rb_self: crb.VALUE, a0: crb.VALUE, a1: crb.VALUE, a2: crb.VALUE, a3: crb.VALUE, a4: crb.VALUE, a5: crb.VALUE, a6: crb.VALUE, a7: crb.VALUE, a8: crb.VALUE, a9: crb.VALUE, a10: crb.VALUE, a11: crb.VALUE, a12: crb.VALUE) callconv(.c) crb.VALUE {
                return Wrapper.callZigFunc(13, rb_self, .{ a0, a1, a2, a3, a4, a5, a6, a7, a8, a9, a10, a11, a12 });
            }
        }.wrapper),
        14 => @ptrCast(&struct {
            fn wrapper(rb_self: crb.VALUE, a0: crb.VALUE, a1: crb.VALUE, a2: crb.VALUE, a3: crb.VALUE, a4: crb.VALUE, a5: crb.VALUE, a6: crb.VALUE, a7: crb.VALUE, a8: crb.VALUE, a9: crb.VALUE, a10: crb.VALUE, a11: crb.VALUE, a12: crb.VALUE, a13: crb.VALUE) callconv(.c) crb.VALUE {
                return Wrapper.callZigFunc(14, rb_self, .{ a0, a1, a2, a3, a4, a5, a6, a7, a8, a9, a10, a11, a12, a13 });
            }
        }.wrapper),
        15 => @ptrCast(&struct {
            fn wrapper(rb_self: crb.VALUE, a0: crb.VALUE, a1: crb.VALUE, a2: crb.VALUE, a3: crb.VALUE, a4: crb.VALUE, a5: crb.VALUE, a6: crb.VALUE, a7: crb.VALUE, a8: crb.VALUE, a9: crb.VALUE, a10: crb.VALUE, a11: crb.VALUE, a12: crb.VALUE, a13: crb.VALUE, a14: crb.VALUE) callconv(.c) crb.VALUE {
                return Wrapper.callZigFunc(15, rb_self, .{ a0, a1, a2, a3, a4, a5, a6, a7, a8, a9, a10, a11, a12, a13, a14 });
            }
        }.wrapper),
        else => @compileError("Arity " ++ std.fmt.comptimePrint("{d}", .{arity}) ++ " not supported. Maximum arity is 15."),
    };
}
