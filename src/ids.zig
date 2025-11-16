const crb = @import("crb.zig").crb;

pub fn init() void {
    @"<=>" = crb.rb_intern("<=>");
    values = crb.rb_intern("values");
    @"key?" = crb.rb_intern("key?");
    keys = crb.rb_intern("keys");
}

pub var @"<=>": crb.ID = undefined;
pub var values: crb.ID = undefined;
pub var @"key?": crb.ID = undefined;
pub var keys: crb.ID = undefined;
