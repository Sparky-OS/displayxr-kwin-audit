// SPDX-License-Identifier: BSL-1.0
/*
 * solid-window [W H]: a windowed 2D Wayland client (wl_shm, xdg-shell) for the DisplayXR KWin audit kit,
 * adapted from Sparky Stereo OS's vkms-stereo-bench fullscreen-2d.c. A W x H logical
 * window (default 600x360) whose buffer is in DEVICE pixels: it follows wp_fractional_scale_v1's
 * preferred scale and maps the buffer onto W x H with wp_viewporter, so at any output scale the buffer
 * can reach the screen 1:1. CLIENT_COLOR=RRGGBB fills it (default ff0000); CLIENT_PATTERN=columns
 * draws alternate device columns in that colour and in black, so a capture shows any resample as
 * smeared columns. A left-button press on it starts xdg_toplevel.move, the client-initiated drag
 * DisplayXR's test apps use (CLIENT_MOVE_BUTTON=right: a right-button press does); it prints every
 * button event it receives. CLIENT_TITLE, CLIENT_APP_ID, HOLD_SECONDS (0 or unset: until killed).
 * Prints its pid and every buffer it attaches.
 * CLIENT_FIFO=PATH: reads commands from that FIFO and calls the window-geometry service from this
 * process, as a runtime does from its own: "move X Y" and "movepid PID X Y" (MoveWindow), "exclude PID"
 * and "release PID" (CaptureExclusion1), "caps", "lattice" (the methods the capability bits leave
 * out), "table explicit|implicit X Y" (a drag table every 3 logical px within +-150, sent with
 * SetDragLatticeAt for start X,Y or with SetDragLattice), "sync PID" (EnableMoveSync), "newwindow" (maps a second, yellow 300x200 window of this process), "fullscreen" and "unfullscreen", "disconnect" (closes this process's bus connection, the
 * window stays). Each prints one "reply ..." line.
 * CLIENT_GEOMETRY_TOP=N: the window geometry (xdg_surface.set_window_geometry) starts N logical px
 * below the surface's top, as a client with its own shadow or title area above the frame has it, so
 * the main surface sits at an offset inside the frame.
 */
#define _GNU_SOURCE
#include <linux/input-event-codes.h>
#include <math.h>
#include <poll.h>
#include <stdarg.h>
#include <stdbool.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/mman.h>
#include <time.h>
#include <unistd.h>

#include <dbus/dbus.h>
#include <fcntl.h>
#include <wayland-client.h>
#include "fractional-scale-v1-client-protocol.h"
#include "viewporter-client-protocol.h"
#include "xdg-shell-client-protocol.h"

struct state {
	struct wl_compositor *compositor;
	struct wl_shm *shm;
	struct xdg_wm_base *wm_base;
	struct wl_seat *seat;
	struct wl_pointer *pointer;
	struct wp_viewporter *viewporter;
	struct wp_fractional_scale_manager_v1 *fractional;
	struct wl_surface *surface;
	struct xdg_toplevel *toplevel;
	struct wp_viewport *viewport;
	int width, height; /* logical */
	struct xdg_surface *xdg;
	int geometry_top;
	uint32_t scale120;
	bool configured, dirty;
	struct wl_buffer *buffer;
};

static void wm_ping(void *data, struct xdg_wm_base *wm_base, uint32_t serial)
{
	xdg_wm_base_pong(wm_base, serial);
}

static const struct xdg_wm_base_listener wm_listener = { .ping = wm_ping };

static void surface_configure(void *data, struct xdg_surface *surface, uint32_t serial)
{
	struct state *state = data;

	xdg_surface_ack_configure(surface, serial);
	state->configured = true;
	state->dirty = true;
}

static const struct xdg_surface_listener surface_listener = { .configure = surface_configure };

static void toplevel_configure(void *data, struct xdg_toplevel *toplevel, int32_t w, int32_t h,
			       struct wl_array *states)
{
	struct state *state = data;

	if (w > 0 && h > 0) {
		state->width = w;
		state->height = h;
	}
}

static void toplevel_close(void *data, struct xdg_toplevel *toplevel)
{
	exit(0);
}

static const struct xdg_toplevel_listener toplevel_listener = {
	.configure = toplevel_configure,
	.close = toplevel_close,
};

static void preferred_scale(void *data, struct wp_fractional_scale_v1 *object, uint32_t scale)
{
	struct state *state = data;

	if (scale != state->scale120) {
		state->scale120 = scale;
		state->dirty = true;
	}
}

static const struct wp_fractional_scale_v1_listener fractional_listener = { .preferred_scale = preferred_scale };

static void pointer_enter(void *data, struct wl_pointer *p, uint32_t serial, struct wl_surface *s, wl_fixed_t x, wl_fixed_t y) {}
static void pointer_leave(void *data, struct wl_pointer *p, uint32_t serial, struct wl_surface *s) {}
static void pointer_motion(void *data, struct wl_pointer *p, uint32_t time, wl_fixed_t x, wl_fixed_t y) {}
static void pointer_axis(void *data, struct wl_pointer *p, uint32_t time, uint32_t axis, wl_fixed_t value) {}

static void pointer_button(void *data, struct wl_pointer *p, uint32_t serial, uint32_t time, uint32_t button,
			   uint32_t button_state)
{
	struct state *state = data;

	const char *move_button = getenv("CLIENT_MOVE_BUTTON");
	const uint32_t wanted = move_button && !strcmp(move_button, "right") ? BTN_RIGHT : BTN_LEFT;

	printf("button %u %s\n", button, button_state == WL_POINTER_BUTTON_STATE_PRESSED ? "pressed" : "released");
	fflush(stdout);
	if (button == wanted && button_state == WL_POINTER_BUTTON_STATE_PRESSED) {
		xdg_toplevel_move(state->toplevel, state->seat, serial);
		printf("move requested\n");
		fflush(stdout);
	}
}

static const struct wl_pointer_listener pointer_listener = {
	.enter = pointer_enter,
	.leave = pointer_leave,
	.motion = pointer_motion,
	.button = pointer_button,
	.axis = pointer_axis,
};

static void seat_capabilities(void *data, struct wl_seat *seat, uint32_t caps)
{
	struct state *state = data;

	if ((caps & WL_SEAT_CAPABILITY_POINTER) && !state->pointer) {
		state->pointer = wl_seat_get_pointer(seat);
		wl_pointer_add_listener(state->pointer, &pointer_listener, state);
	}
}

static void seat_name(void *data, struct wl_seat *seat, const char *name) {}

static const struct wl_seat_listener seat_listener = { .capabilities = seat_capabilities, .name = seat_name };

static void registry_global(void *data, struct wl_registry *registry, uint32_t name,
			    const char *interface, uint32_t version)
{
	struct state *state = data;

	if (!strcmp(interface, wl_compositor_interface.name))
		state->compositor = wl_registry_bind(registry, name, &wl_compositor_interface, 4);
	else if (!strcmp(interface, wl_shm_interface.name))
		state->shm = wl_registry_bind(registry, name, &wl_shm_interface, 1);
	else if (!strcmp(interface, xdg_wm_base_interface.name))
		state->wm_base = wl_registry_bind(registry, name, &xdg_wm_base_interface, 1);
	else if (!strcmp(interface, wl_seat_interface.name))
		state->seat = wl_registry_bind(registry, name, &wl_seat_interface, 3);
	else if (!strcmp(interface, wp_viewporter_interface.name))
		state->viewporter = wl_registry_bind(registry, name, &wp_viewporter_interface, 1);
	else if (!strcmp(interface, wp_fractional_scale_manager_v1_interface.name))
		state->fractional = wl_registry_bind(registry, name, &wp_fractional_scale_manager_v1_interface, 1);
}

static void registry_remove(void *data, struct wl_registry *registry, uint32_t name)
{
}

static const struct wl_registry_listener registry_listener = {
	.global = registry_global,
	.global_remove = registry_remove,
};

static void draw_color(struct state *state, const char *color);

static void draw(struct state *state)
{
	draw_color(state, getenv("CLIENT_COLOR"));
}

static void draw_color(struct state *state, const char *color)
{
	const char *pattern = getenv("CLIENT_PATTERN");
	const bool columns = pattern && !strcmp(pattern, "columns");
	const uint32_t argb = 0xff000000 | (uint32_t)strtoul(color ? color : "ff0000", NULL, 16);
	const double scale = state->scale120 ? state->scale120 / 120.0 : 1.0;
	const int bw = (int)lround(state->width * scale), bh = (int)lround(state->height * scale);
	const int stride = bw * 4, size = stride * bh;
	int fd = memfd_create("solid", MFD_CLOEXEC);
	uint32_t *pixels;

	if (fd < 0 || ftruncate(fd, size))
		exit(1);
	pixels = mmap(NULL, size, PROT_READ | PROT_WRITE, MAP_SHARED, fd, 0);
	if (pixels == MAP_FAILED)
		exit(1);
	for (int y = 0; y < bh; y++)
		for (int x = 0; x < bw; x++)
			pixels[y * bw + x] = columns && (x & 1) ? 0xff000000 : argb;
	struct wl_shm_pool *pool = wl_shm_create_pool(state->shm, fd, size);
	if (state->buffer)
		wl_buffer_destroy(state->buffer);
	state->buffer = wl_shm_pool_create_buffer(pool, 0, bw, bh, stride, WL_SHM_FORMAT_XRGB8888);
	wl_shm_pool_destroy(pool);
	munmap(pixels, size);
	close(fd);
	wp_viewport_set_destination(state->viewport, state->width, state->height);
	if (state->geometry_top > 0)
		xdg_surface_set_window_geometry(state->xdg, 0, state->geometry_top, state->width, state->height - state->geometry_top);
	wl_surface_attach(state->surface, state->buffer, 0, 0);
	wl_surface_damage_buffer(state->surface, 0, 0, bw, bh);
	wl_surface_commit(state->surface);
	printf("buffer %dx%d logical %dx%d scale %u/120\n", bw, bh, state->width, state->height, state->scale120);
	fflush(stdout);
	state->dirty = false;
}

static DBusMessage *call(DBusConnection *bus, const char *path, const char *iface, const char *method, int first, ...)
{
	DBusMessage *m = dbus_message_new_method_call("org.displayxr.WindowGeometry", path, iface, method);
	DBusError err;
	va_list ap;

	va_start(ap, first);
	dbus_message_append_args_valist(m, first, ap);
	va_end(ap);
	dbus_error_init(&err);
	DBusMessage *r = dbus_connection_send_with_reply_and_block(bus, m, 2000, &err);
	dbus_message_unref(m);
	if (!r) {
		printf("reply error %s %s\n", err.name, err.message);
		dbus_error_free(&err);
	}
	return r;
}

static struct xdg_toplevel *command_toplevel;
static struct state *command_state;

static void second_configure(void *data, struct xdg_surface *surface, uint32_t serial)
{
	struct state *second = data;

	xdg_surface_ack_configure(surface, serial);
	second->configured = true;
	second->dirty = true;
}

static const struct xdg_surface_listener second_surface_listener = { .configure = second_configure };

static const struct xdg_toplevel_listener second_toplevel_listener = {
	.configure = toplevel_configure,
	.close = toplevel_close,
};

/* A second 300x200 yellow window of this process, mapped on request. */
static struct state second;

static void open_second(void)
{
	second = *command_state;
	second.width = 300;
	second.height = 200;
	second.buffer = NULL;
	second.configured = false;
	second.surface = wl_compositor_create_surface(second.compositor);
	second.viewport = wp_viewporter_get_viewport(second.viewporter, second.surface);
	struct xdg_surface *xs = xdg_wm_base_get_xdg_surface(second.wm_base, second.surface);
	second.toplevel = xdg_surface_get_toplevel(xs);
	xdg_surface_add_listener(xs, &second_surface_listener, &second);
	xdg_toplevel_add_listener(second.toplevel, &second_toplevel_listener, &second);
	xdg_toplevel_set_title(second.toplevel, "second");
	wl_surface_commit(second.surface);
}

static void command(DBusConnection *bus, char *line)
{
	const char *placement = "/org/displayxr/WindowPlacement", *pi = "org.displayxr.WindowPlacement1";
	const char *exclusion = "/org/displayxr/CaptureExclusion", *ei = "org.displayxr.CaptureExclusion1";
	DBusMessage *r = NULL;
	dbus_uint32_t pid = 0, u = 0;
	dbus_int32_t x, y, sx = 0, sy = 0;
	dbus_bool_t b = FALSE;
	char mode[16];

	if (sscanf(line, "movepid %u %d %d", &pid, &x, &y) == 3 || (pid = 0, sscanf(line, "move %d %d", &x, &y) == 2)) {
		if ((r = call(bus, placement, pi, "MoveWindow", DBUS_TYPE_UINT32, &pid, DBUS_TYPE_INT32, &x, DBUS_TYPE_INT32, &y, DBUS_TYPE_INVALID))) {
			dbus_message_get_args(r, NULL, DBUS_TYPE_BOOLEAN, &b, DBUS_TYPE_INVALID);
			printf("reply move %s\n", b ? "true" : "false");
		}
	} else if (sscanf(line, "exclude %u", &pid) == 1) {
		if ((r = call(bus, exclusion, ei, "Exclude", DBUS_TYPE_UINT32, &pid, DBUS_TYPE_INVALID))) {
			dbus_message_get_args(r, NULL, DBUS_TYPE_UINT32, &u, DBUS_TYPE_INVALID);
			printf("reply exclude %u\n", u);
		}
	} else if (sscanf(line, "release %u", &pid) == 1) {
		if ((r = call(bus, exclusion, ei, "Release", DBUS_TYPE_UINT32, &pid, DBUS_TYPE_INVALID)))
			printf("reply release\n");
	} else if (!strncmp(line, "fullscreen", 10)) {
		xdg_toplevel_set_fullscreen(command_toplevel, NULL);
		printf("reply fullscreen\n");
	} else if (!strncmp(line, "unfullscreen", 12)) {
		xdg_toplevel_unset_fullscreen(command_toplevel);
		printf("reply unfullscreen\n");
	} else if (sscanf(line, "sync %u", &pid) == 1) {
		if ((r = call(bus, placement, pi, "EnableMoveSync", DBUS_TYPE_UINT32, &pid, DBUS_TYPE_INVALID))) {
			dbus_message_get_args(r, NULL, DBUS_TYPE_BOOLEAN, &b, DBUS_TYPE_INVALID);
			printf("reply sync %u %s\n", pid, b ? "true" : "false");
		}
	} else if (sscanf(line, "table %15s %d %d", mode, &x, &y) == 3) {
		/* A synthetic drag table: every 3 logical px in both axes within +-150, built for start x,y. */
		static dbus_int32_t dx[101 * 101], dy[101 * 101];
		const dbus_int32_t *pdx = dx, *pdy = dy;
		const dbus_int32_t cell = 3, lo = -150, hi = 150;
		int n = 0;
		for (int j = -150; j <= 150; j += 3)
			for (int i = -150; i <= 150; i += 3) {
				dx[n] = i;
				dy[n] = j;
				n++;
			}
		if (!strcmp(mode, "explicit"))
			r = call(bus, placement, pi, "SetDragLatticeAt", DBUS_TYPE_UINT32, &pid, DBUS_TYPE_INT32, &x, DBUS_TYPE_INT32, &y,
				 DBUS_TYPE_BOOLEAN, &b, DBUS_TYPE_INT32, &cell, DBUS_TYPE_INT32, &lo, DBUS_TYPE_INT32, &lo, DBUS_TYPE_INT32, &hi,
				 DBUS_TYPE_INT32, &hi, DBUS_TYPE_ARRAY, DBUS_TYPE_INT32, &pdx, n, DBUS_TYPE_ARRAY, DBUS_TYPE_INT32, &pdy, n,
				 DBUS_TYPE_INVALID);
		else
			r = call(bus, placement, pi, "SetDragLattice", DBUS_TYPE_UINT32, &pid, DBUS_TYPE_BOOLEAN, &b, DBUS_TYPE_INT32, &cell,
				 DBUS_TYPE_INT32, &lo, DBUS_TYPE_INT32, &lo, DBUS_TYPE_INT32, &hi, DBUS_TYPE_INT32, &hi, DBUS_TYPE_ARRAY,
				 DBUS_TYPE_INT32, &pdx, n, DBUS_TYPE_ARRAY, DBUS_TYPE_INT32, &pdy, n, DBUS_TYPE_INVALID);
		if (r) {
			dbus_message_get_args(r, NULL, DBUS_TYPE_BOOLEAN, &b, DBUS_TYPE_INT32, &sx, DBUS_TYPE_INT32, &sy, DBUS_TYPE_INVALID);
			printf("reply table %s %s start %d %d\n", mode, b ? "true" : "false", sx, sy);
		}
	} else if (!strncmp(line, "newwindow", 9)) {
		open_second();
		printf("reply newwindow\n");
	} else if (!strncmp(line, "disconnect", 10)) {
		dbus_connection_close(bus);
		printf("reply disconnect\n");
	} else if (!strncmp(line, "caps", 4)) {
		if ((r = call(bus, placement, pi, "GetPlacementCapabilities", DBUS_TYPE_INVALID))) {
			dbus_message_get_args(r, NULL, DBUS_TYPE_UINT32, &u, DBUS_TYPE_INVALID);
			printf("reply caps %u\n", u);
		}
	} else if (!strncmp(line, "lattice", 7)) {
		const dbus_int32_t one = 1, zero = 0, *none = NULL;
		const dbus_uint32_t button = 1;
		if ((r = call(bus, placement, pi, "SetDragLattice", DBUS_TYPE_UINT32, &pid, DBUS_TYPE_BOOLEAN, &b, DBUS_TYPE_INT32, &one,
			      DBUS_TYPE_INT32, &zero, DBUS_TYPE_INT32, &zero, DBUS_TYPE_INT32, &zero, DBUS_TYPE_INT32, &zero,
			      DBUS_TYPE_ARRAY, DBUS_TYPE_INT32, &none, 0, DBUS_TYPE_ARRAY, DBUS_TYPE_INT32, &none, 0, DBUS_TYPE_INVALID))) {
			dbus_message_get_args(r, NULL, DBUS_TYPE_BOOLEAN, &b, DBUS_TYPE_INT32, &sx, DBUS_TYPE_INT32, &sy, DBUS_TYPE_INVALID);
			printf("reply SetDragLattice %s %d %d\n", b ? "true" : "false", sx, sy);
			dbus_message_unref(r);
		}
		if ((r = call(bus, placement, pi, "SetDragLatticeAt", DBUS_TYPE_UINT32, &pid, DBUS_TYPE_INT32, &zero, DBUS_TYPE_INT32, &zero,
			      DBUS_TYPE_BOOLEAN, &b, DBUS_TYPE_INT32, &one, DBUS_TYPE_INT32, &zero, DBUS_TYPE_INT32, &zero, DBUS_TYPE_INT32, &zero,
			      DBUS_TYPE_INT32, &zero, DBUS_TYPE_ARRAY, DBUS_TYPE_INT32, &none, 0, DBUS_TYPE_ARRAY, DBUS_TYPE_INT32, &none, 0,
			      DBUS_TYPE_INVALID))) {
			dbus_message_get_args(r, NULL, DBUS_TYPE_BOOLEAN, &b, DBUS_TYPE_INT32, &sx, DBUS_TYPE_INT32, &sy, DBUS_TYPE_INVALID);
			printf("reply SetDragLatticeAt %s %d %d\n", b ? "true" : "false", sx, sy);
			dbus_message_unref(r);
		}
		if ((r = call(bus, placement, pi, "EnableMoveSync", DBUS_TYPE_UINT32, &pid, DBUS_TYPE_INVALID))) {
			dbus_message_get_args(r, NULL, DBUS_TYPE_BOOLEAN, &b, DBUS_TYPE_INVALID);
			printf("reply EnableMoveSync %s\n", b ? "true" : "false");
			dbus_message_unref(r);
		}
		if ((r = call(bus, placement, pi, "BeginPointerDrag", DBUS_TYPE_UINT32, &pid, DBUS_TYPE_UINT32, &button, DBUS_TYPE_INVALID))) {
			dbus_message_get_args(r, NULL, DBUS_TYPE_BOOLEAN, &b, DBUS_TYPE_INVALID);
			printf("reply BeginPointerDrag %s\n", b ? "true" : "false");
			dbus_message_unref(r);
		}
		if ((r = call(bus, placement, pi, "ClearDragLattice", DBUS_TYPE_UINT32, &pid, DBUS_TYPE_INVALID))) {
			printf("reply ClearDragLattice\n");
			dbus_message_unref(r);
		}
		r = call(bus, placement, pi, "EndPointerDrag", DBUS_TYPE_UINT32, &pid, DBUS_TYPE_INVALID);
		if (r)
			printf("reply EndPointerDrag\n");
	}
	if (r)
		dbus_message_unref(r);
	fflush(stdout);
}

int main(int argc, char **argv)
{
	struct state state = { .width = argc > 2 ? atoi(argv[1]) : 600, .height = argc > 2 ? atoi(argv[2]) : 360 };
	struct wl_display *display = wl_display_connect(NULL);
	const char *hold = getenv("HOLD_SECONDS");
	const char *title = getenv("CLIENT_TITLE");
	const char *app_id = getenv("CLIENT_APP_ID");
	const time_t end = hold && atoi(hold) > 0 ? time(NULL) + atoi(hold) : 0;

	if (!display)
		return 1;
	wl_registry_add_listener(wl_display_get_registry(display), &registry_listener, &state);
	wl_display_roundtrip(display);
	if (!state.compositor || !state.shm || !state.wm_base || !state.viewporter || !state.fractional)
		return 1;
	xdg_wm_base_add_listener(state.wm_base, &wm_listener, &state);
	if (state.seat)
		wl_seat_add_listener(state.seat, &seat_listener, &state);

	state.surface = wl_compositor_create_surface(state.compositor);
	state.viewport = wp_viewporter_get_viewport(state.viewporter, state.surface);
	struct wp_fractional_scale_v1 *fs = wp_fractional_scale_manager_v1_get_fractional_scale(state.fractional, state.surface);
	wp_fractional_scale_v1_add_listener(fs, &fractional_listener, &state);
	struct xdg_surface *xdg_surface = xdg_wm_base_get_xdg_surface(state.wm_base, state.surface);
	state.toplevel = xdg_surface_get_toplevel(xdg_surface);
	state.xdg = xdg_surface;
	state.geometry_top = getenv("CLIENT_GEOMETRY_TOP") ? atoi(getenv("CLIENT_GEOMETRY_TOP")) : 0;
	command_toplevel = state.toplevel;
	command_state = &state;

	xdg_surface_add_listener(xdg_surface, &surface_listener, &state);
	xdg_toplevel_add_listener(state.toplevel, &toplevel_listener, &state);
	xdg_toplevel_set_title(state.toplevel, title ? title : "solid window");
	xdg_toplevel_set_app_id(state.toplevel, app_id ? app_id : "dxr-rig-solid");
	wl_surface_commit(state.surface);
	while (!state.configured)
		if (wl_display_dispatch(display) < 0)
			return 1;
	printf("pid %d\n", getpid());
	fflush(stdout);

	const char *fifo = getenv("CLIENT_FIFO");
	DBusConnection *bus = fifo ? dbus_bus_get_private(DBUS_BUS_SESSION, NULL) : NULL;
	struct pollfd pfd[2] = { { .fd = wl_display_get_fd(display), .events = POLLIN },
				 { .fd = fifo ? open(fifo, O_RDWR | O_NONBLOCK) : -1, .events = POLLIN } };
	char cmd[256];
	size_t used = 0;
	for (;;) {
		if (state.dirty)
			draw(&state);
		if (second.surface && second.dirty && second.configured)
			draw_color(&second, "ffff00");
		wl_display_flush(display);
		if (poll(pfd, 2, 100) > 0 && (pfd[0].revents & POLLIN) && wl_display_dispatch(display) < 0)
			return 1;
		wl_display_dispatch_pending(display);
		if (bus && (pfd[1].revents & POLLIN)) {
			ssize_t got = read(pfd[1].fd, cmd + used, sizeof(cmd) - 1 - used);
			char *nl;
			used += got > 0 ? got : 0;
			cmd[used] = 0;
			while ((nl = strchr(cmd, '\n'))) {
				*nl = 0;
				command(bus, cmd);
				memmove(cmd, nl + 1, used - (nl + 1 - cmd) + 1);
				used -= nl + 1 - cmd;
			}
		}
		if (end && time(NULL) >= end)
			return 0;
	}
}
