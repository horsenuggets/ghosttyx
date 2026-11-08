const std = @import("std");
const terminal = @import("../terminal/main.zig");

const BLINK_INTERVAL = 600 * std.time.ns_per_ms;
const BLINK_PERIOD = 4 * std.time.ns_per_s / 3;

/// Whether the visible cursor should animate rather than remain steady.
pub fn blinking(state: *const terminal.RenderState, opts: StyleOptions) bool {
    return state.cursor.blinking and
        state.cursor.visible and
        state.cursor.viewport != null and
        !state.cursor.password_input and
        !opts.preedit and
        opts.focused;
}

/// A full-opacity pause after input, then VS Code's smooth blink at 0.75x speed.
pub fn opacity(elapsed_ns: u64) f32 {
    if (elapsed_ns <= BLINK_INTERVAL) return 1;
    const phase = (elapsed_ns - BLINK_INTERVAL) % BLINK_PERIOD;
    const ms: f64 = @as(f64, @floatFromInt(phase)) * 1000 / BLINK_PERIOD;
    if (ms <= 100 or ms >= 900) return 1;
    if (ms >= 300 and ms <= 700) return 0;
    return @floatCast(if (ms < 300)
        1 - easeInOut((ms - 100) / 200)
    else
        easeInOut((ms - 700) / 200));
}

/// Evaluate CSS cubic-bezier(0.42, 0, 0.58, 1), inverting its time axis.
fn easeInOut(time: f64) f64 {
    var lower: f64 = 0;
    var upper: f64 = 1;
    for (0..24) |_| {
        const s = (lower + upper) / 2;
        const inverse = 1 - s;
        const x = 3 * inverse * inverse * s * 0.42 +
            3 * inverse * s * s * 0.58 + s * s * s;
        if (x < time) lower = s else upper = s;
    }
    const s = (lower + upper) / 2;
    return 3 * (1 - s) * s * s + s * s * s;
}

/// Available cursor styles for drawing that renderers must support.
/// This is a superset of terminal cursor styles since the renderer supports
/// some additional cursor states such as the hollow block.
pub const Style = enum {
    // Typical cursor input styles
    block,
    block_hollow,
    bar,
    underline,

    // Special cursor styles
    lock,

    /// Create a cursor style from the terminal style request.
    pub fn fromTerminal(term: terminal.CursorStyle) Style {
        return switch (term) {
            .bar => .bar,
            .block => .block,
            .block_hollow => .block_hollow,
            .underline => .underline,
        };
    }
};

pub const StyleOptions = struct {
    preedit: bool = false,
    focused: bool = false,
    blink_visible: bool = false,
};

/// Returns the cursor style to use for the current render state or null
/// if a cursor should not be rendered at all.
pub fn style(
    state: *const terminal.RenderState,
    opts: StyleOptions,
) ?Style {
    // Note the order of conditionals below is important. It represents
    // a priority system of how we determine what state overrides cursor
    // visibility and style.

    // The cursor must be visible in the viewport to be rendered.
    if (state.cursor.viewport == null) return null;

    // If we are in preedit, then we always show the block cursor. We do
    // this even if the cursor is explicitly not visible because it shows
    // an important editing state to the user.
    if (opts.preedit) return .block;

    // If we're at a password input its always a lock.
    if (state.cursor.password_input) return .lock;

    // If the cursor is explicitly not visible by terminal mode, we don't render.
    if (!state.cursor.visible) return null;

    // If we're not focused, our cursor is always visible so that
    // we can show the hollow box.
    if (!opts.focused) return .block_hollow;

    // If the cursor is blinking and our blink state is not visible,
    // then we don't show the cursor.
    if (state.cursor.blinking and !opts.blink_visible) return null;

    // Otherwise, we use whatever style the terminal wants.
    return .fromTerminal(state.cursor.visual_style);
}

test "cursor: fade timing" {
    const testing = std.testing;
    try testing.expectEqual(@as(f32, 1), opacity(0));
    try testing.expectEqual(@as(f32, 1), opacity(BLINK_INTERVAL));
    const samples = [_]struct { ms: u64, alpha: f32 }{
        .{ .ms = 0, .alpha = 1 },
        .{ .ms = 100, .alpha = 1 },
        .{ .ms = 150, .alpha = 0.8708381 },
        .{ .ms = 200, .alpha = 0.5 },
        .{ .ms = 250, .alpha = 0.1291619 },
        .{ .ms = 300, .alpha = 0 },
        .{ .ms = 500, .alpha = 0 },
        .{ .ms = 700, .alpha = 0 },
        .{ .ms = 750, .alpha = 0.1291619 },
        .{ .ms = 800, .alpha = 0.5 },
        .{ .ms = 850, .alpha = 0.8708381 },
        .{ .ms = 900, .alpha = 1 },
        .{ .ms = 1000, .alpha = 1 },
    };
    for (samples) |sample| {
        try testing.expectApproxEqAbs(
            sample.alpha,
            opacity(BLINK_INTERVAL + sample.ms * BLINK_PERIOD / 1000),
            0.00001,
        );
    }
    for (0..2600) |ms| {
        const elapsed = ms * std.time.ns_per_ms;
        const value = opacity(elapsed);
        try testing.expect(value >= 0 and value <= 1);
        try testing.expectEqual(value, opacity(elapsed));
        try testing.expect(@abs(value - opacity(elapsed + std.time.ns_per_ms)) < 0.009);
        if (elapsed >= BLINK_INTERVAL) {
            try testing.expectEqual(value, opacity(elapsed + BLINK_PERIOD));
        }
    }
}

test "cursor: fade visibility overrides" {
    const testing = std.testing;
    const alloc = testing.allocator;
    var term: terminal.Terminal = try .init(alloc, .{ .cols = 10, .rows = 10 });
    defer term.deinit(alloc);
    var state: terminal.RenderState = .empty;
    defer state.deinit(alloc);
    try state.update(alloc, &term);

    // Exhaust the independent visibility and editing conditions.
    for (0..128) |bits| {
        const focused = bits & 1 != 0;
        const preedit = bits & 2 != 0;
        const visible = bits & 4 != 0;
        const blink = bits & 8 != 0;
        const password = bits & 16 != 0;
        const in_viewport = bits & 32 != 0;
        const blink_visible = bits & 64 != 0;
        state.cursor.visible = visible;
        state.cursor.blinking = blink;
        state.cursor.password_input = password;
        state.cursor.viewport = if (in_viewport) .{ .x = 0, .y = 0, .wide_tail = false } else null;
        const opts: StyleOptions = .{
            .focused = focused,
            .preedit = preedit,
            .blink_visible = blink_visible,
        };
        try testing.expectEqual(
            focused and !preedit and visible and blink and !password and in_viewport,
            blinking(&state, opts),
        );
    }
}

test "cursor: default uses configured style" {
    const testing = std.testing;
    const alloc = testing.allocator;
    var term: terminal.Terminal = try .init(alloc, .{ .cols = 10, .rows = 10 });
    defer term.deinit(alloc);

    term.screens.active.cursor.cursor_style = .bar;
    term.modes.set(.cursor_blinking, true);

    var state: terminal.RenderState = .empty;
    defer state.deinit(alloc);
    try state.update(alloc, &term);

    try testing.expect(style(&state, .{ .preedit = false, .focused = true, .blink_visible = true }) == .bar);
    try testing.expect(style(&state, .{ .preedit = false, .focused = false, .blink_visible = true }) == .block_hollow);
    try testing.expect(style(&state, .{ .preedit = false, .focused = false, .blink_visible = false }) == .block_hollow);
    try testing.expect(style(&state, .{ .preedit = false, .focused = true, .blink_visible = false }) == null);
}

test "cursor: blinking disabled" {
    const testing = std.testing;
    const alloc = testing.allocator;
    var term = try terminal.Terminal.init(alloc, .{ .cols = 10, .rows = 10 });
    defer term.deinit(alloc);

    term.screens.active.cursor.cursor_style = .bar;
    term.modes.set(.cursor_blinking, false);

    var state: terminal.RenderState = .empty;
    defer state.deinit(alloc);
    try state.update(alloc, &term);

    try testing.expect(style(&state, .{ .focused = true, .blink_visible = true }) == .bar);
    try testing.expect(style(&state, .{ .focused = true, .blink_visible = false }) == .bar);
    try testing.expect(style(&state, .{ .focused = false, .blink_visible = true }) == .block_hollow);
    try testing.expect(style(&state, .{ .focused = false, .blink_visible = false }) == .block_hollow);
}

test "cursor: explicitly not visible" {
    const testing = std.testing;
    const alloc = testing.allocator;
    var term = try terminal.Terminal.init(alloc, .{ .cols = 10, .rows = 10 });
    defer term.deinit(alloc);

    term.screens.active.cursor.cursor_style = .bar;
    term.modes.set(.cursor_visible, false);
    term.modes.set(.cursor_blinking, false);

    var state: terminal.RenderState = .empty;
    defer state.deinit(alloc);
    try state.update(alloc, &term);

    try testing.expect(style(&state, .{ .focused = true, .blink_visible = true }) == null);
    try testing.expect(style(&state, .{ .focused = true, .blink_visible = false }) == null);
    try testing.expect(style(&state, .{ .focused = false, .blink_visible = true }) == null);
    try testing.expect(style(&state, .{ .focused = false, .blink_visible = false }) == null);
}

test "cursor: always block with preedit" {
    const testing = std.testing;
    const alloc = testing.allocator;
    var term = try terminal.Terminal.init(alloc, .{ .cols = 10, .rows = 10 });
    defer term.deinit(alloc);

    var state: terminal.RenderState = .empty;
    defer state.deinit(alloc);
    try state.update(alloc, &term);

    // In any bool state
    try testing.expect(style(&state, .{ .preedit = true, .focused = false, .blink_visible = false }) == .block);
    try testing.expect(style(&state, .{ .preedit = true, .focused = true, .blink_visible = false }) == .block);
    try testing.expect(style(&state, .{ .preedit = true, .focused = true, .blink_visible = true }) == .block);
    try testing.expect(style(&state, .{ .preedit = true, .focused = false, .blink_visible = true }) == .block);

    // If we're scrolled though, then we don't show the cursor.
    for (0..100) |_| try term.index();
    term.scrollViewport(.{ .top = {} });
    try state.update(alloc, &term);

    // In any bool state
    try testing.expect(style(&state, .{ .preedit = true, .focused = false, .blink_visible = false }) == null);
    try testing.expect(style(&state, .{ .preedit = true, .focused = true, .blink_visible = false }) == null);
    try testing.expect(style(&state, .{ .preedit = true, .focused = true, .blink_visible = true }) == null);
    try testing.expect(style(&state, .{ .preedit = true, .focused = false, .blink_visible = true }) == null);
}
