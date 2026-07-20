// SPDX-FileCopyrightText: © 2026 The River Developers
// SPDX-License-Identifier: GPL-3.0-only

//! Server implementation of the private psyclyx_color_management_v1 protocol.
//!
//! A client takes exclusive control of an output's color via a per-output
//! object and assigns a display ICC profile. The resulting transform is stored
//! on the Output and applied by the scene after blending (see
//! Output.renderAndCommit). The correction is bound to the object's lifetime:
//! destroying it, or the client disconnecting, reverts the output to an
//! uncorrected transform — so killing the controlling process is a reliable
//! undo, à la wlr-gamma-control / swaybg.

const ColorManagement = @This();

const std = @import("std");
const mem = std.mem;
const wlr = @import("wlroots");
const wayland = @import("wayland");
const wl = wayland.server.wl;
const psyclyx = wayland.server.psyclyx;

const server = &@import("main.zig").server;
const util = @import("util.zig");

const ColorTransform = @import("ColorTransform.zig");
const Output = @import("Output.zig");

const log = std.log.scoped(.output);

/// Reject absurd ICC sizes; matches the limit documented in the protocol.
const max_icc_bytes = 64 << 20;

global: *wl.Global,

pub fn init(cm: *ColorManagement) !void {
    cm.* = .{
        .global = try wl.Global.create(server.wl_server, psyclyx.ColorManagementV1, 1, ?*anyopaque, null, bind),
    };
}

pub fn deinit(cm: *ColorManagement) void {
    cm.global.destroy();
}

/// Make an output's color control object inert because the output is going
/// away. The object survives client-side until the client destroys it, but no
/// longer references the (soon to be freed) Output. Called from
/// Output.handleDestroy.
pub fn makeOutputInert(output: *Output) void {
    if (output.color_object) |object| {
        object.setHandler(?*anyopaque, handleOutputInert, null, null);
        output.color_object = null;
    }
}

fn bind(client: *wl.Client, _: ?*anyopaque, version: u32, id: u32) void {
    const object = psyclyx.ColorManagementV1.create(client, version, id) catch {
        client.postNoMemory();
        log.err("out of memory", .{});
        return;
    };
    object.setHandler(?*anyopaque, handleRequest, null, null);
}

fn handleRequest(
    object: *psyclyx.ColorManagementV1,
    request: psyclyx.ColorManagementV1.Request,
    _: ?*anyopaque,
) void {
    switch (request) {
        .destroy => object.destroy(),
        .get_output_color => |args| {
            const color = psyclyx.ColorManagementOutputV1.create(
                object.getClient(),
                object.getVersion(),
                args.id,
            ) catch {
                object.getClient().postNoMemory();
                log.err("out of memory", .{});
                return;
            };

            if (denyReason(args.output)) |reason| {
                log.info("color control denied: {s}", .{reason});
                // Unavailable: inert object + failed event.
                color.setHandler(?*anyopaque, handleOutputInert, null, null);
                color.sendFailed();
                return;
            }

            const output = outputFromResource(args.output).?;
            color.setHandler(*Output, handleOutputRequest, handleOutputDestroy, output);
            output.color_object = color;
        },
    }
}

fn handleOutputRequest(
    color: *psyclyx.ColorManagementOutputV1,
    request: psyclyx.ColorManagementOutputV1.Request,
    output: *Output,
) void {
    std.debug.assert(output.color_object == color);
    switch (request) {
        .destroy => color.destroy(), // triggers handleOutputDestroy
        .set_icc_profile => |args| {
            // The received fd is ours to close once read. Use libc directly; a
            // client fd may be invalid and std.posix asserts on e.g. EBADF.
            defer _ = std.c.close(args.icc_fd);
            const transform = buildTransform(args.icc_fd, args.offset, args.length, output) orelse return;
            output.setColorTransform(transform);
        },
    }
}

fn handleOutputDestroy(_: *psyclyx.ColorManagementOutputV1, output: *Output) void {
    // The controlling object is gone (client destroyed it or disconnected);
    // revert the output to uncorrected.
    output.color_object = null;
    output.setColorTransform(null);
}

fn handleOutputInert(
    color: *psyclyx.ColorManagementOutputV1,
    request: psyclyx.ColorManagementOutputV1.Request,
    _: ?*anyopaque,
) void {
    if (request == .destroy) color.destroy();
}

/// Why color control of `wl_output` cannot be granted, or null if it can.
fn denyReason(wl_output: *wl.Output) ?[]const u8 {
    const output = outputFromResource(wl_output) orelse return "output resource has no Output data";
    if (!server.renderer.features.output_color_transform) return "renderer lacks output_color_transform support";
    if (output.color_object != null) return "output already under color control";
    return null;
}

/// Resolve a client's wl_output to river's Output. The wl_output resource's
/// user data is the wlr_output (set by wlroots in output_bind), and river
/// stores its Output on wlr_output.data. Casting getUserData() straight to
/// *Output is WRONG — that pointer is the wlr_output, and dereferencing it as
/// an Output crashes.
fn outputFromResource(wl_output: *wl.Output) ?*Output {
    const wlr_output = wlr.Output.fromWlOutput(wl_output) orelse return null;
    const data = wlr_output.data orelse return null;
    return @ptrCast(@alignCast(data));
}

/// Read the ICC bytes from the fd and build a color transform. Returns null
/// (logging the reason) on any problem, per the protocol's ignore-on-error rule.
fn buildTransform(fd: i32, offset: u32, length: u32, output: *Output) ?*wlr.ColorTransform {
    if (length == 0 or length > max_icc_bytes) {
        log.err("rejecting ICC profile for output '{s}': invalid length {d}", .{ outputName(output), length });
        return null;
    }

    const data = util.gpa.alloc(u8, length) catch return null;
    defer util.gpa.free(data);

    var read: usize = 0;
    while (read < length) {
        const n = std.c.pread(fd, data.ptr + read, length - read, @as(std.c.off_t, offset) + @as(std.c.off_t, @intCast(read)));
        if (n < 0) {
            log.err("failed to read ICC profile for output '{s}': {s}", .{
                outputName(output),
                @tagName(@as(std.c.E, @enumFromInt(std.c._errno().*))),
            });
            return null;
        }
        if (n == 0) break; // fd shorter than the client claimed
        read += @intCast(n);
    }
    if (read != length) {
        log.err("short read of ICC profile for output '{s}': got {d} of {d} bytes", .{ outputName(output), read, length });
        return null;
    }

    const transform = ColorTransform.fromIccData(data) orelse {
        log.err("invalid ICC profile for output '{s}'", .{outputName(output)});
        return null;
    };
    log.info("applied ICC profile ({d} bytes) to output '{s}'", .{ length, outputName(output) });
    return transform;
}

fn outputName(output: *Output) []const u8 {
    return if (output.wlr_output) |wlr_output| mem.span(wlr_output.name) else "(gone)";
}
