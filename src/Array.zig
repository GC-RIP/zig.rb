const std = @import("std");
const crb = @import("crb.zig").crb;
const Value = @import("Value.zig");

const Self = @This();

value: Value,

pub fn new() Self {
    return .{ .value = Value.fromRaw(crb.rb_ary_new()) };
}

pub fn newWithCapacity(capacity: c_long) Self {
    return .{ .value = Value.fromRaw(crb.rb_ary_new_capa(capacity)) };
}

pub fn fromValue(val: Value) Self {
    return .{ .value = val };
}

pub fn fromRawValue(val: crb.VALUE) Self {
    return .fromValue(Value.fromRaw(val));
}

pub fn fromSlice(comptime T: type, slice: []const T) Self {
    const arr = newWithCapacity(@intCast(slice.len));
    for (slice) |item| {
        arr.push(Value.from(item));
    }
    return arr;
}

pub fn len(self: Self) c_long {
    return crb.RARRAY_LEN(self.value.toRaw());
}

pub fn isEmpty(self: Self) bool {
    return self.len() == 0;
}

pub fn get(self: Self, index: usize) Value {
    return Value.fromRaw(crb.rb_ary_entry(self.value.toRaw(), @intCast(index)));
}

pub fn set(self: Self, index: usize, val: Value) void {
    crb.rb_ary_store(self.value.toRaw(), @intCast(index), val.toRaw());
}

pub fn push(self: Self, val: Value) void {
    _ = crb.rb_ary_push(self.value.toRaw(), val.toRaw());
}

pub fn pop(self: Self) Value {
    return Value.fromRaw(crb.rb_ary_pop(self.value.toRaw()));
}

pub fn shift(self: Self) Value {
    return Value.fromRaw(crb.rb_ary_shift(self.value.toRaw()));
}

pub fn unshift(self: Self, val: Value) Self {
    fromRawValue(crb.rb_ary_unshift(self.value.toRaw(), val.toRaw()));
}

pub fn clear(self: Self) void {
    _ = crb.rb_ary_clear(self.value.toRaw());
}

pub fn reverse(self: Self) void {
    _ = crb.rb_ary_reverse(self.value.toRaw());
}

pub fn toValue(self: Self) Value {
    return self.value;
}

pub fn toRaw(self: Self) crb.VALUE {
    return self.value.toRaw();
}

pub const Iterator = struct {
    array: Self,
    index: usize,

    pub fn next(self: *Iterator) ?Value {
        if (self.index >= self.array.len()) {
            return null;
        }
        const val = Value.fromRaw(crb.RARRAY_AREF(self.array.value.toRaw(), @as(c_long, @intCast(self.index))));
        self.index += 1;
        return val;
    }
};

pub fn iterator(self: Self) Iterator {
    return .{ .array = self, .index = 0 };
}

const testing = std.testing;

test "create empty array" {
    const arr = new();
    try testing.expectEqual(@as(c_long, 0), arr.len());
    try testing.expect(arr.isEmpty());
}

test "push and get elements" {
    const arr = new();
    arr.push(Value.from(1));
    arr.push(Value.from(2));
    arr.push(Value.from(3));

    try testing.expectEqual(@as(c_long, 3), arr.len());
    try testing.expectEqual(@as(c_int, 1), try arr.get(0).toInt(c_int));
    try testing.expectEqual(@as(c_int, 2), try arr.get(1).toInt(c_int));
    try testing.expectEqual(@as(c_int, 3), try arr.get(2).toInt(c_int));
}

test "pop and shift" {
    const arr = new();
    arr.push(Value.from(1));
    arr.push(Value.from(2));
    arr.push(Value.from(3));

    const popped = arr.pop();
    try testing.expectEqual(@as(c_int, 3), try popped.toInt(c_int));
    try testing.expectEqual(@as(c_long, 2), arr.len());

    const shifted = arr.shift();
    try testing.expectEqual(@as(c_int, 1), try shifted.toInt(c_int));
    try testing.expectEqual(@as(c_long, 1), arr.len());
}

test "iterator" {
    const arr = new();
    arr.push(Value.from(10));
    arr.push(Value.from(20));
    arr.push(Value.from(30));

    var iter = arr.iterator();
    var sum: c_int = 0;
    while (iter.next()) |val| {
        sum += try val.toInt(c_int);
    }

    try testing.expectEqual(@as(c_int, 60), sum);
}

test "fromSlice" {
    const slice = [_]c_int{ 5, 10, 15, 20 };
    const arr = fromSlice(c_int, &slice);

    try testing.expectEqual(@as(c_long, 4), arr.len());
    try testing.expectEqual(@as(c_int, 5), try arr.get(0).toInt(c_int));
    try testing.expectEqual(@as(c_int, 20), try arr.get(3).toInt(c_int));
}

test "clear" {
    const arr = new();
    arr.push(Value.from(1));
    arr.push(Value.from(2));
    try testing.expectEqual(@as(c_long, 2), arr.len());

    arr.clear();
    try testing.expectEqual(@as(c_long, 0), arr.len());
    try testing.expect(arr.isEmpty());
}
