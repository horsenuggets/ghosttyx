const std = @import("std");
const testing = std.testing;
const Allocator = std.mem.Allocator;
const lib = @import("../lib.zig");
const CAllocator = lib.alloc.Allocator;
const sgr = @import("../sgr.zig");
const Result = @import("result.zig").Result;

const log = std.log.scoped(.sgr);

/// Wrapper around parser that tracks the allocator for C API usage.
const ParserWrapper = struct {
    parser: sgr.Parser,
    alloc: Allocator,
};

/// C: GhosttySgrParser
pub const Parser = ?*ParserWrapper;

pub fn new(
    alloc_: ?*const CAllocator,
    result: *Parser,
) callconv(lib.calling_conv) Result {
    const alloc = lib.alloc.default(alloc_);
    const ptr = alloc.create(ParserWrapper) catch
        return .out_of_memory;
    ptr.* = .{
        .parser = .empty,
        .alloc = alloc,
    };
    result.* = ptr;
    return .success;
}

pub fn free(parser_: Parser) callconv(lib.calling_conv) void {
    const wrapper = parser_ orelse return;
    const alloc = wrapper.alloc;
    const parser: *sgr.Parser = &wrapper.parser;
    if (parser.params.len > 0) alloc.free(parser.params);
    alloc.destroy(wrapper);
}

pub fn reset(parser_: Parser) callconv(lib.calling_conv) void {
    const wrapper = parser_ orelse return;
    const parser: *sgr.Parser = &wrapper.parser;
    parser.idx = 0;
}

pub fn setParams(
    parser_: Parser,
    params: [*]const u16,
    seps_: ?[*]const u8,
    len: usize,
) callconv(lib.calling_conv) Result {
    const wrapper = parser_ orelse return .invalid_value;
    const alloc = wrapper.alloc;
    const parser: *sgr.Parser = &wrapper.parser;

    // Copy our new parameters
    const params_slice = alloc.dupe(u16, params[0..len]) catch
        return .out_of_memory;
    if (parser.params.len > 0) alloc.free(parser.params);
    parser.params = params_slice;

    // If we have separators, set that state too.
    parser.params_sep = .initEmpty();
    if (seps_) |seps| {
        if (len > @TypeOf(parser.params_sep).bit_length) {
            log.warn("ghostty_sgr_set_params: separators length {} exceeds max supported length {}", .{
                len,
                @TypeOf(parser.params_sep).bit_length,
            });
            return .invalid_value;
        }

        for (seps[0..len], 0..) |sep, i| {
            if (sep == ':') parser.params_sep.set(i);
        }
    }

    // Reset our parsing state
    parser.idx = 0;

    return .success;
}

pub fn next(
    parser_: Parser,
    result: *sgr.Attribute.C,
) callconv(lib.calling_conv) bool {
    const wrapper = parser_ orelse return false;
    const parser: *sgr.Parser = &wrapper.parser;
    if (parser.next()) |attr| {
        result.* = attr.cval();
        return true;
    }

    return false;
}

pub fn unknown_full(
    unknown: sgr.Attribute.Unknown.C,
    ptr: ?*[*]const u16,
) callconv(lib.calling_conv) usize {
    if (ptr) |p| p.* = unknown.full_ptr;
    return unknown.full_len;
}

pub fn unknown_partial(
    unknown: sgr.Attribute.Unknown.C,
    ptr: ?*[*]const u16,
) callconv(lib.calling_conv) usize {
    if (ptr) |p| p.* = unknown.partial_ptr;
    return unknown.partial_len;
}

pub fn attribute_tag(
    attr: sgr.Attribute.C,
) callconv(lib.calling_conv) sgr.Attribute.Tag {
    return attr.tag;
}

pub fn attribute_value(
    attr: *sgr.Attribute.C,
) callconv(lib.calling_conv) *sgr.Attribute.CValue {
    return &attr.value;
}

pub fn wasm_alloc_attribute() callconv(lib.calling_conv) *sgr.Attribute.C {
    const alloc = std.heap.wasm_allocator;
    const ptr = alloc.create(sgr.Attribute.C) catch @panic("out of memory");
    return ptr;
}

pub fn wasm_free_attribute(attr: *sgr.Attribute.C) callconv(lib.calling_conv) void {
    const alloc = std.heap.wasm_allocator;
    alloc.destroy(attr);
}

test "foreground RGBA C parser" {
    var p: Parser = undefined;
    try testing.expectEqual(Result.success, new(&lib.alloc.test_allocator, &p));
    defer free(p);

    const params = [_]u16{ 38, 6, 0, 255, 100, 50, 128, 3 };
    try testing.expectEqual(Result.success, setParams(
        p,
        &params,
        "::::::;;",
        params.len,
    ));
    var attr: sgr.Attribute.C = undefined;
    try testing.expect(next(p, &attr));
    try testing.expectEqual(.direct_color_fg_rgba, attribute_tag(attr));
    const rgba = attribute_value(&attr).direct_color_fg_rgba;
    try testing.expectEqual(@as(u8, 255), rgba.r);
    try testing.expectEqual(@as(u8, 100), rgba.g);
    try testing.expectEqual(@as(u8, 50), rgba.b);
    try testing.expectEqual(@as(u8, 128), rgba.a);
    try testing.expect(next(p, &attr));
    try testing.expectEqual(.italic, attr.tag);
    try testing.expect(!next(p, &attr));

    reset(p);
    try testing.expect(next(p, &attr));
    try testing.expectEqual(.direct_color_fg_rgba, attr.tag);
}

test "foreground RGBA preserves C SGR ABI" {
    const LegacyAttribute = extern struct {
        tag: c_int,
        value: extern union {
            _padding: [8]u64,
        },
    };
    try testing.expectEqual(@sizeOf([8]u64), @sizeOf(sgr.Attribute.CValue));
    try testing.expectEqual(@sizeOf(LegacyAttribute), @sizeOf(sgr.Attribute.C));
    try testing.expectEqual(
        @offsetOf(LegacyAttribute, "value"),
        @offsetOf(sgr.Attribute.C, "value"),
    );
    const existing = .{
        "unset",           "unknown",              "bold",                "reset_bold",          "italic",                "reset_italic",
        "faint",           "underline",            "underline_color",     "256_underline_color", "reset_underline_color", "overline",
        "reset_overline",  "blink",                "reset_blink",         "inverse",             "reset_inverse",         "invisible",
        "reset_invisible", "strikethrough",        "reset_strikethrough", "direct_color_fg",     "direct_color_bg",       "8_bg",
        "8_fg",            "reset_fg",             "reset_bg",            "8_bright_bg",         "8_bright_fg",           "256_bg",
        "256_fg",          "direct_color_fg_rgba",
    };
    inline for (existing, 0..) |name, value| {
        try testing.expectEqual(value, @intFromEnum(@field(sgr.Attribute.Tag, name)));
    }
}

test "alloc" {
    var p: Parser = undefined;
    try testing.expectEqual(Result.success, new(
        &lib.alloc.test_allocator,
        &p,
    ));
    free(p);
}

test "simple params, no seps" {
    var p: Parser = undefined;
    try testing.expectEqual(Result.success, new(
        &lib.alloc.test_allocator,
        &p,
    ));
    defer free(p);

    try testing.expectEqual(Result.success, setParams(
        p,
        &.{1},
        null,
        1,
    ));

    // Set it twice on purpose to make sure we don't leak.
    try testing.expectEqual(Result.success, setParams(
        p,
        &.{1},
        null,
        1,
    ));

    // Verify we get bold
    var attr: sgr.Attribute.C = undefined;
    try testing.expect(next(p, &attr));
    try testing.expectEqual(.bold, attr.tag);

    // Nothing else
    try testing.expect(!next(p, &attr));
}
