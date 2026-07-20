// SPDX-FileCopyrightText: © 2026 The River Developers
// SPDX-License-Identifier: GPL-3.0-only

//! set-output-icc: apply a display ICC profile to a river output via the
//! private psyclyx_color_management_v1 protocol.
//!
//! Like swaybg, this holds the Wayland connection open: the color correction
//! persists only while the process runs, so killing it reverts the output to
//! uncorrected. Run it (once per calibrated output) from the session, e.g. as a
//! systemd user service.
//!
//!   set-output-icc <output_name> <icc_file>   apply and hold
//!   set-output-icc --list                     list outputs, then exit

const std = @import("std");
const mem = std.mem;
const wayland = @import("wayland");
const wl = wayland.client.wl;
const psyclyx = wayland.client.psyclyx;

const io = std.Io.Threaded.global_single_threaded.io();

/// Reject absurd ICC sizes; matches the compositor-side limit.
const max_icc_bytes = 64 << 20;

const OutputInfo = struct {
    proxy: *wl.Output,
    name: ?[]u8 = null,
    description: ?[]u8 = null,
    state: *State,
};

/// A target matches an output if it equals the connector name (e.g. "DP-1") or
/// is a prefix of the wl_output description (e.g. "QHX GF005", which river
/// reports as "QHX GF005 (DP-1)"). The latter lets callers target a panel by
/// its make/model/serial identity so a profile follows it across connectors,
/// matching how monitors are keyed elsewhere (kanshi, egregore).
fn matches(info: *const OutputInfo, target: []const u8) bool {
    if (info.name) |n| if (mem.eql(u8, n, target)) return true;
    if (info.description) |d| if (mem.startsWith(u8, d, target)) return true;
    return false;
}

const State = struct {
    alloc: mem.Allocator,
    manager: ?*psyclyx.ColorManagementV1 = null,
    outputs: [32]OutputInfo = undefined,
    output_count: usize = 0,
    target_name: ?[]const u8 = null,
    target: ?*wl.Output = null,
};

fn usage() noreturn {
    std.debug.print(
        \\Usage: set-output-icc <output> <icc_file>
        \\       set-output-icc --list
        \\
        \\<output> is a connector name (e.g. DP-1) or a make/model/serial identity
        \\prefix (e.g. "QHX GF005"), so a profile can follow a panel across ports.
        \\
    , .{});
    std.process.exit(1);
}

pub fn main(init: std.process.Init.Minimal) !void {
    var arena_state = std.heap.ArenaAllocator.init(std.heap.c_allocator);
    defer arena_state.deinit();
    const arena = arena_state.allocator();

    const args = try init.args.toSlice(arena);
    if (args.len < 2) usage();

    const arg1 = args[1];
    const list_mode = mem.eql(u8, arg1, "--list");
    if (!list_mode and args.len < 3) usage();

    var state: State = .{ .alloc = std.heap.c_allocator };
    if (!list_mode) state.target_name = arg1;

    const display = try wl.Display.connect(null);
    const registry = try display.getRegistry();
    registry.setListener(*State, registryListener, &state);

    // First roundtrip binds the globals; the second delivers wl_output.name.
    // First roundtrip binds the globals; the second delivers wl_output name +
    // description events.
    if (display.roundtrip() != .SUCCESS) return error.RoundtripFailed;
    if (display.roundtrip() != .SUCCESS) return error.RoundtripFailed;

    if (list_mode) {
        std.debug.print("Outputs (connector — description):\n", .{});
        for (state.outputs[0..state.output_count]) |o| {
            std.debug.print("  {s} — {s}\n", .{ o.name orelse "(unnamed)", o.description orelse "" });
        }
        std.debug.print("Manager: {s}\n", .{
            if (state.manager != null) "present" else "MISSING (not a patched river?)",
        });
        return;
    }

    if (state.target_name) |target_name| {
        for (state.outputs[0..state.output_count]) |*o| {
            if (matches(o, target_name)) {
                state.target = o.proxy;
                break;
            }
        }
    }

    const manager = state.manager orelse {
        std.debug.print("psyclyx_color_management_v1 not available (is this a patched river?)\n", .{});
        std.process.exit(1);
    };
    const target = state.target orelse {
        std.debug.print("output '{s}' not found; available:\n", .{state.target_name.?});
        for (state.outputs[0..state.output_count]) |o| {
            std.debug.print("  {s}\n", .{o.name orelse "(unnamed)"});
        }
        std.process.exit(1);
    };

    // Keep the file open for the life of the process; libwayland dups the fd at
    // marshal time, but holding it open is harmless and simplest.
    const path = args[2];
    var file = std.Io.Dir.cwd().openFile(io, path, .{}) catch |err| {
        std.debug.print("cannot open ICC profile '{s}': {s}\n", .{ path, @errorName(err) });
        std.process.exit(1);
    };
    const stat = file.stat(io) catch |err| {
        std.debug.print("cannot stat ICC profile '{s}': {s}\n", .{ path, @errorName(err) });
        std.process.exit(1);
    };
    if (stat.size == 0 or stat.size > max_icc_bytes) {
        std.debug.print("ICC profile '{s}' has bad size {d}\n", .{ path, stat.size });
        std.process.exit(1);
    }

    const color = try manager.getOutputColor(target);
    color.setListener(?*anyopaque, colorListener, null);
    color.setIccProfile(file.handle, 0, @intCast(stat.size));
    if (display.flush() != .SUCCESS) return error.FlushFailed;

    // Hold the connection: the correction lives as long as we do. A failed
    // event (handled in colorListener) exits non-zero; otherwise loop until the
    // display disconnects or we are killed, at which point the compositor
    // reverts the output.
    while (display.dispatch() == .SUCCESS) {}
}

fn registryListener(registry: *wl.Registry, event: wl.Registry.Event, state: *State) void {
    switch (event) {
        .global => |g| {
            if (mem.orderZ(u8, g.interface, "wl_output") == .eq) {
                if (state.output_count >= state.outputs.len) return;
                const proxy = registry.bind(g.name, wl.Output, 4) catch return;
                const info = &state.outputs[state.output_count];
                info.* = .{ .proxy = proxy, .state = state };
                state.output_count += 1;
                proxy.setListener(*OutputInfo, outputListener, info);
            } else if (mem.orderZ(u8, g.interface, "psyclyx_color_management_v1") == .eq) {
                state.manager = registry.bind(g.name, psyclyx.ColorManagementV1, 1) catch return;
            }
        },
        .global_remove => {},
    }
}

fn outputListener(_: *wl.Output, event: wl.Output.Event, info: *OutputInfo) void {
    switch (event) {
        .name => |n| info.name = info.state.alloc.dupe(u8, mem.span(n.name)) catch null,
        .description => |d| info.description = info.state.alloc.dupe(u8, mem.span(d.description)) catch null,
        else => {},
    }
}

fn colorListener(
    _: *psyclyx.ColorManagementOutputV1,
    event: psyclyx.ColorManagementOutputV1.Event,
    _: ?*anyopaque,
) void {
    switch (event) {
        .failed => {
            std.debug.print("failed: could not take color control of the output " ++
                "(already controlled by another client, or unsupported)\n", .{});
            std.process.exit(1);
        },
    }
}
