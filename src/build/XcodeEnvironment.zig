const std = @import("std");

pub fn create(allocator: std.mem.Allocator, source: *const std.process.EnvMap) !std.process.EnvMap {
    var result = std.process.EnvMap.init(allocator);
    errdefer result.deinit();
    for ([_][]const u8{ "DEVELOPER_DIR", "PATH", "SDKROOT" }) |name| {
        if (source.get(name)) |value| try result.put(name, value);
    }
    return result;
}

test "Xcode preserves toolchain selection and filters unrelated environment" {
    const names = [_][]const u8{ "DEVELOPER_DIR", "PATH", "SDKROOT" };
    for (0..8) |mask| {
        var source = std.process.EnvMap.init(std.testing.allocator);
        defer source.deinit();
        try source.put("UNRELATED", "excluded");
        for (names, 0..) |name, index| {
            if (mask & (@as(usize, 1) << @intCast(index)) != 0) {
                try source.put(name, name);
            }
        }
        var actual = try create(std.testing.allocator, &source);
        defer actual.deinit();
        try std.testing.expect(actual.get("UNRELATED") == null);
        for (names) |name| {
            if (source.get(name)) |expected| {
                try std.testing.expectEqualStrings(expected, actual.get(name).?);
            } else {
                try std.testing.expect(actual.get(name) == null);
            }
        }
    }
}
