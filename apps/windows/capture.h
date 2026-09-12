#pragma once
#include <windows.h>
#include <vector>
#include <string>
#include <cstdint>
struct Image {int width=0,height=0;std::vector<uint8_t> bgra;};
struct Desktop {RECT bounds{};Image image;double captureMs=0;};
Desktop captureDesktop();
Image cropImage(const Image&,RECT);
void copyImage(HWND,const Image&);
void saveImage(const Image&,const std::wstring&,bool overwrite);
std::vector<uint8_t> encodePNG(const Image&);
