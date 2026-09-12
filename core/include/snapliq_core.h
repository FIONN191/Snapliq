#pragma once
#ifdef __cplusplus
extern "C" {
#endif
typedef struct { double x,y,width,height; } SLRect;
typedef struct { double x,y; } SLPoint;
SLRect sl_normalize(SLPoint a, SLPoint b);
SLRect sl_intersect(SLRect a, SLRect b);
SLRect sl_clamp(SLRect rect, SLRect bounds);
SLRect sl_resize(SLRect original, SLPoint delta, int handle, double minimum);
SLRect sl_toolbar(SLRect selection, SLRect visible, double width, double height, double gap);
SLRect sl_pixels(SLRect selection, SLRect display, double pixelWidth, double pixelHeight);
int sl_contains(SLRect rect, SLPoint point);
int sl_handle(SLRect rect, SLPoint point, double radius);
#ifdef __cplusplus
}
#endif
