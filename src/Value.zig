const std = @import("std");
const builtin = @import("builtin");
const crb = @import("crb.zig").crb;
const ids = @import("ids.zig");
const Self = @This();

raw: crb.VALUE,

pub const nil = Self{ .raw = crb.Qnil };
pub const @"true" = Self{ .raw = crb.Qtrue };
pub const @"false" = Self{ .raw = crb.Qfalse };

pub const ConversionError = error{
    UnsupportedConversion,
    TypeError,
};

pub const Type = enum(c_int) {
    none = crb.RUBY_T_NONE,
    object = crb.RUBY_T_OBJECT,
    class = crb.RUBY_T_CLASS,
    module = crb.RUBY_T_MODULE,
    float = crb.RUBY_T_FLOAT,
    string = crb.RUBY_T_STRING,
    regexp = crb.RUBY_T_REGEXP,
    array = crb.RUBY_T_ARRAY,
    hash = crb.RUBY_T_HASH,
    @"struct" = crb.RUBY_T_STRUCT,
    bignum = crb.RUBY_T_BIGNUM,
    file = crb.RUBY_T_FILE,
    data = crb.RUBY_T_DATA,
    match = crb.RUBY_T_MATCH,
    complex = crb.RUBY_T_COMPLEX,
    rational = crb.RUBY_T_RATIONAL,
    nil = crb.RUBY_T_NIL,
    true = crb.RUBY_T_TRUE,
    false = crb.RUBY_T_FALSE,
    symbol = crb.RUBY_T_SYMBOL,
    fixnum = crb.RUBY_T_FIXNUM,
    undef = crb.RUBY_T_UNDEF,
};

pub fn fromRaw(raw: crb.VALUE) Self {
    return .{ .raw = raw };
}

pub fn toRaw(self: Self) crb.VALUE {
    return self.raw;
}

pub fn from(value: anytype) Self {
    if (@TypeOf(value) == Self) {
        return value;
    }
    return .{ .raw = toRuby(value) };
}

pub fn isEql(self: Self, other: Self) bool {
    return crb.rb_eql(self.toRaw(), other.toRaw()) != 0;
}

pub fn isEqual(self: Self, other: Self) bool {
    return crb.rb_equal(self.toRaw(), other.toRaw()) != 0;
}

pub fn isIdentical(self: Self, other: Self) bool {
    return self.toRaw() == other.toRaw();
}

pub fn newString(str: []const u8) Self {
    return .{ .raw = crb.rb_str_new(str.ptr, @intCast(str.len)) };
}

pub fn newInt(comptime T: type, value: T) Self {
    return .{ .raw = intToRuby(T, value) };
}

pub fn newFloat(value: f64) Self {
    return .{ .raw = crb.rb_float_new(value) };
}

pub fn fromBool(value: bool) Self {
    return .{ .raw = if (value) crb.Qtrue else crb.Qfalse };
}

fn packFlags() c_int {
    return switch (builtin.cpu.arch.endian()) {
        .little => crb.INTEGER_PACK_2COMP | crb.INTEGER_PACK_LITTLE_ENDIAN,
        .big => crb.INTEGER_PACK_2COMP | crb.INTEGER_PACK_BIG_ENDIAN,
    };
}

fn packBufferBits(val: crb.VALUE) !usize {
    var size: usize = undefined;
    const neg = if (crb.FIXNUM_P(val)) crb.FIX2LONG(val) < 0 else crb.RBIGNUM_NEGATIVE_P(val);
    var nlz_bits: c_int = undefined;
    size = crb.rb_absint_numwords(val, 1, @ptrCast(@alignCast(&nlz_bits)));
    if (nlz_bits == 0 and !(neg and crb.rb_absint_singlebit_p(val) != 0))
        size += 1;
    return size;
}

pub fn fromBigInt(value: anytype, allocator: std.mem.Allocator) !Self {
    var value_const: std.math.big.int.Const = undefined;
    var value_managed: ?std.math.big.int.Managed = null;
    defer {
        if (value_managed) |*m| {
            m.deinit();
        }
    }

    const T = @TypeOf(value);

    switch (@typeInfo(T)) {
        .int, .comptime_int => {
            const value_managed_ = try std.math.big.int.Managed.initSet(allocator, value);
            value_const = value_managed_.toConst();
            value_managed = value_managed_;
        },
        .@"struct" => {
            if (T == std.math.big.int.Const) {
                value_const = value;
            } else if (T == std.math.big.int.Managed) {
                // don't set value_managed, as this one is not owned by us
                value_const = value.toConst();
            }
        },
        else => @compileError("Unsupported type for BigInt conversion"),
    }

    if (value_const.eqlZero()) {
        return .{ .raw = crb.INT2NUM(0) };
    }

    const bit_count = value_const.bitCountTwosCompForSignedness(.signed);

    const num_bytes = try std.math.divCeil(usize, bit_count, @bitSizeOf(u8));
    const byte_aligned_bit_count = num_bytes * 8;

    const buf_bytes = try allocator.alloc(u8, num_bytes);
    defer allocator.free(buf_bytes);
    @memset(buf_bytes, 0);

    value_const.writePackedTwosComplement(buf_bytes, 0, byte_aligned_bit_count, builtin.cpu.arch.endian());

    const rb_packed = crb.rb_integer_unpack(@ptrCast(@alignCast(@constCast(buf_bytes.ptr))), @intCast(num_bytes), @sizeOf(u8), 0, packFlags());

    return .{ .raw = rb_packed };
}

pub fn toBigInt(self: Self, allocator: std.mem.Allocator) !std.math.big.int.Managed {
    switch (self.getType()) {
        .fixnum => {
            const val = crb.NUM2LONG(self.raw);
            var result = try std.math.big.int.Managed.init(allocator);
            errdefer result.deinit();
            try result.set(val);
            return result;
        },
        .bignum => {
            const num_bits = try packBufferBits(self.raw);

            const num_bytes = try std.math.divCeil(usize, @intCast(num_bits), @bitSizeOf(u8));
            const buf = try allocator.alloc(u8, num_bytes);
            defer allocator.free(buf);
            @memset(buf, 0);

            _ = crb.rb_integer_pack(self.raw, buf.ptr, @intCast(num_bytes), @sizeOf(u8), 0, packFlags());

            var result = try std.math.big.int.Managed.init(allocator);
            errdefer result.deinit();

            const bytes = buf;

            // Ensure we have enough capacity for the limbs
            const Limb = std.math.big.Limb;
            const read_bit_count = num_bytes * 8;
            const num_limbs = (read_bit_count + @bitSizeOf(Limb) - 1) / @bitSizeOf(Limb);
            try result.ensureCapacity(num_limbs);

            var mutable = result.toMutable();

            // read full bytes
            mutable.readPackedTwosComplement(bytes, 0, read_bit_count, builtin.cpu.arch.endian(), .signed);

            // Update the Managed's metadata with the values from mutable
            result.setMetadata(mutable.positive, mutable.len);

            return result;
        },
        else => return ConversionError.TypeError,
    }
}

pub fn to(self: Self, comptime T: type) ConversionError!T {
    return fromRuby(T, self.raw);
}

pub fn toInt(self: Self, comptime T: type) ConversionError!T {
    return fromRuby(T, self.raw);
}

pub fn toFloat(self: Self, comptime T: type) ConversionError!T {
    return fromRuby(T, self.raw);
}

pub fn toBool(self: Self) ConversionError!bool {
    return fromRuby(bool, self.raw);
}

pub fn toString(self: Self) ConversionError![]const u8 {
    return fromRuby([]const u8, self.raw);
}

pub fn isNil(self: Self) bool {
    return self.raw == crb.Qnil;
}

pub fn isTrue(self: Self) bool {
    return self.raw == crb.Qtrue;
}

pub fn isFalse(self: Self) bool {
    return self.raw == crb.Qfalse;
}

pub fn isTruthy(self: Self) bool {
    return self.raw != crb.Qnil and self.raw != crb.Qfalse;
}

pub fn isFalsy(self: Self) bool {
    return self.raw == crb.Qnil or self.raw == crb.Qfalse;
}

pub fn getType(self: Self) Type {
    return @enumFromInt(crb.rb_type(self.raw));
}

pub fn getTypeRaw(self: Self) c_int {
    return crb.rb_type(self.raw);
}

pub fn symbol(str: []const u8) Self {
    return .{ .raw = crb.ID2SYM(crb.rb_intern2(str.ptr, @intCast(str.len))) };
}

pub fn order(self: Self, other: Self) std.math.Order {
    const cmp_result = crb.rb_cmpint(crb.rb_funcall(self.raw, ids.@"<=>", 1, other.raw), self.raw, other.raw);
    if (cmp_result < 0) {
        return .lt;
    } else if (cmp_result > 0) {
        return .gt;
    } else {
        return .eq;
    }
}

fn toRuby(value: anytype) crb.VALUE {
    const T = @TypeOf(value);

    switch (@typeInfo(T)) {
        .int => return intToRuby(T, value),
        .comptime_int => return comptimeIntToRuby(value),
        .float, .comptime_float => return crb.rb_float_new(value),
        .bool => return if (value) crb.Qtrue else crb.Qfalse,
        .pointer => |ptr_info| {
            switch (ptr_info.size) {
                .one => {
                    // Handle pointer to array (string literals)
                    if (@typeInfo(ptr_info.child) == .array) {
                        const array_info = @typeInfo(ptr_info.child).array;
                        if (array_info.child == u8) {
                            // This is a string literal like "*const [N:0]u8"
                            const str: [*:0]const u8 = @ptrCast(value);
                            return crb.rb_str_new_cstr(str);
                        }
                    }
                },
                .slice => {
                    // Handle string slices
                    if (ptr_info.child == u8) {
                        const str: []const u8 = value;
                        return crb.rb_str_new(str.ptr, @intCast(str.len));
                    }
                },
                else => {},
            }
            @compileError("don't know how to convert pointer type '" ++ @typeName(T) ++ "' to Ruby");
        },
        else => @compileError("don't know how to convert type '" ++ @typeName(T) ++ "' to Ruby"),
    }
}

fn intToRuby(comptime T: type, value: T) crb.VALUE {
    const info = @typeInfo(T).int;
    const int_bits = @typeInfo(c_int).int.bits;
    const uint_bits = @typeInfo(c_uint).int.bits;
    const long_bits = @typeInfo(c_long).int.bits;
    const ulong_bits = @typeInfo(c_ulong).int.bits;

    // Small integers fit in c_int
    if (info.bits < int_bits) {
        return crb.RB_INT2FIX(@as(c_int, value));
    }

    // Match by signedness and size
    if (info.signedness == .signed) {
        if (info.bits <= int_bits) {
            return crb.RB_INT2FIX(value);
        } else if (info.bits <= long_bits) {
            return crb.RB_LONG2NUM(value);
        }
    } else {
        if (info.bits <= uint_bits) {
            return crb.RB_UINT2NUM(value);
        } else if (info.bits <= ulong_bits) {
            return crb.RB_ULONG2NUM(value);
        }
    }

    @compileError("cannot convert integer type '" ++ @typeName(T) ++ "' to Ruby");
}

fn comptimeIntToRuby(comptime value: comptime_int) crb.VALUE {
    const long_bits = @typeInfo(c_long).int.bits;
    // See https://github.com/ruby/ruby/blob/97c133a8591495156f46b53c613abee8c7088a04/spec/mspec/lib/mspec/helpers/numeric.rb#L46
    const max_fixnum = (2 << (long_bits - 3)) - 1;
    const min_fixnum = -(2 << (long_bits - 3));

    if (comptime value >= min_fixnum and value <= max_fixnum) {
        return crb.RB_INT2FIX(value);
    } else {
        return crb.RB_LONG2NUM(value);
    }
}

fn fromRuby(comptime T: type, rb_value: crb.VALUE) ConversionError!T {
    switch (@typeInfo(T)) {
        .int => return intFromRuby(T, rb_value),
        .bool => return boolFromRuby(rb_value),
        else => {
            // Handle special types
            if (T == []const u8) {
                return stringFromRuby(rb_value);
            } else if (T == f64) {
                return floatFromRuby(rb_value);
            }
            return ConversionError.UnsupportedConversion;
        },
    }
}

fn intFromRuby(comptime T: type, rb_value: crb.VALUE) ConversionError!T {
    const rb_type = crb.rb_type(rb_value);
    if (rb_type != crb.RUBY_T_FIXNUM and rb_type != crb.RUBY_T_BIGNUM) {
        return ConversionError.TypeError;
    }

    const info = @typeInfo(T).int;

    if (info.signedness == .signed) {
        const raw: c_longlong = crb.rb_num2ll(rb_value);
        const casted = std.math.cast(T, raw) orelse return ConversionError.UnsupportedConversion;
        return casted;
    } else {
        const raw: c_ulonglong = crb.rb_num2ull(rb_value);
        const casted = std.math.cast(T, raw) orelse return ConversionError.UnsupportedConversion;
        return casted;
    }
}

fn floatFromRuby(rb_value: crb.VALUE) ConversionError!f64 {
    const rb_type = crb.rb_type(rb_value);

    switch (rb_type) {
        crb.RUBY_T_FLOAT => return crb.rb_num2dbl(rb_value),
        crb.RUBY_T_FIXNUM, crb.RUBY_T_BIGNUM => return crb.rb_num2dbl(rb_value),
        else => return ConversionError.TypeError,
    }
}

fn boolFromRuby(rb_value: crb.VALUE) ConversionError!bool {
    const rb_type = crb.rb_type(rb_value);

    return switch (rb_type) {
        crb.RUBY_T_FALSE => false,
        crb.RUBY_T_TRUE => true,
        else => ConversionError.TypeError,
    };
}

fn stringFromRuby(rb_value: crb.VALUE) ConversionError![]const u8 {
    const rb_type = crb.rb_type(rb_value);

    if (rb_type != crb.RUBY_T_STRING) {
        return ConversionError.TypeError;
    }

    const ptr = crb.RSTRING_PTR(rb_value);
    const len = crb.RSTRING_LEN(rb_value);
    return ptr[0..@intCast(len)];
}

pub fn format(
    self: Self,
    writer: *std.Io.Writer,
) std.Io.Writer.Error!void {
    // Call Ruby's inspect method to get a string representation
    const inspect_result = crb.rb_funcall(self.raw, crb.rb_intern("inspect"), 0);
    const inspect_str = stringFromRuby(inspect_result) catch {
        // Fallback if inspect fails
        try writer.print("Value{{raw=0x{x}}}", .{self.raw});
        return;
    };

    try writer.writeAll(inspect_str);
}

test "format" {
    const testing = std.testing;

    const allocator = testing.allocator;

    {
        var allocating = std.io.Writer.Allocating.init(allocator);
        defer allocating.deinit();

        const int_value = Self.from(42);
        try int_value.format(&allocating.writer);

        const int_output = try allocating.toOwnedSlice();
        defer allocator.free(int_output);
        try testing.expectEqualStrings("42", int_output);
    }

    {
        var allocating = std.io.Writer.Allocating.init(allocator);
        defer allocating.deinit();

        const str_value = Self.newString("hello");
        try str_value.format(&allocating.writer);

        const str_output = try allocating.toOwnedSlice();
        defer allocator.free(str_output);
        try testing.expectEqualStrings("\"hello\"", str_output);
    }

    {
        var allocating = std.io.Writer.Allocating.init(allocator);
        defer allocating.deinit();

        const nil_value = Self.nil;
        try nil_value.format(&allocating.writer);

        const nil_output = try allocating.toOwnedSlice();
        defer allocator.free(nil_output);
        try testing.expectEqualStrings("nil", nil_output);
    }
}

test "integer round-trip conversions" {
    const testing = std.testing;

    const signed_values = [_]c_longlong{
        0,
        1,
        -1,
        std.math.maxInt(c_int),
        std.math.minInt(c_int),
        @as(c_longlong, 1) << 40,
        -(@as(c_longlong, 1) << 40),
    };

    inline for (signed_values) |value| {
        const ruby_value = Self.from(value);
        const round_trip = try ruby_value.toInt(c_longlong);
        try testing.expectEqual(value, round_trip);
    }

    const unsigned_values = [_]c_ulonglong{
        std.math.maxInt(c_uint),
        std.math.maxInt(c_ulong),
        @as(c_ulonglong, 1) << 40,
        (@as(c_ulonglong, 1) << 63) | 12345,
    };

    inline for (unsigned_values) |value| {
        const ruby_value = Self.from(value);
        const round_trip = try ruby_value.toInt(c_ulonglong);
        try testing.expectEqual(value, round_trip);
    }
}

test "big int round-trip conversions" {
    const allocator = std.testing.allocator;

    const literals = [_][]const u8{
        // Small numbers
        "0",
        "1",
        "-1",
        "2",
        "-2",
        // Byte boundaries (i8)
        "127",
        "-127",
        "128",
        "-128",
        // Word boundaries (i16)
        "255",
        "-255",
        "256",
        "-256",
        "32767",
        "-32767",
        "32768",
        "-32768",
        // Dword boundaries (i32)
        "65535",
        "-65535",
        "65536",
        "-65536",
        "2147483647",
        "-2147483647",
        "2147483648",
        "-2147483648",
        // Qword boundaries (i64)
        "4294967295",
        "-4294967295",
        "4294967296",
        "-4294967296",
        "9223372036854775807",
        "-9223372036854775807",
        "9223372036854775808",
        "-9223372036854775808",
        // Powers of 2 and near powers of 2
        "1023",
        "-1023",
        "1024",
        "-1024",
        "1025",
        "-1025",
        "16383",
        "-16383",
        "16384",
        "-16384",
        "16385",
        "-16385",
        // Large numbers
        "123456789123456789123456789123456789123456789",
        "-987654321987654321987654321987654321987654321",
        "1844674407370955161600000000000000000000000000000",
        // Random large numbers
        "57896044618658097711785492504343953926634992332820282019728792003956564819967",
        "-28948022309329048855892746252171976963317496166410141009864396001978282409983",
        "45671234567890123456789012345678901234567890123456789012345678901234567890",
        "-98765432109876543210987654321098765432109876543210987654321098765432109876",
        "11111111111111111111111111111111111111111111111111111111111111111111111111",
        "-22222222222222222222222222222222222222222222222222222222222222222222222222",
        "77777777777777777777777777777777777777777777777777777777777777777777777777",
        "-33333333333333333333333333333333333333333333333333333333333333333333333333",
        "12345678901234567890123456789012345678901234567890123456789012345678901234",
        "-98765432109876543210987654321098765432109876543210987654321098765432109",
        "99999999999999999999999999999999999999999999999999999999999999999999999999",
        "-88888888888888888888888888888888888888888888888888888888888888888888888888",
        "13579246801357924680135792468013579246801357924680135792468013579246801357",
        "-24680135792468013579246801357924680135792468013579246801357924680135792468",
        "55555555555555555555555555555555555555555555555555555555555555555555555555",
        "-66666666666666666666666666666666666666666666666666666666666666666666666666",
        "10000000000000000000000000000000000000000000000000000000000000000000000001",
        "-10000000000000000000000000000000000000000000000000000000000000000000000002",
        "31415926535897932384626433832795028841971693993751058209749445923078164062",
        "-27182818284590452353602874713526624977572470936999595749669676277240766303",
        "-57896044618658097711785492504343953926634992332820282019728792003956564819968",
        "57896044618658097711785492504343953926634992332820282019728792003956564819967",
    };

    inline for (literals) |literal| {
        const int = try std.fmt.parseInt(i256, literal, 10);
        const big_int_val = try Self.fromBigInt(int, allocator);
        var int_ = try big_int_val.toBigInt(allocator);
        defer int_.deinit();
        var int_managed = try std.math.big.int.Managed.initSet(allocator, int);
        defer int_managed.deinit();
        try std.testing.expectEqual(int_.order(int_managed), .eq);
    }
}

test "float round-trip conversions" {
    const testing = std.testing;

    const floats = [_]f64{
        0.0,
        -123.456,
        98765.4321,
        std.math.pi,
        -std.math.tau / 3.0,
    };

    inline for (floats) |value| {
        const ruby_value = Self.from(value);
        const round_trip = try ruby_value.toFloat(f64);
        try testing.expectEqual(value, round_trip);
    }
}

test "string round-trip conversions" {
    const testing = std.testing;

    const bytes = [_]u8{ 'b', 'y', 't', 'e', 0, 's', '!', 0xff };
    const slice = bytes[0..];

    const ruby_value = Self.newString(slice);
    const round_trip = try ruby_value.toString();
    try testing.expectEqualSlices(u8, slice, round_trip);
}

test "boolean conversions and truthiness" {
    const testing = std.testing;

    try testing.expect(try Self.from(true).toBool());
    try testing.expect(!(try Self.from(false).toBool()));

    try testing.expect(Self.true.isTruthy());
    try testing.expect(!Self.false.isTruthy());
    try testing.expect(!Self.nil.isTruthy());

    try testing.expect(!Self.true.isFalsy());
    try testing.expect(Self.false.isFalsy());
    try testing.expect(Self.nil.isFalsy());
}

test "symbol creation" {
    const testing = std.testing;

    const sym1 = Self.symbol("test");
    try testing.expectEqual(Type.symbol, sym1.getType());

    const sym2 = Self.symbol("test");
    try testing.expectEqual(sym1.toRaw(), sym2.toRaw());

    const sym3 = Self.symbol("other");
    try testing.expect(sym1.toRaw() != sym3.toRaw());
}

test "order" {
    const testing = std.testing;

    {
        const a = Self.from(5);
        const b = Self.from(10);
        const c = Self.from(5);

        try testing.expectEqual(std.math.Order.lt, a.order(b));
        try testing.expectEqual(std.math.Order.gt, b.order(a));
        try testing.expectEqual(std.math.Order.eq, a.order(c));
    }

    {
        const f1 = Self.from(3.14);
        const f2 = Self.from(2.71);
        const f3 = Self.from(3.14);

        try testing.expectEqual(std.math.Order.gt, f1.order(f2));
        try testing.expectEqual(std.math.Order.lt, f2.order(f1));
        try testing.expectEqual(std.math.Order.eq, f1.order(f3));
    }

    {
        const s1 = Self.newString("apple");
        const s2 = Self.newString("banana");
        const s3 = Self.newString("apple");

        try testing.expectEqual(std.math.Order.lt, s1.order(s2));
        try testing.expectEqual(std.math.Order.gt, s2.order(s1));
        try testing.expectEqual(std.math.Order.eq, s1.order(s3));
    }
}

test "equality functions" {
    const testing = std.testing;

    // isIdentical - checks object identity (same object in memory)
    {
        const a = Self.from(42);
        const b = Self.from(42);
        const c = a;

        try testing.expect(a.isIdentical(c));
        try testing.expect(a.isIdentical(b));
    }

    // isEqual - Ruby's == operator (value equality)
    {
        const s1 = Self.newString("hello");
        const s2 = Self.newString("hello");
        const s3 = Self.newString("world");

        try testing.expect(s1.isEqual(s2));
        try testing.expect(!s1.isEqual(s3));

        const n1 = Self.from(100);
        const n2 = Self.from(100);
        const n3 = Self.from(200);
        const n4 = Self.from(200.0);

        try testing.expect(n1.isEqual(n2));
        try testing.expect(!n1.isEqual(n3));
        try testing.expect(n3.isEqual(n4));
    }

    // isEql - Ruby's eql? method (stricter equality, checks type and value)
    {
        const int1 = Self.from(42);
        const int2 = Self.from(42);
        const float1 = Self.from(42.0);

        try testing.expect(int1.isEql(int2));
        try testing.expect(!int1.isEql(float1));

        const str1 = Self.newString("test");
        const str2 = Self.newString("test");
        const sym = Self.symbol("test");

        try testing.expect(str1.isEql(str2));
        try testing.expect(!str1.isEql(sym));
    }
}
