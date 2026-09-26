#pragma once
#include <windows.h>
#include <shlobj.h>
#include <winrt/base.h>
#include <filesystem>
#include <cwchar>
#include <string>

namespace recording_preferences {
inline constexpr const wchar_t* registryPath=L"Software\\Snapliq\\Development";
inline constexpr const wchar_t* systemAudioKey=L"recordSystemAudio";
inline constexpr const wchar_t* microphoneKey=L"recordMicrophone";

// Missing values mean a fresh installation; explicitly disabled inputs stay disabled.
inline bool enabled(const wchar_t* name){
 DWORD value=1,bytes=sizeof(value);
 return RegGetValue(HKEY_CURRENT_USER,registryPath,name,RRF_RT_REG_DWORD,nullptr,&value,&bytes)==ERROR_SUCCESS?value!=0:true;
}
inline void setEnabled(const wchar_t* name,bool enabled){
 HKEY key=nullptr;auto status=RegCreateKeyEx(HKEY_CURRENT_USER,registryPath,0,nullptr,0,KEY_SET_VALUE,nullptr,&key,nullptr);
 if(status!=ERROR_SUCCESS)winrt::throw_hresult(HRESULT_FROM_WIN32(status));
 DWORD value=enabled?1:0;
 status=RegSetValueEx(key,name,0,REG_DWORD,reinterpret_cast<const BYTE*>(&value),sizeof(value));RegCloseKey(key);
 if(status!=ERROR_SUCCESS)winrt::throw_hresult(HRESULT_FROM_WIN32(status));
}
inline std::wstring automaticPath(const std::wstring& configuredFolder){
 std::filesystem::path folder;
 if(configuredFolder.empty()){
  PWSTR knownFolder=nullptr;winrt::check_hresult(SHGetKnownFolderPath(FOLDERID_Videos,KF_FLAG_CREATE,nullptr,&knownFolder));
  folder=knownFolder;CoTaskMemFree(knownFolder);folder/=L"Snapliq";
  std::filesystem::create_directories(folder);
 }else{
  folder=configuredFolder;
  if(!std::filesystem::is_directory(folder))throw winrt::hresult_error(HRESULT_FROM_WIN32(ERROR_PATH_NOT_FOUND),L"默认保存文件夹不可用，请在 Snapliq 设置中重新选择。");
 }
 SYSTEMTIME now;GetLocalTime(&now);wchar_t timestamp[32];
 swprintf_s(timestamp,L"%04u-%02u-%02u_%02u-%02u-%02u",now.wYear,now.wMonth,now.wDay,now.wHour,now.wMinute,now.wSecond);
 GUID guid;winrt::check_hresult(CoCreateGuid(&guid));wchar_t identifier[40];StringFromGUID2(guid,identifier,40);
 // A full GUID avoids collisions between quick sessions. Finalization never overwrites.
 return (folder/(L"Snapliq-"+std::wstring(timestamp)+L"-"+std::wstring(identifier+1,36)+L".mp4")).wstring();
}
}
