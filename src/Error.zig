const std = @import("std");
const crb = @import("crb.zig").crb;
const Value = @import("Value.zig");

pub const ProtectError = error{Raised};

fn raise(klass: crb.VALUE, message: [:0]const u8) noreturn {
    crb.rb_raise(klass, message, @as([*c]const u8, null));
}

pub fn raiseArgumentError(message: [:0]const u8) noreturn {
    raise(crb.rb_eArgError, message);
}

pub fn raiseTypeError(message: [:0]const u8) noreturn {
    raise(crb.rb_eTypeError, message);
}

pub fn raiseRuntimeError(message: [:0]const u8) noreturn {
    raise(crb.rb_eRuntimeError, message);
}

pub fn protect(arg: anytype, comptime Ret: type, comptime Fn: fn (@TypeOf(arg)) Ret) ProtectError!Ret {
    const Arg = @TypeOf(arg);
    const Wrapper = struct {
        fn call(data: crb.VALUE) callconv(.c) crb.VALUE {
            const retval = Fn(@as(*const Arg, @ptrCast(@alignCast(&data))).*);
            return @as(*const crb.VALUE, @ptrCast(@alignCast(&retval))).*;
        }
    };

    var status: c_int = 0;
    const result = crb.rb_protect(Wrapper.call, @as(*const crb.VALUE, @ptrCast(&arg)).*, &status);
    if (status != 0) {
        return ProtectError.Raised;
    }
    return @as(*const Ret, @ptrCast(&result)).*;
}

pub fn lastException() ?Value {
    const errinfo = crb.rb_errinfo();
    return if (errinfo == crb.Qnil) null else Value.fromRaw(errinfo);
}

pub fn clearLastException() void {
    crb.rb_set_errinfo(crb.Qnil);
}

const testing = std.testing;

test "protect returns the wrapped function's value" {
    const identity = struct {
        fn call(arg: Value) Value {
            return arg;
        }
    }.call;

    const input = Value.from(1234);
    const result = try protect(input, Value, identity);
    const output = try result.toInt(c_int);

    try testing.expectEqual(@as(c_int, 1234), output);
}

test "protect returns the wrapped function's value (pointer)" {
    const identity = struct {
        fn call(arg: *u32) *u32 {
            return arg;
        }
    }.call;

    var input: u32 = 1234;
    const result = try protect(&input, *u32, identity);
    try testing.expectEqual(@as(u32, 1234), result.*);
}

test "protect converts Ruby exceptions into ProtectError and exposes lastException" {
    clearLastException();

    const raises = struct {
        fn call(arg: Value) Value {
            _ = arg;
            raiseRuntimeError("boom");
            unreachable;
        }
    }.call;

    const protected_call = protect(Value.nil, Value, raises);
    try testing.expectError(ProtectError.Raised, protected_call);

    const exception = lastException();
    try testing.expect(exception != null);

    if (exception) |exc| {
        const exc_class = Value.fromRaw(crb.rb_class_of(exc.toRaw()));
        try testing.expectEqual(crb.rb_eRuntimeError, exc_class.toRaw());
    }
}

test "protect: successful execution returns value" {
    const testFunc = struct {
        fn call(arg: Value) Value {
            // Simply return the argument unchanged
            return arg;
        }
    }.call;

    const input = Value.from(42);
    const result = try protect(input, Value, testFunc);
    const output = try result.toInt(c_int);
    try testing.expectEqual(42, output);
}

test "protect: catches Ruby exception and returns error" {
    const testFunc = struct {
        fn call(arg: Value) Value {
            _ = arg;
            raiseRuntimeError("test error");
            return Value.nil;
        }
    }.call;

    const input = Value.nil;
    const result = protect(input, Value, testFunc);

    try testing.expectError(ProtectError.Raised, result);
}

test "protect: exception is available via lastException" {
    const testFunc = struct {
        fn call(arg: Value) Value {
            _ = arg;
            raiseArgumentError("custom error message");
            return Value.nil;
        }
    }.call;

    const input = Value.nil;
    _ = protect(input, Value, testFunc) catch |err| {
        try testing.expectEqual(ProtectError.Raised, err);

        // Check that we can retrieve the exception
        const exception = lastException();
        try testing.expect(exception != null);

        if (exception) |exc| {
            // Verify it's an ArgumentError
            const exc_class = Value.fromRaw(crb.rb_class_of(exc.toRaw()));
            const arg_error_class = Value.fromRaw(crb.rb_eArgError);
            try testing.expectEqual(exc_class.toRaw(), arg_error_class.toRaw());
        }

        return;
    };
}

test "protect: clearLastException clears exception info" {
    const testFunc = struct {
        fn call(arg: Value) Value {
            _ = arg;
            raiseTypeError("type error");
            return Value.nil;
        }
    }.call;

    const input = Value.nil;
    _ = protect(input, Value, testFunc) catch |err| {
        try testing.expectEqual(ProtectError.Raised, err);

        // Exception should be set
        try testing.expect(lastException() != null);

        // Clear it
        clearLastException();

        // Should now be null
        try testing.expect(lastException() == null);

        return;
    };
}

test "protect: multiple exceptions in sequence" {
    // First exception
    const testFunc1 = struct {
        fn call(arg: Value) Value {
            _ = arg;
            raiseRuntimeError("first error");
            return Value.nil;
        }
    }.call;

    _ = protect(Value.nil, Value, testFunc1) catch |err| {
        try testing.expectEqual(ProtectError.Raised, err);
    };

    clearLastException();

    // Second exception
    const testFunc2 = struct {
        fn call(arg: Value) Value {
            _ = arg;
            raiseArgumentError("second error");
            return Value.nil;
        }
    }.call;

    _ = protect(Value.nil, Value, testFunc2) catch |err| {
        try testing.expectEqual(ProtectError.Raised, err);

        const exception = lastException();
        try testing.expect(exception != null);

        if (exception) |exc| {
            const exc_class = Value.fromRaw(crb.rb_class_of(exc.toRaw()));
            const arg_error_class = Value.fromRaw(crb.rb_eArgError);
            try testing.expectEqual(exc_class.toRaw(), arg_error_class.toRaw());
        }
    };
}

test "protect: works with different argument types" {
    // Test with string
    const stringFunc = struct {
        fn call(arg: Value) Value {
            return arg;
        }
    }.call;

    const str_input = Value.newString("hello");
    const str_result = try protect(str_input, Value, stringFunc);
    const str_output = try str_result.toString();
    try testing.expectEqualSlices(u8, "hello", str_output);

    // Test with float
    const floatFunc = struct {
        fn call(arg: Value) Value {
            return arg;
        }
    }.call;

    const float_input = Value.from(3.14);
    const float_result = try protect(float_input, Value, floatFunc);
    const float_output = try float_result.toFloat(f64);
    try testing.expectEqual(3.14, float_output);
}

test "protect: nested protect calls" {
    const outerFunc = struct {
        fn call(arg: Value) Value {
            const innerFunc = struct {
                fn inner(inner_arg: Value) Value {
                    return Value.from((inner_arg.toInt(c_int) catch unreachable) * 2);
                }
            }.inner;

            const doubled = protect(arg, Value, innerFunc) catch {
                return Value.nil;
            };

            return doubled;
        }
    }.call;

    const input = Value.from(21);
    const result = try protect(input, Value, outerFunc);
    const output = try result.toInt(c_int);
    try testing.expectEqual(42, output);
}

test "lastException: returns null when no exception" {
    clearLastException();
    const exception = lastException();
    try testing.expect(exception == null);
}
