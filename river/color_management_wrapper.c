// SPDX-FileCopyrightText: © 2025 The River Developers
// SPDX-License-Identifier: GPL-3.0-only

// This C wrapper is needed because wlr_color_manager_v1_create takes a struct
// containing enum types from the generated color-management-v1 protocol header,
// which is not installed by wlroots and must be generated at build time.

#define WLR_USE_UNSTABLE

#include <wayland-server.h>
#include <wlr/types/wlr_color_management_v1.h>

struct wlr_color_manager_v1 *river_create_color_manager(struct wl_display *display) {
	static const enum wp_color_manager_v1_render_intent render_intents[] = {
		WP_COLOR_MANAGER_V1_RENDER_INTENT_PERCEPTUAL,
		WP_COLOR_MANAGER_V1_RENDER_INTENT_RELATIVE,
		WP_COLOR_MANAGER_V1_RENDER_INTENT_ABSOLUTE,
	};
	static const enum wp_color_manager_v1_transfer_function transfer_functions[] = {
		WP_COLOR_MANAGER_V1_TRANSFER_FUNCTION_SRGB,
	};
	static const enum wp_color_manager_v1_primaries primaries[] = {
		WP_COLOR_MANAGER_V1_PRIMARIES_SRGB,
	};
	const struct wlr_color_manager_v1_options options = {
		.features = {
			.icc_v2_v4 = false, // not yet implemented in wlroots
		},
		.render_intents = render_intents,
		.render_intents_len = sizeof(render_intents) / sizeof(render_intents[0]),
		.transfer_functions = transfer_functions,
		.transfer_functions_len = sizeof(transfer_functions) / sizeof(transfer_functions[0]),
		.primaries = primaries,
		.primaries_len = sizeof(primaries) / sizeof(primaries[0]),
	};
	return wlr_color_manager_v1_create(display, 1, &options);
}

struct wl_global *river_color_manager_get_global(struct wlr_color_manager_v1 *manager) {
	return manager->global;
}
