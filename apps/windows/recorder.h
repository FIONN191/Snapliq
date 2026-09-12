#pragma once
#include <windows.h>
#include <atomic>
#include <functional>
#include <string>
#include <thread>
struct RecordingOptions {HMONITOR monitor=nullptr;HWND window=nullptr;bool systemAudio=false,microphone=false;std::wstring path;};
struct RecordingOutcome {bool saved=false;std::wstring message;long long frames=0,droppedAudio=0;};
class DesktopRecorder {
 std::thread worker_;
 std::atomic<bool> stop_{false},paused_{false},active_{false},started_{false};
 std::atomic<long long> elapsed_{0};
public:
 ~DesktopRecorder(){stop();join();}
 bool active()const{return active_;}
 bool started()const{return started_;}
 bool stopping()const{return stop_;}
 bool paused()const{return paused_;}
 double seconds()const{return double(elapsed_.load())/10000000.0;}
 void pause(){if(started_&&!stop_)paused_=!paused_.load();}
 void stop(){stop_=true;}
 void join(){if(worker_.joinable())worker_.join();}
 void start(RecordingOptions,std::function<void(RecordingOutcome)>);
};
