// SPDX-License-Identifier: BSL-1.0
/*
 * screencast-node [OUTPUT]: asks KWin for a screen cast of one output (zkde_screencast_unstable_v1
 * stream_output, cursor hidden; OUTPUT by its wl_output name, else the first output) and prints "node N",
 * the PipeWire node a reader takes the frames from. Keeps the stream open until killed. For the DisplayXR
 * KWin audit kit's move-sync audit, which reads every frame KWin sends.
 */
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#include <wayland-client.h>
#include "screencast-client-protocol.h"

#define MAX_OUTPUTS 16

static struct zkde_screencast_unstable_v1 *screencast;
static struct wl_output *outputs[MAX_OUTPUTS];
static char *names[MAX_OUTPUTS];
static int count;

static void output_geometry(void *data, struct wl_output *o, int32_t x, int32_t y, int32_t pw, int32_t ph, int32_t sp,
			    const char *make, const char *model, int32_t transform)
{
}

static void output_mode(void *data, struct wl_output *o, uint32_t flags, int32_t w, int32_t h, int32_t refresh)
{
}

static void output_done(void *data, struct wl_output *o)
{
}

static void output_scale(void *data, struct wl_output *o, int32_t factor)
{
}

static void output_name(void *data, struct wl_output *o, const char *name)
{
	names[(int)(intptr_t)data] = strdup(name);
}

static void output_description(void *data, struct wl_output *o, const char *description)
{
}

static const struct wl_output_listener output_listener = {
	.geometry = output_geometry,
	.mode = output_mode,
	.done = output_done,
	.scale = output_scale,
	.name = output_name,
	.description = output_description,
};

static void registry_global(void *data, struct wl_registry *registry, uint32_t name, const char *interface, uint32_t version)
{
	if (!strcmp(interface, zkde_screencast_unstable_v1_interface.name)) {
		screencast = wl_registry_bind(registry, name, &zkde_screencast_unstable_v1_interface, version < 5 ? version : 5);
	} else if (!strcmp(interface, wl_output_interface.name) && count < MAX_OUTPUTS) {
		outputs[count] = wl_registry_bind(registry, name, &wl_output_interface, version < 4 ? version : 4);
		wl_output_add_listener(outputs[count], &output_listener, (void *)(intptr_t)count);
		count++;
	}
}

static void registry_remove(void *data, struct wl_registry *registry, uint32_t name)
{
}

static const struct wl_registry_listener registry_listener = { registry_global, registry_remove };

static void stream_closed(void *data, struct zkde_screencast_stream_unstable_v1 *stream)
{
	printf("closed\n");
	exit(1);
}

static void stream_created(void *data, struct zkde_screencast_stream_unstable_v1 *stream, uint32_t node)
{
	printf("node %u\n", node);
	fflush(stdout);
}

static void stream_failed(void *data, struct zkde_screencast_stream_unstable_v1 *stream, const char *error)
{
	printf("failed %s\n", error);
	exit(1);
}

static const struct zkde_screencast_stream_unstable_v1_listener stream_listener = {
	.closed = stream_closed,
	.created = stream_created,
	.failed = stream_failed,
};

int main(int argc, char **argv)
{
	struct wl_display *display = wl_display_connect(NULL);
	const char *want = argc > 1 ? argv[1] : NULL;
	struct wl_output *output = NULL;

	if (!display)
		return 1;
	wl_registry_add_listener(wl_display_get_registry(display), &registry_listener, NULL);
	wl_display_roundtrip(display);
	wl_display_roundtrip(display); /* the outputs' names */
	if (!screencast || !count) {
		fprintf(stderr, "no zkde_screencast_unstable_v1 or wl_output\n");
		return 1;
	}
	for (int i = 0; i < count; i++)
		if (!want || (names[i] && !strcmp(names[i], want)))
			if (!output)
				output = outputs[i];
	if (!output) {
		fprintf(stderr, "no output named %s\n", want);
		return 1;
	}
	struct zkde_screencast_stream_unstable_v1 *stream =
		zkde_screencast_unstable_v1_stream_output(screencast, output, ZKDE_SCREENCAST_UNSTABLE_V1_POINTER_HIDDEN);
	zkde_screencast_stream_unstable_v1_add_listener(stream, &stream_listener, NULL);
	while (wl_display_dispatch(display) >= 0)
		;
	return 0;
}
