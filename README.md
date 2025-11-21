# zig.rb

Type-safe Ruby native extensions written in Zig.

## Overview

`zig.rb` provides a high-level API for creating Ruby extensions in Zig with compile-time type safety, automatic memory management, and idiomatic Zig patterns. The library wraps Ruby's C API with zero-cost abstractions that prevent common errors while maintaining full performance.

## Features

- **Type-safe Value conversions** - Compile-time checked conversions between Ruby and Zig types
- **Automatic memory management** - RubyAllocator integrates with Ruby's GC
- **Class and module definitions** - Define Ruby classes with Zig structs
- **Method binding** - Automatic Ruby method wrappers with arity checking
- **Full Ruby type support** - Fixnum, Bignum, Float, String, Array, Hash, Symbol
- **Format support** - Direct integration with Zig's `std.fmt` for Ruby values
- **Error handling** - Type-safe error propagation between Ruby and Zig

> **Note:** The complete Ruby C API remains available via the raw bindings exposed under `rb.crb.*`.

## Installation

Add `zig.rb` to your `build.zig.zon`:

```zig
.dependencies = .{
    .zig_rb = .{
        .url = "https://github.com/furunkel/zig.rb/archive/main.tar.gz",
        .hash = "...",
    },
},
```

## Quick Start

### Basic Extension

```zig
const rb = @import("zig_rb");
const Value = rb.Value;
const Module = rb.Module;

fn add(_: Value, a: Value, b: Value) Value {
    // first parameter is module self
    const a_int = a.toInt(i64) catch 0;
    const b_int = b.toInt(i64) catch 0;
    return Value.from(a_int + b_int);
}

export fn Init_myextension() void {
    rb.init();
    const mod = Module.define("MyExtension");
    mod.defineFunction(add, "add");
}
```

### Defining Ruby Classes

```zig
const Counter = struct {
    const Self = @This();
    count: i64,

    pub const ruby_type = TypedDataClass.createDataType(Self, "Counter", RubyType);

    pub const RubyType = struct {
        pub fn alloc(_: Value, allocator: std.mem.Allocator) ?*Self {
            const ptr = allocator.create(Self) catch return null;
            ptr.* = .{ .count = 0 };
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

        pub fn get_count(self: *Self) Value {
            return Value.from(self.count);
        }
    };

    pub const Constants = struct {
        pub const VERSION = "1.0.0";
        pub const MAX_VALUE = 1000000;
    };
};

export fn Init_counter() void {
    rb.init();
    _ = TypedDataClass.defineFromStructs("Counter", Counter);
}
```

Ruby usage:

```ruby
counter = Counter.new
counter.increment  # => 1
counter.increment  # => 2
counter.get_count  # => 2
Counter::VERSION   # => "1.0.0"
```

## Type Conversions

### Ruby to Zig

```zig
// Integers (Fixnum and Bignum)
const i = value.toInt(i64) catch 0;
const u = value.toInt(u32) catch 0;

// Floats
const f = value.toFloat(f64) catch 0.0;

// Strings
const str = value.toString() catch "";

// Booleans
const b = value.toBool() catch false;

// Type checking
if (value.isNil()) { ... }
const type_tag = value.getType(); // Returns Value.Type enum
```

### Zig to Ruby

```zig
// From primitives
const v1 = Value.from(42);           // Fixnum
const v2 = Value.from(3.14);         // Float
const v3 = Value.from(true);         // TrueClass
const v4 = Value.from("hello");      // String

// Explicit constructors
const v5 = Value.newInt(i64, 100);
const v6 = Value.newFloat(2.718);
const v7 = Value.newString("world");

// Special values
const nil_val = Value.nil;
const true_val = Value.true;
const false_val = Value.false;
```

## Working with Collections

### Arrays

```zig
const rb = @import("zig_rb");
const Array = rb.Array;
const Value = rb.Value;

fn array_sum(_: Value, rb_array: Value) Value {
    const array = Array.fromValue(rb_array);
    var sum: i64 = 0;
    var iter = array.iterator();
    while (iter.next()) |elem| {
        sum += elem.toInt(i64) catch 0;
    }
    
    return Value.from(sum);
}
```

## Format Support

Ruby values integrate with Zig's `std.fmt`:

```zig
const value = Value.from(42);
std.debug.print("Value: {}\n", .{value}); // Calls Ruby's inspect
```

## Error Handling

```zig
const Error = rb.Error;

fn divide(_: Value, a: Value, b: Value) Value {
    const a_int = a.toInt(i64) catch {
        Error.raiseTypeError("first argument must be an integer");
    };
    const b_int = b.toInt(i64) catch {
        Error.raiseTypeError("second argument must be an integer");
    };
    
    if (b_int == 0) {
        Error.raiseArgumentError("division by zero");
    }
    
    return Value.from(@divTrunc(a_int, b_int));
}
```

## Build Integration

Use the provided build utilities for seamless integration:

```zig
const std = @import("std");

pub fn build(b: *std.Build) void {
    const ruby = @import("zig_rb").ruby;
    
    // Get Ruby configuration
    const ruby_config = try ruby.getConfig(b);
    
    // Create extension
    const ext = ruby.addExtension(b, &ruby_config, .{
        .name = "myextension",
        .root_module = my_module,
    });
    
    // Install to lib/ for development
    try ruby.installExtensionToLib(b, &ruby_config, ext, "myextension");
}
```

## API Reference

### Core Types

- **`Value`** - Wrapper for Ruby VALUE with type-safe conversions
- **`TypedDataClass`** - Define Ruby classes backed by Zig structs
- **`Module`** - Define Ruby modules and singleton methods
- **`Array`** - Ruby Array operations
- **`Hash`** - Ruby Hash operations
- **`Error`** - Raise Ruby exceptions
- **`RubyAllocator`** - std.mem.Allocator that uses Ruby's memory allocation system

## Supported Ruby Types

| Ruby Type | Zig Type | Notes |
|-----------|----------|-------|
| Fixnum | `i8` to `i64`, `u8` to `u64` | Native integer types |
| Bignum | `std.math.big.int.Managed` | Arbitrary precision |
| Float | `f32`, `f64` | IEEE 754 floats |
| String | `[]const u8` | UTF-8 byte slices |
| Symbol | `Value` | Via `Value.toSymbol()` |
| Array | `Array` | Indexed collection |
| Hash | `Hash` | Key-value store |
| true/false | `bool` | Boolean values |
| nil | `Value.nil` | Null value |

## Examples

See the [`example/`](example/) directory for a complete gem project demonstrating:

- Standard Ruby gem structure
- Build system integration
- Extension compilation
- Testing with minitest
- Gem packaging

## Requirements

- Zig 0.15.2 or later
- Ruby 2.6 or later
- C compiler (for Ruby headers)

## License

MIT

## Contributing

Contributions welcome. Please ensure all tests pass before submitting PRs.

```bash
zig build test
```

## TODO

- Conversion helpers between Zig maps and Ruby Hash values
- Custom Ruby error type wrappers
