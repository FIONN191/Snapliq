#pragma once
#include <windows.h>

// Cursor capture and WDA_EXCLUDEFROMCAPTURE both require Windows 10 2004.
inline bool supportedWindowsHost() {
    using RtlGetVersionFn = LONG (WINAPI*)(OSVERSIONINFOW*);
    auto module = GetModuleHandleW(L"ntdll.dll");
    auto query = reinterpret_cast<RtlGetVersionFn>(GetProcAddress(module, "RtlGetVersion"));
    OSVERSIONINFOW version{};
    version.dwOSVersionInfoSize = sizeof(version);
    if (!query || query(&version) != 0) return false;
    return version.dwMajorVersion > 10 ||
           (version.dwMajorVersion == 10 && version.dwBuildNumber >= 19041);
}
