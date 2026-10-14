// SPDX-License-Identifier: BSL-1.0
/*
 * consumer-convert PID < snapshot.json: converts one window of a WindowGeometry1 snapshot to DEVICE
 * pixels exactly as DisplayXR's consumer without buffer_device does (displayxr-runtime comp_vk_native_wl_geom.c,
 * wlg_parse_snapshot and comp_vk_native_wl_geom_get_window_rect): frame/buffer numbers truncated to
 * int32, the monitor read as integers, the factor from u_wl_stage_to_device_scale(), the buffer
 * preferred to the frame (u_wl_window_content_rect), then u_wl_window_rect_px_on_monitor(). It builds
 * against the runtime's own header-only conversion (u_wayland_geom.h, u_wayland_layout.h) and its
 * bundled cJSON, so the test converts with the consumer's code, not a copy of its rule.
 * Prints "device X Y W H factor F layout logical|physical|unknown monitor_px W H" or "none".
 */
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#include "cjson/cJSON.h"
#include "util/u_wayland_geom.h"
#include "util/u_wayland_layout.h"

static int get_int(const cJSON *o, const char *k, int *out)
{
	const cJSON *v = cJSON_GetObjectItemCaseSensitive(o, k);
	if (!cJSON_IsNumber(v))
		return 0;
	*out = v->valueint;
	return 1;
}

int main(int argc, char **argv)
{
	static char buf[1 << 20];
	size_t n = fread(buf, 1, sizeof(buf) - 1, stdin);
	buf[n] = 0;
	const int pid = argc > 1 ? atoi(argv[1]) : 0;
	cJSON *root = cJSON_Parse(buf);
	if (!root)
		return 2;
	enum u_wl_layout_mode layout = U_WL_LAYOUT_MODE_UNKNOWN;
	const cJSON *lm = cJSON_GetObjectItemCaseSensitive(root, "layout_mode");
	if (cJSON_IsString(lm))
		layout = u_wl_layout_mode_from_string(lm->valuestring);
	const cJSON *win = NULL;
	cJSON_ArrayForEach(win, cJSON_GetObjectItemCaseSensitive(root, "windows"))
	{
		int p = 0;
		if (!get_int(win, "pid", &p) || p != pid)
			continue;
		const cJSON *frame = cJSON_GetObjectItemCaseSensitive(win, "frame");
		const cJSON *buffer = cJSON_GetObjectItemCaseSensitive(win, "buffer");
		const cJSON *mon = cJSON_GetObjectItemCaseSensitive(win, "monitor");
		struct u_wl_rect_logical f = {(int32_t)cJSON_GetArrayItem(frame, 0)->valuedouble,
		                              (int32_t)cJSON_GetArrayItem(frame, 1)->valuedouble,
		                              (int32_t)cJSON_GetArrayItem(frame, 2)->valuedouble,
		                              (int32_t)cJSON_GetArrayItem(frame, 3)->valuedouble};
		struct u_wl_rect_logical b = {0, 0, 0, 0};
		if (cJSON_IsArray(buffer) && cJSON_GetArraySize(buffer) == 4) {
			b.logical_x = (int32_t)cJSON_GetArrayItem(buffer, 0)->valuedouble;
			b.logical_y = (int32_t)cJSON_GetArrayItem(buffer, 1)->valuedouble;
			b.logical_w = (int32_t)cJSON_GetArrayItem(buffer, 2)->valuedouble;
			b.logical_h = (int32_t)cJSON_GetArrayItem(buffer, 3)->valuedouble;
		}
		int mx = 0, my = 0, mw = 0, mh = 0;
		if (!cJSON_IsObject(mon) || !get_int(mon, "x", &mx) || !get_int(mon, "y", &my) || !get_int(mon, "w", &mw) ||
		    !get_int(mon, "h", &mh)) {
			printf("none\n");
			return 1;
		}
		const cJSON *sc = cJSON_GetObjectItemCaseSensitive(mon, "scale");
		const cJSON *ds = cJSON_GetObjectItemCaseSensitive(mon, "device_scale");
		const float mon_scale = cJSON_IsNumber(sc) && sc->valuedouble > 0 ? (float)sc->valuedouble : 1.0f;
		const float mon_device_scale = cJSON_IsNumber(ds) && ds->valuedouble > 0 ? (float)ds->valuedouble : 0.0f;
		const double factor = u_wl_stage_to_device_scale((double)mon_scale, (double)mon_device_scale, layout);
		const struct u_wl_monitor m = {mx, my, mw, mh, factor, 0, 0};
		struct u_wl_rect_logical content = f;
		u_wl_window_content_rect(&f, b.logical_w > 0 && b.logical_h > 0 ? &b : NULL, &content);
		struct u_wl_rect_px px = {0, 0, 0, 0};
		int32_t mon_w = 0, mon_h = 0;
		u_wl_window_rect_px_on_monitor(&m, content.logical_x, content.logical_y, content.logical_w, content.logical_h, &px);
		u_wl_monitor_size_px(&m, &mon_w, &mon_h);
		printf("device %d %d %d %d factor %.6f layout %s monitor_px %d %d\n", px.x, px.y, px.w, px.h, factor,
		       layout == U_WL_LAYOUT_MODE_LOGICAL ? "logical" : layout == U_WL_LAYOUT_MODE_PHYSICAL ? "physical" : "unknown",
		       mon_w, mon_h);
		return 0;
	}
	printf("none\n");
	return 1;
}
