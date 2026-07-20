// SPDX-FileCopyrightText: © 2026 The River Developers
// SPDX-License-Identifier: GPL-3.0-only

//! Thin binding over wlroots color transforms built from ICC profiles.
//!
//! zig-wlroots models wlr_color_transform as an opaque type with no
//! constructors, so the C entry points are declared directly here. river links
//! libwlroots (built with lcms2) via pkg-config, so these resolve at link time.

const wlr = @import("wlroots");

extern fn wlr_color_transform_init_linear_to_icc(data: *const anyopaque, size: usize) ?*wlr.ColorTransform;
extern fn wlr_color_transform_unref(tr: *wlr.ColorTransform) void;

/// Build an output color transform from raw ICC profile bytes (an SDR display
/// profile), or null if the data is empty or not a usable ICC profile. Owned by
/// the caller (initial refcount 1, release with unref()).
pub fn fromIccData(data: []const u8) ?*wlr.ColorTransform {
    if (data.len == 0) return null;
    return wlr_color_transform_init_linear_to_icc(data.ptr, data.len);
}

/// Release a transform obtained from fromIccData().
pub const unref = wlr_color_transform_unref;
