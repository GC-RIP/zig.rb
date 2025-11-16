const std = @import("std");
const rb = @import("rb");
const crb = rb.crb;
const Value = rb.Value;
const TypedDataClass = rb.TypedDataClass;
const Module = rb.Module;
const RubyAllocator = rb.RubyAllocator;
const Error = rb.Error;

const Counter = struct {
    const Self = @This();

    count: i64,
    name: []const u8,

    pub const ruby_type = TypedDataClass.createDataType(Self, "Counter", RubyType);

    pub const RubyType = struct {
        pub fn alloc(_: Value, allocator: std.mem.Allocator) ?*Self {
            const ptr = allocator.create(Self) catch return null;
            ptr.* = .{ .count = 0, .name = "" };
            return ptr;
        }

        pub fn mark(_: *Self) void {}

        pub fn free(self: *Self, allocator: std.mem.Allocator) void {
            allocator.destroy(self);
        }
    };

    pub const InstanceMethods = struct {
        pub fn increment(self: *Self) Value {
            self.count += 1;
            return Value.from(self.count);
        }

        pub fn decrement(self: *Self) Value {
            self.count -= 1;
            return Value.from(self.count);
        }

        pub fn get_count(self: *Self) Value {
            return Value.from(self.count);
        }

        pub fn set_count(self: *Self, rb_value: Value) Value {
            self.count = rb_value.toInt(i64) catch 0;
            return Value.from(self.count);
        }

        pub fn add(self: *Self, rb_amount: Value) Value {
            const amount = rb_amount.toInt(i64) catch 0;
            self.count += amount;
            return Value.from(self.count);
        }

        pub fn reset(self: *Self) Value {
            self.count = 0;
            return Value.from(self.count);
        }
    };

    pub const Constants = struct {
        pub const VERSION = "1.0.0";
        pub const MAX_VALUE = 1000000;
    };
};

const Calculator = struct {
    const Self = @This();

    last_result: f64,

    pub const ruby_type = TypedDataClass.createDataType(Self, "Calculator", RubyType);

    pub const RubyType = struct {
        pub fn alloc(_: Value, allocator: std.mem.Allocator) ?*Self {
            const ptr = allocator.create(Self) catch return null;
            ptr.* = .{ .last_result = 0.0 };
            return ptr;
        }

        pub fn mark(_: *Self) void {}

        pub fn free(self: *Self, allocator: std.mem.Allocator) void {
            allocator.destroy(self);
        }
    };

    pub const InstanceMethods = struct {
        pub fn add(self: *Self, rb_a: Value, rb_b: Value) Value {
            const a = rb_a.toFloat(f64) catch 0.0;
            const b = rb_b.toFloat(f64) catch 0.0;
            self.last_result = a + b;
            return Value.from(self.last_result);
        }

        pub fn subtract(self: *Self, rb_a: Value, rb_b: Value) Value {
            const a = rb_a.toFloat(f64) catch 0.0;
            const b = rb_b.toFloat(f64) catch 0.0;
            self.last_result = a - b;
            return Value.from(self.last_result);
        }

        pub fn multiply(self: *Self, rb_a: Value, rb_b: Value) Value {
            const a = rb_a.toFloat(f64) catch 0.0;
            const b = rb_b.toFloat(f64) catch 0.0;
            self.last_result = a * b;
            return Value.from(self.last_result);
        }

        pub fn divide(self: *Self, rb_a: Value, rb_b: Value) Value {
            const a = rb_a.toFloat(f64) catch 0.0;
            const b = rb_b.toFloat(f64) catch 0.0;
            if (b == 0.0) {
                return Value.nil;
            }
            self.last_result = a / b;
            return Value.from(self.last_result);
        }

        pub fn last_result(self: *Self) Value {
            return Value.from(self.last_result);
        }
    };

    pub const SingletonMethods = struct {
        pub fn pi(_: Value) Value {
            return Value.from(std.math.pi);
        }

        pub fn e(_: Value) Value {
            return Value.from(std.math.e);
        }
    };
};

const StringProcessor = struct {
    const Self = @This();

    prefix: []const u8,

    pub const ruby_type = TypedDataClass.createDataType(Self, "StringProcessor", RubyType);

    pub const RubyType = struct {
        pub fn alloc(_: Value, allocator: std.mem.Allocator) ?*Self {
            const ptr = allocator.create(Self) catch return null;
            ptr.* = .{ .prefix = "" };
            return ptr;
        }

        pub fn mark(_: *Self) void {}

        pub fn free(self: *Self, allocator: std.mem.Allocator) void {
            allocator.destroy(self);
        }
    };

    pub const InstanceMethods = struct {
        pub fn reverse(_: *Self, rb_str: Value) Value {
            const str = rb_str.toString() catch return Value.nil;

            const allocator: RubyAllocator = .{};
            const reversed = allocator.allocator().alloc(u8, str.len) catch return Value.nil;
            defer allocator.allocator().free(reversed);

            var i: usize = 0;
            while (i < str.len) : (i += 1) {
                reversed[i] = str[str.len - 1 - i];
            }

            return Value.newString(reversed);
        }

        pub fn upcase(_: *Self, rb_str: Value) Value {
            const str = rb_str.toString() catch return Value.nil;

            const allocator: RubyAllocator = .{};
            const upper = allocator.allocator().alloc(u8, str.len) catch return Value.nil;
            defer allocator.allocator().free(upper);

            for (str, 0..) |c, i| {
                upper[i] = std.ascii.toUpper(c);
            }

            return Value.newString(upper);
        }

        pub fn downcase(_: *Self, rb_str: Value) Value {
            const str = rb_str.toString() catch return Value.nil;

            const allocator: RubyAllocator = .{};
            const lower = allocator.allocator().alloc(u8, str.len) catch return Value.nil;
            defer allocator.allocator().free(lower);

            for (str, 0..) |c, i| {
                lower[i] = std.ascii.toLower(c);
            }

            return Value.newString(lower);
        }

        pub fn length(_: *Self, rb_str: Value) Value {
            const str = rb_str.toString() catch return Value.from(0);
            return Value.from(@as(i64, @intCast(str.len)));
        }
    };
};

const TypeTester = struct {
    const Self = @This();

    dummy: u8,

    pub const ruby_type = TypedDataClass.createDataType(Self, "TypeTester", RubyType);

    pub const RubyType = struct {
        pub fn alloc(_: Value, allocator: std.mem.Allocator) ?*Self {
            const ptr = allocator.create(Self) catch return null;
            ptr.* = .{ .dummy = 0 };
            return ptr;
        }

        pub fn mark(_: *Self) void {}

        pub fn free(self: *Self, allocator: std.mem.Allocator) void {
            allocator.destroy(self);
        }
    };

    pub const InstanceMethods = struct {
        pub fn echo_int(_: *Self, rb_val: Value) Value {
            const num = rb_val.toInt(i64) catch return Value.nil;
            return Value.from(num);
        }

        pub fn echo_float(_: *Self, rb_val: Value) Value {
            const num = rb_val.toFloat(f64) catch return Value.nil;
            return Value.from(num);
        }

        pub fn echo_string(_: *Self, rb_val: Value) Value {
            const str = rb_val.toString() catch return Value.nil;
            return Value.newString(str);
        }

        pub fn echo_bool(_: *Self, rb_val: Value) Value {
            const b = rb_val.toBool() catch false;
            return Value.from(b);
        }

        pub fn is_nil(_: *Self, rb_val: Value) Value {
            return Value.from(rb_val.isNil());
        }

        pub fn get_type(_: *Self, rb_val: Value) Value {
            const type_name = switch (rb_val.getType()) {
                .nil => "nil",
                .true => "true",
                .false => "false",
                .fixnum => "fixnum",
                .float => "float",
                .string => "string",
                .array => "array",
                .hash => "hash",
                .symbol => "symbol",
                .object => "object",
                else => "unknown",
            };
            return Value.newString(type_name);
        }
    };
};

const ZigRbTest = struct {
    pub const Functions = struct {
        pub fn add(_: Value, rb_a: Value, rb_b: Value) Value {
            const a = rb_a.toInt(i64) catch 0;
            const b = rb_b.toInt(i64) catch 0;
            return Value.from(a + b);
        }

        pub fn multiply(_: Value, rb_a: Value, rb_b: Value) Value {
            const a = rb_a.toInt(i64) catch 0;
            const b = rb_b.toInt(i64) catch 0;
            return Value.from(a * b);
        }

        pub fn is_even(_: Value, rb_num: Value) Value {
            const num = rb_num.toInt(i64) catch 0;
            return Value.from(@mod(num, 2) == 0);
        }

        pub fn factorial(_: Value, rb_n: Value) Value {
            const n = rb_n.toInt(i64) catch return Value.nil;

            if (n < 0) {
                Error.raiseArgumentError("n must be >= 0");
            }

            var result: i64 = 1;
            var i: i64 = 2;
            while (i <= n) : (i += 1) {
                result *= i;
            }

            return Value.from(result);
        }

        pub fn greet(_: Value, rb_name: Value) Value {
            const name = rb_name.toString() catch return Value.nil;

            const allocator: RubyAllocator = .{};
            const greeting = std.fmt.allocPrint(allocator.allocator(), "Hello, {s}!", .{name}) catch return Value.nil;
            defer allocator.allocator().free(greeting);

            return Value.newString(greeting);
        }

        pub fn array_sum(_: Value, rb_array: Value) Value {
            const len = crb.RARRAY_LEN(rb_array.raw);
            var sum: i64 = 0;

            var i: c_long = 0;
            while (i < len) : (i += 1) {
                const elem = crb.rb_ary_entry(rb_array.raw, i);
                const val = Value.fromRaw(elem).toInt(i64) catch 0;
                sum += val;
            }

            return Value.from(sum);
        }

        pub fn reverse_string(_: Value, rb_str: Value) Value {
            const str = rb_str.toString() catch return Value.nil;

            const allocator: RubyAllocator = .{};
            const reversed = allocator.allocator().alloc(u8, str.len) catch return Value.nil;
            defer allocator.allocator().free(reversed);

            var i: usize = 0;
            while (i < str.len) : (i += 1) {
                reversed[i] = str[str.len - 1 - i];
            }

            return Value.newString(reversed);
        }

        pub fn hash_merge_simple(_: Value, rb_hash1: Value, rb_hash2: Value) Value {
            const result = crb.rb_hash_new();
            _ = crb.rb_funcall(result, crb.rb_intern("merge!"), 1, rb_hash1.raw);
            _ = crb.rb_funcall(result, crb.rb_intern("merge!"), 1, rb_hash2.raw);
            return Value.fromRaw(result);
        }
    };

    pub const Constants = struct {
        pub const VERSION = "0.1.0";
    };
};

export fn Init_libzig_rb_test() void {
    std.log.info("Loaded", .{});

    _ = TypedDataClass.defineFromStructs("Counter", Counter);
    _ = TypedDataClass.defineFromStructs("Calculator", Calculator);
    _ = TypedDataClass.defineFromStructs("StringProcessor", StringProcessor);
    _ = TypedDataClass.defineFromStructs("TypeTester", TypeTester);

    const zig_rb_test = Module.define("ZigRbTest");
    zig_rb_test.defineFunctions(ZigRbTest.Functions);
    zig_rb_test.defineConstants(ZigRbTest.Constants);
}
