#include "native-bridge.h"
#include "product.h"
#include <winrt/base.h>
#include <winrt/Windows.Foundation.Collections.h>
#include <winrt/Windows.Data.Json.h>
#include <sddl.h>
#include <shlobj.h>
#include <shellapi.h>
#include <io.h>
#include <fcntl.h>
#include <vector>
#include <algorithm>
#include <string>
#include <fstream>
#include <filesystem>
using namespace winrt;
using namespace winrt::Windows::Data::Json;
namespace {
std::wstring sid(){
 HANDLE token;if(!OpenProcessToken(GetCurrentProcess(),TOKEN_QUERY,&token))throw hresult_error(HRESULT_FROM_WIN32(GetLastError()));
 DWORD size=0;GetTokenInformation(token,TokenUser,nullptr,0,&size);std::vector<BYTE> data(size);BOOL ok=GetTokenInformation(token,TokenUser,data.data(),size,&size);CloseHandle(token);if(!ok)throw hresult_error(HRESULT_FROM_WIN32(GetLastError()));
 LPWSTR text;check_bool(ConvertSidToStringSid(reinterpret_cast<TOKEN_USER*>(data.data())->User.Sid,&text));std::wstring value=text;LocalFree(text);return value;
}
std::wstring pipeName(){return L"\\\\.\\pipe\\Snapliq.Development."+sid();}
bool transfer(HANDLE handle,void* data,DWORD count,bool writing){
 DWORD total=0;const auto deadline=GetTickCount64()+2000;
 while(total<count){DWORD available=0;
 if(!writing&&GetFileType(handle)==FILE_TYPE_PIPE){
  while(true){if(!PeekNamedPipe(handle,nullptr,0,nullptr,&available,nullptr))return false;if(available)break;if(GetTickCount64()>=deadline)return false;Sleep(5);}
 }
 DWORD actual=0;BOOL ok=writing?WriteFile(handle,static_cast<BYTE*>(data)+total,count-total,&actual,nullptr):ReadFile(handle,static_cast<BYTE*>(data)+total,available?std::min(count-total,available):count-total,&actual,nullptr);if(!ok||!actual)return false;total+=actual;}return true;
}
bool readFrame(HANDLE h,std::string& text){DWORD count=0;if(!transfer(h,&count,4,false)||!count||count>65536)return false;text.resize(count);return transfer(h,text.data(),count,false);}
void sendFrame(HANDLE h,const std::string& text){DWORD count=DWORD(text.size());if(count>65536)return;if(transfer(h,&count,4,true))transfer(h,const_cast<char*>(text.data()),count,true);}
int parse(const std::string& text){
 JsonObject obj;if(!JsonObject::TryParse(to_hstring(text),obj))return -1;auto action=obj.GetNamedString(L"action",L"");
 if(action==L"ping")return 0;if(action==L"capture")return 100;if(action==L"record")return 117;if(action==L"settings")return 103;return -1;
}
const std::string invalid="{\"ok\":false,\"error\":\"invalid_request\"}";
}
void NativeBridge::start(std::function<void(int)> action){
 stopped_=false;auto name=pipeName();auto user=sid();
 worker_=std::thread([this,name,user,action]{
  init_apartment(apartment_type::multi_threaded);
  PSECURITY_DESCRIPTOR descriptor=nullptr;auto sddl=L"D:P(A;;GA;;;"+user+L")";
  if(!ConvertStringSecurityDescriptorToSecurityDescriptor(sddl.c_str(),SDDL_REVISION_1,&descriptor,nullptr)){uninit_apartment();return;}
  SECURITY_ATTRIBUTES security{sizeof(security),descriptor,FALSE};
  while(!stopped_){
   HANDLE pipe=CreateNamedPipe(name.c_str(),PIPE_ACCESS_DUPLEX,PIPE_TYPE_BYTE|PIPE_READMODE_BYTE|PIPE_WAIT|PIPE_REJECT_REMOTE_CLIENTS,1,65540,65540,2000,&security);
   if(pipe==INVALID_HANDLE_VALUE)break;
   if(ConnectNamedPipe(pipe,nullptr)||GetLastError()==ERROR_PIPE_CONNECTED){
    if(!stopped_){
     std::string data;
     // Local same-user pipe only; one frame is consumed per connection.
     if(readFrame(pipe,data)){
      int command=-1;try{command=parse(data);}catch(...){}
      if(command<0)sendFrame(pipe,invalid);
      else{sendFrame(pipe,"{\"ok\":true,\"accepted\":"+std::string(command?"true":"false")+",\"capabilities\":[\"capture\",\"record\",\"settings\"]}");if(command)action(command);}
     }
    }
   }
   DisconnectNamedPipe(pipe);CloseHandle(pipe);
  }
  LocalFree(descriptor);uninit_apartment();
 });
}
void NativeBridge::stop(){
 if(!worker_.joinable())return;stopped_=true;
 CancelSynchronousIo(worker_.native_handle());
 auto wake=CreateFile(pipeName().c_str(),GENERIC_READ|GENERIC_WRITE,0,nullptr,OPEN_EXISTING,0,nullptr);if(wake!=INVALID_HANDLE_VALUE)CloseHandle(wake);
 worker_.join();
}
int NativeBridge::runHost(const wchar_t* origin){
 if(std::wstring(origin)!=L"chrome-extension://"+std::wstring(CHROME_EXTENSION_ID)+L"/")return 2;
 _setmode(_fileno(stdin),_O_BINARY);_setmode(_fileno(stdout),_O_BINARY);
 init_apartment(apartment_type::multi_threaded);std::string data;auto in=GetStdHandle(STD_INPUT_HANDLE),out=GetStdHandle(STD_OUTPUT_HANDLE);
 auto stdioRead=[&](void* bytes,DWORD count){DWORD total=0;while(total<count){DWORD got=0;if(!ReadFile(in,static_cast<BYTE*>(bytes)+total,count-total,&got,nullptr)||!got)return false;total+=got;}return true;};
 while(true){DWORD size=0;if(!stdioRead(&size,4)||!size||size>65536)break;data.resize(size);if(!stdioRead(data.data(),size))break;
  int command=-1;try{command=parse(data);}catch(...){}
  if(command<0){sendFrame(out,invalid);continue;}
  auto name=pipeName();auto connect=[&]{return CreateFile(name.c_str(),GENERIC_READ|GENERIC_WRITE,0,nullptr,OPEN_EXISTING,0,nullptr);};
  auto pipe=connect();
  if(pipe==INVALID_HANDLE_VALUE&&command){
   wchar_t exe[32768];GetModuleFileName(nullptr,exe,32768);ShellExecute(nullptr,L"open",exe,nullptr,nullptr,SW_SHOWNORMAL);
   for(int i=0;i<50&&pipe==INVALID_HANDLE_VALUE;i++){Sleep(100);pipe=connect();}
  }
  if(pipe==INVALID_HANDLE_VALUE){sendFrame(out,"{\"ok\":false,\"error\":\"desktop_not_running\"}");continue;}
  sendFrame(pipe,data);std::string reply;if(readFrame(pipe,reply))sendFrame(out,reply);else sendFrame(out,"{\"ok\":false,\"error\":\"desktop_timeout\"}");CloseHandle(pipe);
 }
 uninit_apartment();return 0;
}
void NativeBridge::registerHost(){
 PWSTR local;check_hresult(SHGetKnownFolderPath(FOLDERID_LocalAppData,0,nullptr,&local));auto folder=std::filesystem::path(local)/L"Snapliq Development"/L"NativeMessagingHosts";CoTaskMemFree(local);std::filesystem::create_directories(folder);
 wchar_t exe[32768];GetModuleFileName(nullptr,exe,32768);
 JsonObject manifest;manifest.SetNamedValue(L"name",JsonValue::CreateStringValue(L"com.snapliq.desktop.development"));manifest.SetNamedValue(L"description",JsonValue::CreateStringValue(L"Snapliq desktop request adapter"));manifest.SetNamedValue(L"path",JsonValue::CreateStringValue(exe));manifest.SetNamedValue(L"type",JsonValue::CreateStringValue(L"stdio"));
 JsonArray origins;origins.Append(JsonValue::CreateStringValue(L"chrome-extension://"+std::wstring(CHROME_EXTENSION_ID)+L"/"));manifest.SetNamedValue(L"allowed_origins",origins);
 auto path=folder/L"com.snapliq.desktop.development.json";std::ofstream stream(path,std::ios::binary|std::ios::trunc);stream<<to_string(manifest.Stringify());stream.close();if(!stream)throw std::runtime_error("Could not write Chrome bridge manifest.");
 HKEY key;auto created=RegCreateKeyEx(HKEY_CURRENT_USER,L"Software\\Google\\Chrome\\NativeMessagingHosts\\com.snapliq.desktop.development",0,nullptr,0,KEY_SET_VALUE,nullptr,&key,nullptr);if(created!=ERROR_SUCCESS)throw hresult_error(HRESULT_FROM_WIN32(created));auto value=path.wstring();auto result=RegSetValueEx(key,nullptr,0,REG_SZ,reinterpret_cast<const BYTE*>(value.c_str()),DWORD((value.size()+1)*2));RegCloseKey(key);if(result!=ERROR_SUCCESS)throw hresult_error(HRESULT_FROM_WIN32(result));
}
