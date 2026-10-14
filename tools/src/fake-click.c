// SPDX-License-Identifier: BSL-1.0
// fake-click move X Y | click X Y | follow: moves the pointer of KWin to X,Y (logical px, in KWin's global
// layout), and presses and releases the left button there; KWin's fake input protocol
// (org_kde_kwin_fake_input, plasma-wayland-protocols), which KWin offers to any client when it runs with
// KWIN_WAYLAND_NO_PERMISSION_CHECKS=1. Built by tools/build.sh.
// follow reads "X Y" lines on stdin and moves the pointer to each, in one session: the pointer device
// stays, so a GTK client gets an enter and then motion events (a device that comes and goes with every
// move, as move makes it, gives a GTK client enters only). follow also takes fractional positions,
// "down"/"up" for the left button, "key CODE down|up" (Linux input codes), "rdown"/"rup" for the right
// button, and "sleep MS", so one session can hold a modifier and drag; it answers "done LINE" after each.
// From Sparky Stereo OS's stereo-vm test rig, extended for the DisplayXR work.
#include <linux/input-event-codes.h>
#include <wayland-client.h>

#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>

#include "fake-input-client-protocol.h"

static struct org_kde_kwin_fake_input *fake_input;

static void registry_global(void *data, struct wl_registry *registry, uint32_t name,
                            const char *interface, uint32_t version)
{
    (void)data;
    if (strcmp(interface, "org_kde_kwin_fake_input") == 0 && version >= 3)
        fake_input = wl_registry_bind(registry, name, &org_kde_kwin_fake_input_interface,
                                      version > 6 ? 6 : version);
}

static void registry_global_remove(void *data, struct wl_registry *registry, uint32_t name)
{
    (void)data; (void)registry; (void)name;
}

static const struct wl_registry_listener registry_listener = { registry_global, registry_global_remove };

int main(int argc, char **argv)
{
    int follow = argc == 2 && !strcmp(argv[1], "follow");
    if (!follow && (argc != 4 || (strcmp(argv[1], "move") && strcmp(argv[1], "click")))) {
        fprintf(stderr, "usage: fake-click move|click X Y | follow\n");
        return 2;
    }
    struct wl_display *display = wl_display_connect(NULL);
    if (!display) {
        perror("wl_display_connect");
        return 1;
    }
    struct wl_registry *registry = wl_display_get_registry(display);
    wl_registry_add_listener(registry, &registry_listener, NULL);
    if (wl_display_roundtrip(display) < 0 || !fake_input) {
        fprintf(stderr, "fake input global unavailable\n");
        return 1;
    }
    org_kde_kwin_fake_input_authenticate(fake_input, "stereo-vm-test", "pointer for the test rig");
    if (follow) {
        char line[128], state[8];
        double x, y;
        int code, ms;

        while (fgets(line, sizeof(line), stdin)) {
            if (!strncmp(line, "down", 4) || !strncmp(line, "up", 2)) {
                org_kde_kwin_fake_input_button(fake_input, BTN_LEFT, line[0] == 'd' ? WL_POINTER_BUTTON_STATE_PRESSED : WL_POINTER_BUTTON_STATE_RELEASED);
            } else if (!strncmp(line, "rdown", 5) || !strncmp(line, "rup", 3)) {
                org_kde_kwin_fake_input_button(fake_input, BTN_RIGHT, line[1] == 'd' ? WL_POINTER_BUTTON_STATE_PRESSED : WL_POINTER_BUTTON_STATE_RELEASED);
            } else if (sscanf(line, "key %d %7s", &code, state) == 2) {
                org_kde_kwin_fake_input_keyboard_key(fake_input, code, !strcmp(state, "down") ? WL_KEYBOARD_KEY_STATE_PRESSED : WL_KEYBOARD_KEY_STATE_RELEASED);
            } else if (sscanf(line, "sleep %d", &ms) == 1) {
                usleep(ms * 1000);
            } else if (sscanf(line, "%lf %lf", &x, &y) == 2) {
                org_kde_kwin_fake_input_pointer_motion_absolute(fake_input, wl_fixed_from_double(x), wl_fixed_from_double(y));
            } else {
                continue;
            }
            wl_display_roundtrip(display);
            printf("done %s", line);
            fflush(stdout);
        }
        org_kde_kwin_fake_input_destroy(fake_input);
        wl_display_disconnect(display);
        return 0;
    }
    org_kde_kwin_fake_input_pointer_motion_absolute(fake_input, wl_fixed_from_int(atoi(argv[2])),
                                                    wl_fixed_from_int(atoi(argv[3])));
    wl_display_roundtrip(display);
    if (!strcmp(argv[1], "click")) {
        usleep(300000);
        org_kde_kwin_fake_input_button(fake_input, BTN_LEFT, WL_POINTER_BUTTON_STATE_PRESSED);
        wl_display_roundtrip(display);
        usleep(100000);
        org_kde_kwin_fake_input_button(fake_input, BTN_LEFT, WL_POINTER_BUTTON_STATE_RELEASED);
    }
    wl_display_roundtrip(display);
    org_kde_kwin_fake_input_destroy(fake_input);
    wl_display_disconnect(display);
    return 0;
}
