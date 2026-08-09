// SPDX-License-Identifier: GPL-3.0-only
//
// Binding for the KDE server-decoration protocol
// (org_kde_kwin_server_decoration), which zig-wlroots does not wrap.
// Mirrors the zig-wlroots binding style so it can be used like any
// other wlr.* manager. Structs match `wlr/types/wlr_server_decoration.h`.

const wlr = @import("wlroots");

const wayland = @import("wayland");
const wl = wayland.server.wl;

pub const ServerDecorationManager = extern struct {
    /// Mirrors enum wlr_server_decoration_manager_mode /
    /// org_kde_kwin_server_decoration_manager_mode.
    pub const Mode = enum(u32) {
        none = 0,
        client = 1,
        server = 2,
    };

    global: *wl.Global,
    resources: wl.list.Head(wl.Resource, null),
    decorations: wl.list.Head(ServerDecoration, .link),
    default_mode: Mode,

    events: extern struct {
        new_decoration: wl.Signal(*ServerDecoration),
        destroy: wl.Signal(*ServerDecorationManager),
    },

    data: ?*anyopaque,

    private: extern struct {
        display_destroy: wl.Listener(void),
    },

    extern fn wlr_server_decoration_manager_create(server: *wl.Server) ?*ServerDecorationManager;
    pub fn create(server: *wl.Server) !*ServerDecorationManager {
        return wlr_server_decoration_manager_create(server) orelse error.OutOfMemory;
    }

    extern fn wlr_server_decoration_manager_set_default_mode(manager: *ServerDecorationManager, default_mode: Mode) void;
    pub fn setDefaultMode(manager: *ServerDecorationManager, default_mode: Mode) void {
        wlr_server_decoration_manager_set_default_mode(manager, default_mode);
    }
};

pub const ServerDecoration = extern struct {
    resource: *wl.Resource,
    surface: *wlr.Surface,
    link: wl.list.Link,
    mode: ServerDecorationManager.Mode,

    events: extern struct {
        destroy: wl.Signal(*ServerDecoration),
        mode: wl.Signal(*ServerDecoration),
    },

    data: ?*anyopaque,

    private: extern struct {
        surface_destroy_listener: wl.Listener(void),
    },
};
