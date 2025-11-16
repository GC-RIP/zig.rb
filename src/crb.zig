pub const crb = @cImport({
    @cInclude("ruby/ruby.h");
    @cInclude("ruby/intern.h");
    @cInclude("ruby/internal/core/rbignum.h");
});
