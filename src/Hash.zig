const std = @import("std");
const crb = @import("crb.zig").crb;
const Value = @import("Value.zig");
const Array = @import("Array.zig");
const Self = @This();
const ids = @import("ids.zig");

value: Value,

pub fn new() Self {
    return .{ .value = Value.fromRaw(crb.rb_hash_new()) };
}

pub fn fromValue(val: Value) Self {
    return .{ .value = val };
}

fn fromRawValue(val: crb.VALUE) Self {
    return fromValue(Value.fromRaw(val));
}

pub fn len(self: Self) usize {
    return crb.RHASH_SIZE(self.value.toRaw());
}

pub fn isEmpty(self: Self) bool {
    return self.len() == 0;
}

pub fn get(self: Self, key: Value) Value {
    return Value.fromRaw(crb.rb_hash_aref(self.value.toRaw(), key.toRaw()));
}

pub fn set(self: Self, key: Value, val: Value) void {
    _ = crb.rb_hash_aset(self.value.toRaw(), key.toRaw(), val.toRaw());
}

pub fn delete(self: Self, key: Value) Value {
    return Value.fromRaw(crb.rb_hash_delete(self.value.toRaw(), key.toRaw()));
}

pub fn hasKey(self: Self, key: Value) bool {
    const result = crb.rb_funcall(self.value.toRaw(), ids.@"key?", 1, key.toRaw());
    return result == crb.Qtrue;
}

pub fn clear(self: Self) void {
    _ = crb.rb_hash_clear(self.value.toRaw());
}

pub fn keys(self: Self) Array {
    return Array.fromRawValue(crb.rb_funcall(self.value.toRaw(), ids.keys, 0));
}

pub fn values(self: Self) Array {
    return Array.fromRawValue(crb.rb_funcall(self.value.toRaw(), ids.values, 0));
}

pub fn toValue(self: Self) Value {
    return self.value;
}

pub fn toRaw(self: Self) crb.VALUE {
    return self.value.toRaw();
}

pub const IterateResult = enum(c_int) {
    @"continue",
    stop,
    delete,
    check,
};

pub fn forEach(self: Self, userdata: anytype, comptime callback: fn (Value, Value, @TypeOf(userdata)) IterateResult) void {
    const ArgType = @TypeOf(userdata);
    if (@sizeOf(ArgType) > @sizeOf(c_ulong)) {
        @compileError("userdata type size must fit inside c_ulong (hint: use a pointer type)");
    }

    const Wrapper = struct {
        fn call(key: crb.VALUE, val: crb.VALUE, data: c_ulong) callconv(.c) c_int {
            const user_ptr: *const ArgType = @ptrFromInt(data);
            return @intFromEnum(callback(Value.fromRaw(key), Value.fromRaw(val), user_ptr.*));
        }
    };

    crb.rb_hash_foreach(self.value.toRaw(), Wrapper.call, @intFromPtr(&userdata));
}

const testing = std.testing;

test "create empty hash" {
    const hash = new();
    try testing.expectEqual(@as(usize, 0), hash.len());
    try testing.expect(hash.isEmpty());
}

test "set and get values (strings)" {
    const hash = new();
    hash.set(Value.newString("name"), Value.newString("Alice"));
    hash.set(Value.newString("age"), Value.from(30));

    const name = hash.get(Value.newString("name"));
    const name_str = try name.toString();
    try testing.expectEqualSlices(u8, "Alice", name_str);

    const age = hash.get(Value.newString("age"));
    try testing.expectEqual(@as(c_int, 30), try age.toInt(c_int));

    try testing.expectEqual(@as(usize, 2), hash.len());
}

test "set and get values (symbols)" {
    const hash = new();
    hash.set(Value.symbol("name"), Value.newString("Alice"));
    hash.set(Value.symbol("age"), Value.from(30));

    const name = hash.get(Value.symbol("name"));
    const name_str = try name.toString();
    try testing.expectEqualSlices(u8, "Alice", name_str);

    const age = hash.get(Value.symbol("age"));
    try testing.expectEqual(@as(c_int, 30), try age.toInt(c_int));

    try testing.expectEqual(@as(usize, 2), hash.len());
}

test "hasKey" {
    const hash = new();
    hash.set(Value.newString("key1"), Value.from(100));

    try testing.expect(hash.hasKey(Value.newString("key1")));
    try testing.expect(!hash.hasKey(Value.newString("key2")));
}

test "delete" {
    const hash = new();
    hash.set(Value.newString("key1"), Value.from(100));
    hash.set(Value.newString("key2"), Value.from(200));

    try testing.expectEqual(@as(usize, 2), hash.len());

    const deleted = hash.delete(Value.newString("key1"));
    try testing.expectEqual(@as(c_int, 100), try deleted.toInt(c_int));
    try testing.expectEqual(@as(usize, 1), hash.len());
    try testing.expect(!hash.hasKey(Value.newString("key1")));
}

test "clear" {
    const hash = new();
    hash.set(Value.newString("a"), Value.from(1));
    hash.set(Value.newString("b"), Value.from(2));
    try testing.expectEqual(@as(usize, 2), hash.len());

    hash.clear();
    try testing.expectEqual(@as(usize, 0), hash.len());
    try testing.expect(hash.isEmpty());
}

test "keys and values" {
    const hash = new();
    hash.set(Value.from(1), Value.newString("one"));
    hash.set(Value.from(2), Value.newString("two"));

    const hash_keys = hash.keys();
    const hash_values = hash.values();

    // Keys and values should be arrays
    try testing.expectEqual(Value.Type.array, hash_keys.toValue().getType());
    try testing.expectEqual(Value.Type.array, hash_values.toValue().getType());
}

test "forEach iteration" {
    const hash = new();
    hash.set(Value.from(1), Value.from(10));
    hash.set(Value.from(2), Value.from(20));
    hash.set(Value.from(3), Value.from(30));

    // Sum all values using forEach
    const sumCallback = struct {
        fn call(key: Value, val: Value, acc_ptr: *c_int) IterateResult {
            _ = key;
            acc_ptr.* += val.toInt(c_int) catch return .stop;
            return .@"continue";
        }
    }.call;

    var sum: c_int = 0;
    hash.forEach(&sum, sumCallback);
    try testing.expectEqual(@as(c_int, 60), sum);
}
