#pragma once
#include "capture.h"
#include <vector>
struct WindowTarget {HWND window;RECT bounds;std::wstring label;};
std::vector<WindowTarget> desktopWindows();
RECT controlCandidate(HWND,POINT);
std::wstring recognizeText(const Image&);
