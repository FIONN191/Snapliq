#pragma once
#include <windows.h>
#include "recorder.h"
#include "desktop-services.h"
#include <vector>
class RecordingWindow {
 HWND picker_=nullptr,source_=nullptr,system_=nullptr,microphone_=nullptr,controls_=nullptr,label_=nullptr,pause_=nullptr;
 std::vector<RecordingOptions> choices_;
 DesktopRecorder& recorder_;
 HWND owner_;
 std::function<void(RecordingOptions)> start_;
 static LRESULT CALLBACK proc(HWND,UINT,WPARAM,LPARAM);
 void begin();
public:
 RecordingWindow(DesktopRecorder& recorder,HWND owner,std::function<void(RecordingOptions)> start):recorder_(recorder),owner_(owner),start_(std::move(start)){}
 void present();
 void update();
 void close();
};
