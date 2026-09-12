#pragma once
#include <windows.h>
#include <functional>
#include <thread>
#include <atomic>
class NativeBridge {
 std::thread worker_;std::atomic<bool> stopped_{false};
public:
 ~NativeBridge(){stop();}
 void start(std::function<void(int)>);
 void stop();
 static int runHost(const wchar_t* origin);
 static void registerHost();
};
