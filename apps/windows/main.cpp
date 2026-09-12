#include <windows.h>
#include <windowsx.h>
#include <commctrl.h>
#include <shellapi.h>
#include <shobjidl.h>
#include <dwmapi.h>
#include <winrt/base.h>
#include "product.h"
#include "dpi.h"
#include "capture.h"
#include "desktop-services.h"
#include "recording-window.h"
#include "native-bridge.h"
#include "snapliq_core.h"
#include <algorithm>
#include <thread>
#include <memory>
#include <filesystem>
#include <fstream>
#include <chrono>
#include <sstream>
#include <cmath>
constexpr UINT TRAY=WM_APP+1,CAPTURED=WM_APP+2,OCR_DONE=WM_APP+3,HIT_DONE=WM_APP+4,RECORD_DONE=WM_APP+5;
constexpr int REGION=100,SCREEN=101,RESTORE=102,SETTINGS=103,QUIT=104,TODAY=105,HIDE=106,COPY=107,SAVE=108,SAVEAS=109,APPLYKEY=110,FOLDER=111,STARTUP=112,WINDOW=113,OCR=114,SMART=115,CONTROLS=116,RECORD=117,PAUSE_RECORD=118,STOP_RECORD=119,CONNECT_CHROME=120;
const wchar_t* PREFS=L"Software\\Snapliq\\Development";
DWORD readInt(const wchar_t* name,DWORD fallback){DWORD value=0,bytes=sizeof(value);return RegGetValue(HKEY_CURRENT_USER,PREFS,name,RRF_RT_REG_DWORD,nullptr,&value,&bytes)==ERROR_SUCCESS?value:fallback;}
void writeInt(const wchar_t* name,DWORD value){HKEY key;if(RegCreateKeyEx(HKEY_CURRENT_USER,PREFS,0,nullptr,0,KEY_SET_VALUE,nullptr,&key,nullptr)==ERROR_SUCCESS){RegSetValueEx(key,name,0,REG_DWORD,reinterpret_cast<BYTE*>(&value),sizeof(value));RegCloseKey(key);}}
std::wstring readString(const wchar_t* name){wchar_t value[32768]{};DWORD bytes=sizeof(value);if(RegGetValue(HKEY_CURRENT_USER,PREFS,name,RRF_RT_REG_SZ,nullptr,value,&bytes)!=ERROR_SUCCESS)return {};return value;}
void writeString(const wchar_t* name,const std::wstring& value){HKEY key;if(RegCreateKeyEx(HKEY_CURRENT_USER,PREFS,0,nullptr,0,KEY_SET_VALUE,nullptr,&key,nullptr)==ERROR_SUCCESS){RegSetValueEx(key,name,0,REG_SZ,reinterpret_cast<const BYTE*>(value.c_str()),static_cast<DWORD>((value.size()+1)*sizeof(wchar_t)));RegCloseKey(key);}}
DWORD dateKey(){SYSTEMTIME t;GetLocalTime(&t);return DWORD(t.wYear)*10000+t.wMonth*100+t.wDay;}
RECT asRect(SLRect r){return {LONG(std::floor(r.x)),LONG(std::floor(r.y)),LONG(std::ceil(r.x+r.width)),LONG(std::ceil(r.y+r.height))};}
struct HitResult{RECT rect;POINT point;unsigned generation;};
struct OCRResult{unsigned generation=0;std::wstring text,error;};
struct Result{unsigned generation=0;std::unique_ptr<Desktop> desktop;std::wstring error;};
struct App {
 HWND host=nullptr,orb=nullptr,overlay=nullptr,settings=nullptr,hotkeyControl=nullptr;
 std::vector<WindowTarget> targets;SLRect candidate{};bool candidateValid=false,windowMode=false,hitBusy=false,quitAfterRecord=false;
 ULONGLONG lastHit=0;std::thread hitWorker,ocrWorker;HWND ocrWindow=nullptr,ocrEdit=nullptr;
 NativeBridge bridge;unsigned ocrGeneration=0;
 DesktopRecorder recorder;std::unique_ptr<RecordingWindow> recordingWindow;
 unsigned generation=0;NOTIFYICONDATA tray{};std::thread worker;bool busy=false,full=false,selected=false,dragging=false,moving=false,orbDragging=false;int handle=-1;
 DWORD vk=readInt(L"key",'X'),mods=readInt(L"modifiers",MOD_CONTROL|MOD_ALT);
 std::unique_ptr<Desktop> desktop;Image dim;SLRect selection{},original{};POINT start{},orbStart{};RECT orbOrigin{};RECT bar{},modeBar{};
 std::wstring folder=readString(L"folder");
 void error(const std::wstring& text){if(overlay)ShowWindow(overlay,SW_HIDE);MessageBox(settings?settings:host,text.c_str(),PRODUCT_NAME,MB_OK|MB_ICONWARNING);if(overlay){ShowWindow(overlay,SW_SHOW);SetForegroundWindow(overlay);}}
 void report(const std::wstring& message){tray.uFlags=NIF_INFO;wcscpy_s(tray.szInfoTitle,PRODUCT_NAME);wcsncpy_s(tray.szInfo,message.c_str(),_TRUNCATE);tray.dwInfoFlags=NIIF_INFO;Shell_NotifyIcon(NIM_MODIFY,&tray);}
 void refreshTrayIcon(){DWORD light=0,bytes=sizeof(light);RegGetValue(HKEY_CURRENT_USER,L"Software\\Microsoft\\Windows\\CurrentVersion\\Themes\\Personalize",L"SystemUsesLightTheme",RRF_RT_REG_DWORD,nullptr,&light,&bytes);tray.hIcon=LoadIcon(GetModuleHandle(nullptr),MAKEINTRESOURCE(light?2:3));tray.uFlags=NIF_ICON;Shell_NotifyIcon(NIM_MODIFY,&tray);}
 void registerKey(){UnregisterHotKey(host,1);if(!RegisterHotKey(host,1,mods|MOD_NOREPEAT,vk))error(L"Global shortcut registration failed. Choose another combination in Settings.");}
 void refreshOrb(){ShowWindow(orb,((!recorder.active()||SetWindowDisplayAffinity(orb,WDA_EXCLUDEFROMCAPTURE))&&!busy&&!overlay&&!readInt(L"orbHidden",0)&&readInt(L"orbDate",0)!=dateKey())?SW_SHOWNOACTIVATE:SW_HIDE);}
 void placeOrb(bool saved=true){
  MONITORINFO info{sizeof(info)};POINT p{LONG(readInt(L"orbX",200)),LONG(readInt(L"orbY",200))};
  GetMonitorInfo(MonitorFromPoint(p,MONITOR_DEFAULTTOPRIMARY),&info);auto r=info.rcWork;int size=MulDiv(48,int(monitorDpi(MonitorFromPoint(p,MONITOR_DEFAULTTOPRIMARY))),96);
  int x=saved?std::clamp<int>(p.x,r.left+8,r.right-size-8):r.right-size-12;
  int y=saved?std::clamp<int>(p.y,r.top+8,r.bottom-size-8):r.bottom-size-120;
  SetWindowPos(orb,HWND_TOPMOST,x,y,size,size,SWP_NOACTIVATE);SetWindowRgn(orb,CreateEllipticRgn(0,0,size,size),TRUE);
 }
 void dockOrb(){
  MONITORINFO info{sizeof(info)};GetMonitorInfo(MonitorFromWindow(orb,MONITOR_DEFAULTTONEAREST),&info);RECT r;GetWindowRect(orb,&r);
  const int size=r.right-r.left;
  int x=(r.left+r.right)/2<(info.rcWork.left+info.rcWork.right)/2?info.rcWork.left+8:info.rcWork.right-size-8;
  int y=std::clamp<int>(r.top,info.rcWork.top+8,info.rcWork.bottom-size-8);SetWindowPos(orb,HWND_TOPMOST,x,y,size,size,SWP_NOACTIVATE);
  writeInt(L"orbX",DWORD(x));writeInt(L"orbY",DWORD(y));
 }
 void popup(bool orbMenu){
  HMENU menu=CreatePopupMenu();
  if(orbMenu){AppendMenu(menu,MF_STRING,TODAY,L"仅今天停用");AppendMenu(menu,MF_STRING,HIDE,L"停用");}
  else{AppendMenu(menu,MF_STRING,REGION,L"区域截图");AppendMenu(menu,MF_STRING,SCREEN,L"当前屏幕截图");AppendMenu(menu,MF_STRING,WINDOW,L"窗口截图");AppendMenu(menu,MF_STRING,RESTORE,L"显示悬浮球");}
  if(!orbMenu){AppendMenu(menu,MF_STRING,RECORD,recorder.active()?L"显示录屏控制条":L"屏幕录制…");if(recorder.active()){AppendMenu(menu,MF_STRING,PAUSE_RECORD,recorder.paused()?L"继续录屏":L"暂停录屏");AppendMenu(menu,MF_STRING,STOP_RECORD,L"停止并保存录屏");}}
  AppendMenu(menu,MF_SEPARATOR,0,nullptr);AppendMenu(menu,MF_STRING,SETTINGS,L"设置");
  if(!orbMenu){AppendMenu(menu,MF_SEPARATOR,0,nullptr);AppendMenu(menu,MF_STRING,QUIT,L"退出 Snapliq");}
  POINT point;GetCursorPos(&point);SetForegroundWindow(host);int action=TrackPopupMenu(menu,TPM_RETURNCMD|TPM_RIGHTBUTTON,point.x,point.y,0,host,nullptr);
  DestroyMenu(menu);PostMessage(host,WM_NULL,0,0);if(action)command(action);
 }
 void capture(bool screen,bool window=false){
  if(busy||overlay)return;busy=true;full=screen;windowMode=window;targets=desktopWindows();candidateValid=false;if(settings)ShowWindow(settings,SW_HIDE);refreshOrb();
  if(worker.joinable())worker.join();
  // Owned windows are hidden and display-affinity excluded. WGC does not depend on Chrome.
  DwmFlush();
  const auto requestedGeneration=++generation;
  worker=std::thread([this,requestedGeneration]{
   auto result=new Result;result->generation=requestedGeneration;
   try{result->desktop=std::make_unique<Desktop>(captureDesktop());}
   catch(const winrt::hresult_error& e){result->error=e.message().c_str();}
   catch(const std::exception& e){std::string m=e.what();result->error.assign(m.begin(),m.end());}
   if(!PostMessage(host,CAPTURED,0,reinterpret_cast<LPARAM>(result)))delete result;
  });
 }
 void showCapture(Result* raw){
  std::unique_ptr<Result> result(raw);busy=false;
  if(result->generation!=generation){refreshOrb();return;}
  if(!result->error.empty()){refreshOrb();error(result->error);return;}
  desktop=std::move(result->desktop);dim=desktop->image;
  for(size_t i=0;i<dim.bgra.size();i+=4){dim.bgra[i]=uint8_t(dim.bgra[i]*0.55);dim.bgra[i+1]=uint8_t(dim.bgra[i+1]*0.55);dim.bgra[i+2]=uint8_t(dim.bgra[i+2]*0.55);}
  selected=false;selection={};candidateValid=false;
  if(full){POINT p;GetCursorPos(&p);MONITORINFO info{sizeof(info)};GetMonitorInfo(MonitorFromPoint(p,MONITOR_DEFAULTTOPRIMARY),&info);
   selection={double(info.rcMonitor.left-desktop->bounds.left),double(info.rcMonitor.top-desktop->bounds.top),double(info.rcMonitor.right-info.rcMonitor.left),double(info.rcMonitor.bottom-info.rcMonitor.top)};selected=true;}
  overlay=CreateWindowEx(WS_EX_TOPMOST|WS_EX_TOOLWINDOW,L"SnapliqOverlay",PRODUCT_NAME,WS_POPUP,desktop->bounds.left,desktop->bounds.top,desktop->image.width,desktop->image.height,host,nullptr,GetModuleHandle(nullptr),nullptr);
  SetWindowDisplayAffinity(overlay,WDA_EXCLUDEFROMCAPTURE);ShowWindow(overlay,SW_SHOW);SetForegroundWindow(overlay);SetFocus(overlay);refreshOrb();
 }
 void closeCapture(){
  ++generation;
  if(overlay){auto w=overlay;overlay=nullptr;DestroyWindow(w);}desktop.reset();dim={};selected=false;refreshOrb();
 }
 Image current(){if(!selected||!desktop)throw std::runtime_error("Select a region first.");return cropImage(desktop->image,asRect(selection));}
 std::wstring choosePath(bool directory){
  if(overlay)ShowWindow(overlay,SW_HIDE);
  std::wstring result;
  try{
   if(directory){
    auto dialog=winrt::create_instance<IFileOpenDialog>(CLSID_FileOpenDialog);DWORD flags;dialog->GetOptions(&flags);dialog->SetOptions(flags|FOS_PICKFOLDERS|FOS_FORCEFILESYSTEM);
    if(SUCCEEDED(dialog->Show(settings?settings:host))){winrt::com_ptr<IShellItem> item;dialog->GetResult(item.put());PWSTR path;item->GetDisplayName(SIGDN_FILESYSPATH,&path);result=path;CoTaskMemFree(path);}
   }else{
    auto dialog=winrt::create_instance<IFileSaveDialog>(CLSID_FileSaveDialog);COMDLG_FILTERSPEC filter{L"PNG image",L"*.png"};dialog->SetFileTypes(1,&filter);dialog->SetDefaultExtension(L"png");dialog->SetFileName(L"Snapliq.png");
    if(!folder.empty()){winrt::com_ptr<IShellItem> dir;if(SUCCEEDED(SHCreateItemFromParsingName(folder.c_str(),nullptr,IID_PPV_ARGS(dir.put()))))dialog->SetFolder(dir.get());}
    if(SUCCEEDED(dialog->Show(host))){winrt::com_ptr<IShellItem> item;dialog->GetResult(item.put());PWSTR path;item->GetDisplayName(SIGDN_FILESYSPATH,&path);result=path;CoTaskMemFree(path);}
   }
  }catch(const winrt::hresult_error& e){error(e.message().c_str());}
  if(overlay){ShowWindow(overlay,SW_SHOW);SetForegroundWindow(overlay);}return result;
 }
 void save(bool saveAs){
  if(!selected)return;
  try{
   if(saveAs){auto path=choosePath(false);if(path.empty())return;saveImage(current(),path,true);}
   else{
    if(folder.empty()){folder=choosePath(true);if(folder.empty())return;writeString(L"folder",folder);}
    SYSTEMTIME t;GetLocalTime(&t);wchar_t stem[100];swprintf_s(stem,L"Snapliq_%04d-%02d-%02d_%02d-%02d-%02d",t.wYear,t.wMonth,t.wDay,t.wHour,t.wMinute,t.wSecond);
    auto image=current();bool saved=false;
    for(int i=0;i<10000;i++){
     auto path=(std::filesystem::path(folder)/(std::wstring(stem)+(i?L"_"+std::to_wstring(i):L"")+L".png")).wstring();
     try{saveImage(image,path,false);saved=true;break;}catch(const winrt::hresult_error& e){if(e.code()!=HRESULT_FROM_WIN32(ERROR_FILE_EXISTS)&&e.code()!=HRESULT_FROM_WIN32(ERROR_ALREADY_EXISTS))throw;}
    }
    if(!saved)throw std::runtime_error("Too many files with the same name.");
   }
   closeCapture();report(L"已保存图片");
  }catch(const winrt::hresult_error& e){error(e.message().c_str());}catch(const std::exception& e){std::string m=e.what();error(std::wstring(m.begin(),m.end()));}
 }
 void copied(){
  if(!selected)return;
  try{copyImage(host,current());closeCapture();report(L"已复制图片");}
  catch(const winrt::hresult_error& e){error(e.message().c_str());}catch(const std::exception& e){std::string m=e.what();error(std::wstring(m.begin(),m.end()));}
 }
 void drawImage(HDC dc,const Image& image){
  BITMAPINFO info{};info.bmiHeader.biSize=sizeof(BITMAPINFOHEADER);info.bmiHeader.biWidth=image.width;info.bmiHeader.biHeight=-image.height;info.bmiHeader.biPlanes=1;info.bmiHeader.biBitCount=32;info.bmiHeader.biCompression=BI_RGB;
  SetDIBitsToDevice(dc,0,0,image.width,image.height,0,0,0,image.height,image.bgra.data(),&info,DIB_RGB_COLORS);
 }
 void paint(HDC dc){
  if(!desktop)return;drawImage(dc,dim);
  POINT location;GetCursorPos(&location);if(selected)location={LONG(desktop->bounds.left+selection.x+selection.width/2),LONG(desktop->bounds.top+selection.y+selection.height/2)};
  auto dpi=monitorDpi(MonitorFromPoint(location,MONITOR_DEFAULTTONEAREST));auto d=[dpi](int value){return MulDiv(value,int(dpi),96);};
  auto font=CreateFont(-d(13),0,0,0,FW_NORMAL,FALSE,FALSE,FALSE,DEFAULT_CHARSET,OUT_DEFAULT_PRECIS,CLIP_DEFAULT_PRECIS,DEFAULT_QUALITY,DEFAULT_PITCH,L"Segoe UI");auto previousFont=SelectObject(dc,font);
  SetBkMode(dc,TRANSPARENT);SetTextColor(dc,RGB(255,255,255));
  if(!selected&&candidateValid){auto r=asRect(candidate);auto pen=CreatePen(PS_SOLID,2,RGB(255,255,255));auto old=SelectObject(dc,pen);auto brush=SelectObject(dc,GetStockObject(NULL_BRUSH));Rectangle(dc,r.left,r.top,r.right,r.bottom);SelectObject(dc,brush);SelectObject(dc,old);DeleteObject(pen);}
  if(selected){
   auto r=asRect(selection);SaveDC(dc);IntersectClipRect(dc,r.left,r.top,r.right,r.bottom);drawImage(dc,desktop->image);RestoreDC(dc,-1);
   auto pen=CreatePen(PS_SOLID,1,RGB(255,255,255));auto old=SelectObject(dc,pen);auto brush=SelectObject(dc,GetStockObject(NULL_BRUSH));Rectangle(dc,r.left,r.top,r.right,r.bottom);
   for(auto p:std::vector<POINT>{{r.left,r.top},{(r.left+r.right)/2,r.top},{r.right,r.top},{r.right,(r.top+r.bottom)/2},{r.right,r.bottom},{(r.left+r.right)/2,r.bottom},{r.left,r.bottom},{r.left,(r.top+r.bottom)/2}})Ellipse(dc,p.x-d(4),p.y-d(4),p.x+d(4),p.y+d(4));
   SelectObject(dc,brush);SelectObject(dc,old);DeleteObject(pen);
   POINT mid{desktop->bounds.left+(r.left+r.right)/2,desktop->bounds.top+(r.top+r.bottom)/2};MONITORINFO info{sizeof(info)};GetMonitorInfo(MonitorFromPoint(mid,MONITOR_DEFAULTTONEAREST),&info);
   SLRect screen{double(info.rcWork.left-desktop->bounds.left+8),double(desktop->image.height-(info.rcWork.bottom-desktop->bounds.top)+8),double(info.rcWork.right-info.rcWork.left-16),double(info.rcWork.bottom-info.rcWork.top-16)};
   auto placed=sl_toolbar({selection.x,desktop->image.height-selection.y-selection.height,selection.width,selection.height},screen,d(540),d(42),d(12));
   bar=asRect({placed.x,desktop->image.height-placed.y-placed.height,placed.width,placed.height});FillRect(dc,&bar,static_cast<HBRUSH>(GetStockObject(BLACK_BRUSH)));
   const wchar_t* labels[]={L"提取文字",L"复制",L"下载 ▾",L"取消",L"完成 ↵"};
   for(int i=0;i<5;i++){RECT box{bar.left+i*(bar.right-bar.left)/5,bar.top,bar.left+(i+1)*(bar.right-bar.left)/5,bar.bottom};DrawText(dc,labels[i],-1,&box,DT_CENTER|DT_VCENTER|DT_SINGLELINE);}
   auto text=std::to_wstring(r.right-r.left)+L" × "+std::to_wstring(r.bottom-r.top)+L" px";
   RECT label{r.left,std::max(0L,r.top-28),r.left+190,std::max(0L,r.top-28)+26};FillRect(dc,&label,static_cast<HBRUSH>(GetStockObject(BLACK_BRUSH)));DrawText(dc,text.c_str(),-1,&label,DT_CENTER|DT_VCENTER|DT_SINGLELINE);
  }
  POINT cursor;GetCursorPos(&cursor);MONITORINFO info{sizeof(info)};GetMonitorInfo(MonitorFromPoint(cursor,MONITOR_DEFAULTTOPRIMARY),&info);
  int center=(info.rcWork.left+info.rcWork.right)/2-desktop->bounds.left;
  modeBar={center-d(160),info.rcWork.top-desktop->bounds.top+d(12),center+d(160),info.rcWork.top-desktop->bounds.top+d(52)};
  FillRect(dc,&modeBar,static_cast<HBRUSH>(GetStockObject(BLACK_BRUSH)));RECT left=modeBar,right=modeBar;left.right=(modeBar.left+modeBar.right)/2;right.left=left.right;
  DrawText(dc,L"截图",-1,&left,DT_CENTER|DT_VCENTER|DT_SINGLELINE);DrawText(dc,L"屏幕录制",-1,&right,DT_CENTER|DT_VCENTER|DT_SINGLELINE);
  SelectObject(dc,previousFont);DeleteObject(font);
 }
 void down(POINT p){
  if(PtInRect(&modeBar,p)){if(p.x>(modeBar.left+modeBar.right)/2){closeCapture();command(RECORD);}return;}
  if(selected&&PtInRect(&bar,p)){
   int action=(p.x-bar.left)*5/std::max(1L,bar.right-bar.left);
   if(action==0)extract();else if(action==1||action==4)copied();else if(action==3)closeCapture();else{
    HMENU m=CreatePopupMenu();AppendMenu(m,MF_STRING,SAVE,L"保存");AppendMenu(m,MF_STRING,SAVEAS,L"另存为");AppendMenu(m,MF_STRING,FOLDER,L"默认保存位置设置");
    POINT global=p;ClientToScreen(overlay,&global);int cmd=TrackPopupMenu(m,TPM_RETURNCMD,global.x,global.y,0,overlay,nullptr);DestroyMenu(m);if(cmd)command(cmd);
   };return;
  }
  start=p;original=selection;handle=selected?sl_handle(selection,{double(p.x),double(p.y)},9):-1;
  moving=selected&&handle<0&&sl_contains(selection,{double(p.x),double(p.y)});dragging=true;SetCapture(overlay);
  if(!moving&&handle<0){selected=false;selection={};}
 }
 void move(POINT p){
  if(!desktop)return;
  if(!dragging){hover(p);return;}
  SLPoint delta{double(p.x-start.x),double(p.y-start.y)};
  if(std::hypot(delta.x,delta.y)<3&&!selected)return;
  if(handle>=0)selection=sl_resize(original,delta,handle,1);
  else if(moving)selection={original.x+delta.x,original.y+delta.y,original.width,original.height};
  else selection=sl_normalize({double(start.x),double(start.y)},{double(p.x),double(p.y)});
  selection=sl_clamp(selection,{0,0,double(desktop->image.width),double(desktop->image.height)});selected=selection.width>=1&&selection.height>=1;InvalidateRect(overlay,nullptr,FALSE);
 }
 void hover(POINT p){
  if(selected||(!windowMode&&!readInt(L"smart",0)))return;
  POINT point{p.x+desktop->bounds.left,p.y+desktop->bounds.top};auto target=std::find_if(targets.begin(),targets.end(),[&](const WindowTarget& t){return PtInRect(&t.bounds,point);});
  candidateValid=target!=targets.end();if(!candidateValid){InvalidateRect(overlay,nullptr,FALSE);return;}
  candidate={double(target->bounds.left-desktop->bounds.left),double(target->bounds.top-desktop->bounds.top),double(target->bounds.right-target->bounds.left),double(target->bounds.bottom-target->bounds.top)};
  InvalidateRect(overlay,nullptr,FALSE);
  if(!readInt(L"controls",0)||hitBusy||GetTickCount64()-lastHit<100)return;
  hitBusy=true;lastHit=GetTickCount64();if(hitWorker.joinable())hitWorker.join();auto window=target->window;auto token=generation;
  hitWorker=std::thread([this,window,point,token]{winrt::init_apartment(winrt::apartment_type::multi_threaded);auto result=new HitResult{{},point,token};try{result->rect=controlCandidate(window,point);}catch(...){}if(!PostMessage(host,HIT_DONE,0,reinterpret_cast<LPARAM>(result)))delete result;winrt::uninit_apartment();});
 }
 void extract(){
  if(!selected||ocrWindow)return;
  auto image=current();ShowWindow(overlay,SW_HIDE);
  ocrWindow=CreateWindowEx(WS_EX_TOOLWINDOW,L"SnapliqOCR",L"提取文字 · Snapliq",WS_OVERLAPPEDWINDOW,CW_USEDEFAULT,CW_USEDEFAULT,620,430,host,nullptr,GetModuleHandle(nullptr),nullptr);
  ocrEdit=CreateWindowEx(WS_EX_CLIENTEDGE,L"EDIT",L"正在本地识别中文和英文…",WS_CHILD|WS_VISIBLE|WS_VSCROLL|ES_MULTILINE|ES_AUTOVSCROLL,15,15,570,300,ocrWindow,nullptr,GetModuleHandle(nullptr),nullptr);
  CreateWindow(L"BUTTON",L"Copy text",WS_CHILD|WS_VISIBLE|WS_TABSTOP,15,330,160,30,ocrWindow,reinterpret_cast<HMENU>(1),GetModuleHandle(nullptr),nullptr);
  const auto token=++ocrGeneration;
  SendMessage(ocrEdit,EM_SETLIMITTEXT,1000000,0);applyWindowDpi(ocrWindow);ShowWindow(ocrWindow,SW_SHOW);SetForegroundWindow(ocrWindow);
  if(ocrWorker.joinable())ocrWorker.join();
  ocrWorker=std::thread([this,token,image=std::move(image)]{winrt::init_apartment(winrt::apartment_type::multi_threaded);auto result=new OCRResult;result->generation=token;try{result->text=recognizeText(image);}catch(const winrt::hresult_error& e){result->error=e.message().c_str();}catch(const std::exception& e){std::string t=e.what();result->error.assign(t.begin(),t.end());}if(!PostMessage(host,OCR_DONE,0,reinterpret_cast<LPARAM>(result)))delete result;winrt::uninit_apartment();});
 }
 void startRecording(RecordingOptions options){
  try{
   if(settings)ShowWindow(settings,SW_HIDE);closeCapture();
   recorder.start(options,[this](RecordingOutcome result){auto value=new RecordingOutcome(std::move(result));if(!PostMessage(host,RECORD_DONE,0,reinterpret_cast<LPARAM>(value)))delete value;});
   SetTimer(host,2,250,nullptr);refreshOrb();
  }catch(const std::exception& e){std::string t=e.what();error(std::wstring(t.begin(),t.end()));}
 }
 void showSettings();
 void command(int action){
  switch(action){
   case REGION:capture(false);break;case SCREEN:capture(true);break;case WINDOW:capture(false,true);break;
   case OCR:extract();break;
   case CONNECT_CHROME:try{NativeBridge::registerHost();report(L"Chrome connection registered for this application.");}catch(const winrt::hresult_error& e){error(e.message().c_str());}catch(const std::exception& e){std::string t=e.what();error(std::wstring(t.begin(),t.end()));}break;
   case SMART:writeInt(L"smart",IsDlgButtonChecked(settings,SMART)==BST_CHECKED);break;
   case CONTROLS:writeInt(L"controls",IsDlgButtonChecked(settings,CONTROLS)==BST_CHECKED);break;
   case RECORD:if(!recordingWindow)recordingWindow=std::make_unique<RecordingWindow>(recorder,host,[this](RecordingOptions o){startRecording(o);});recordingWindow->present();break;
   case PAUSE_RECORD:recorder.pause();if(recordingWindow)recordingWindow->update();break;
   case STOP_RECORD:recorder.stop();break;
   case RESTORE:writeInt(L"orbHidden",0);writeInt(L"orbDate",0);refreshOrb();break;
   case TODAY:writeInt(L"orbDate",dateKey());refreshOrb();break;case HIDE:writeInt(L"orbHidden",1);refreshOrb();break;
   case SETTINGS:showSettings();break;case QUIT:closeCapture();if(recorder.active()){quitAfterRecord=true;recorder.stop();report(L"正在停止并保存录屏…");}else DestroyWindow(host);break;
   case COPY:copied();break;case SAVE:save(false);break;case SAVEAS:save(true);break;
   case FOLDER:{auto path=choosePath(true);if(!path.empty()){folder=path;writeString(L"folder",folder);}break;}
   case APPLYKEY:{
    WORD key=WORD(SendMessage(hotkeyControl,HKM_GETHOTKEY,0,0));BYTE flags=HIBYTE(key);
    if(!(flags&(HOTKEYF_CONTROL|HOTKEYF_ALT))){error(L"Use Control or Alt in the shortcut.");break;}
    DWORD oldVK=vk,oldMods=mods;vk=LOBYTE(key);mods=((flags&HOTKEYF_CONTROL)?MOD_CONTROL:0)|((flags&HOTKEYF_ALT)?MOD_ALT:0)|((flags&HOTKEYF_SHIFT)?MOD_SHIFT:0);
    UnregisterHotKey(host,1);if(!RegisterHotKey(host,1,mods|MOD_NOREPEAT,vk)){vk=oldVK;mods=oldMods;registerKey();error(L"Shortcut unavailable; original restored.");}else{writeInt(L"key",vk);writeInt(L"modifiers",mods);}break;
   }
   case STARTUP:{
    HKEY key;auto enabled=IsDlgButtonChecked(settings,STARTUP)==BST_CHECKED;
    if(RegCreateKeyEx(HKEY_CURRENT_USER,L"Software\\Microsoft\\Windows\\CurrentVersion\\Run",0,nullptr,0,KEY_SET_VALUE,nullptr,&key,nullptr)==ERROR_SUCCESS){
     LSTATUS result;if(enabled){wchar_t path[32768];GetModuleFileName(nullptr,path,32768);auto quoted=L"\""+std::wstring(path)+L"\"";result=RegSetValueEx(key,L"SnapliqDevelopment",0,REG_SZ,reinterpret_cast<const BYTE*>(quoted.c_str()),DWORD((quoted.size()+1)*2));}
     else result=RegDeleteValue(key,L"SnapliqDevelopment");RegCloseKey(key);if(result!=ERROR_SUCCESS&&result!=ERROR_FILE_NOT_FOUND)error(L"Could not update startup setting.");
    }break;
   }
  }
 }
} app;
LRESULT CALLBACK HostProc(HWND w,UINT m,WPARAM a,LPARAM b){
 switch(m){
 case WM_HOTKEY:app.capture(false);return 0;
 case WM_COMMAND:app.command(LOWORD(a));return 0;
 case TRAY:if(b==WM_LBUTTONUP)app.capture(false);else if(b==WM_RBUTTONUP)app.popup(false);return 0;
 case CAPTURED:app.showCapture(reinterpret_cast<Result*>(b));return 0;
 case OCR_DONE:{std::unique_ptr<OCRResult> r(reinterpret_cast<OCRResult*>(b));if(app.ocrEdit&&r->generation==app.ocrGeneration)SetWindowText(app.ocrEdit,r->error.empty()?r->text.c_str():r->error.c_str());return 0;}
 case HIT_DONE:{std::unique_ptr<HitResult> r(reinterpret_cast<HitResult*>(b));app.hitBusy=false;POINT p;GetCursorPos(&p);if(app.desktop&&app.overlay&&!app.selected&&!app.dragging&&r->generation==app.generation&&std::abs(p.x-r->point.x)+std::abs(p.y-r->point.y)<5&&r->rect.right>r->rect.left){app.candidate={double(r->rect.left-app.desktop->bounds.left),double(r->rect.top-app.desktop->bounds.top),double(r->rect.right-r->rect.left),double(r->rect.bottom-r->rect.top)};app.candidateValid=true;InvalidateRect(app.overlay,nullptr,FALSE);}return 0;}
 case RECORD_DONE:{app.tray.uFlags=NIF_TIP;wcscpy_s(app.tray.szTip,PRODUCT_NAME);Shell_NotifyIcon(NIM_MODIFY,&app.tray);std::unique_ptr<RecordingOutcome> r(reinterpret_cast<RecordingOutcome*>(b));KillTimer(w,2);if(app.recordingWindow)app.recordingWindow->update();app.refreshOrb();app.report(r->saved?L"已保存录屏":L"录屏停止，文件需要恢复");if(!r->message.empty()&&!app.quitAfterRecord)app.error(r->message);if(app.quitAfterRecord)DestroyWindow(w);return 0;}
 case WM_TIMER:if(a==2){if(app.recordingWindow)app.recordingWindow->update();app.tray.uFlags=NIF_TIP;wcsncpy_s(app.tray.szTip,app.recorder.stopping()?L"Snapliq - Finishing":!app.recorder.started()?L"Snapliq - Preparing":app.recorder.paused()?L"Snapliq - Paused":L"Snapliq - Recording",_TRUNCATE);Shell_NotifyIcon(NIM_MODIFY,&app.tray);}else app.refreshOrb();return 0;
 case WM_DISPLAYCHANGE:app.recorder.stop();app.closeCapture();app.placeOrb();return 0;
 case WM_TIMECHANGE:app.refreshOrb();return 0;
 case WM_SETTINGCHANGE:app.refreshTrayIcon();return 0;
 case WM_POWERBROADCAST:if(a==PBT_APMSUSPEND){app.recorder.stop();app.closeCapture();}else if(a==PBT_APMRESUMEAUTOMATIC){app.placeOrb();app.refreshOrb();}return TRUE;
 case WM_DESTROY:app.bridge.stop();UnregisterHotKey(w,1);Shell_NotifyIcon(NIM_DELETE,&app.tray);app.recorder.stop();app.recorder.join();if(app.recordingWindow)app.recordingWindow->close();if(app.worker.joinable())app.worker.join();if(app.ocrWorker.joinable())app.ocrWorker.join();if(app.hitWorker.joinable())app.hitWorker.join();PostQuitMessage(0);return 0;
 }return DefWindowProc(w,m,a,b);
}
LRESULT CALLBACK OrbProc(HWND w,UINT m,WPARAM a,LPARAM b){
 switch(m){
 case WM_PAINT:{
  PAINTSTRUCT ps;auto dc=BeginPaint(w,&ps);RECT r;GetClientRect(w,&r);auto brush=CreateSolidBrush(RGB(34,35,38));FillRect(dc,&r,brush);DeleteObject(brush);
  SetMapMode(dc,MM_ANISOTROPIC);SetWindowExtEx(dc,48,48,nullptr);SetViewportExtEx(dc,r.right,r.bottom,nullptr);
  auto pen=CreatePen(PS_SOLID,3,RGB(238,240,242));auto old=SelectObject(dc,pen);
  MoveToEx(dc,14,26,nullptr);LineTo(dc,14,14);LineTo(dc,26,14);MoveToEx(dc,22,34,nullptr);LineTo(dc,34,34);LineTo(dc,34,22);
  auto oldBrush=SelectObject(dc,GetStockObject(WHITE_BRUSH));Ellipse(dc,22,22,27,27);SelectObject(dc,oldBrush);SelectObject(dc,old);DeleteObject(pen);EndPaint(w,&ps);return 0;
 }
 case WM_LBUTTONDOWN:app.orbDragging=false;GetCursorPos(&app.orbStart);GetWindowRect(w,&app.orbOrigin);SetCapture(w);return 0;
 case WM_MOUSEMOVE:if(GetCapture()==w){POINT p;GetCursorPos(&p);int dx=p.x-app.orbStart.x,dy=p.y-app.orbStart.y;if(std::abs(dx)+std::abs(dy)>4)app.orbDragging=true;if(app.orbDragging)SetWindowPos(w,HWND_TOPMOST,app.orbOrigin.left+dx,app.orbOrigin.top+dy,0,0,SWP_NOSIZE|SWP_NOACTIVATE);}return 0;
 case WM_LBUTTONUP:ReleaseCapture();if(app.orbDragging)app.dockOrb();else app.capture(false);return 0;
 case WM_RBUTTONUP:app.popup(true);return 0;
 case WM_DPICHANGED:{auto r=reinterpret_cast<RECT*>(b);int size=MulDiv(48,HIWORD(a),96);SetWindowPos(w,HWND_TOPMOST,r->left,r->top,size,size,SWP_NOACTIVATE);SetWindowRgn(w,CreateEllipticRgn(0,0,size,size),TRUE);return 0;}
 }return DefWindowProc(w,m,a,b);
}
LRESULT CALLBACK OverlayProc(HWND w,UINT m,WPARAM a,LPARAM b){
 switch(m){
 case WM_ERASEBKGND:return 1;
 case WM_PAINT:{PAINTSTRUCT ps;auto dc=BeginPaint(w,&ps);auto memory=CreateCompatibleDC(dc);RECT r;GetClientRect(w,&r);auto bitmap=CreateCompatibleBitmap(dc,r.right,r.bottom);auto old=SelectObject(memory,bitmap);app.paint(memory);BitBlt(dc,0,0,r.right,r.bottom,memory,0,0,SRCCOPY);SelectObject(memory,old);DeleteObject(bitmap);DeleteDC(memory);EndPaint(w,&ps);return 0;}
 case WM_LBUTTONDOWN:app.down({GET_X_LPARAM(b),GET_Y_LPARAM(b)});return 0;
 case WM_MOUSEMOVE:app.move({GET_X_LPARAM(b),GET_Y_LPARAM(b)});return 0;
 case WM_LBUTTONUP:if(!app.selected&&app.candidateValid){app.selection=app.candidate;app.selected=true;}app.dragging=false;ReleaseCapture();InvalidateRect(w,nullptr,FALSE);return 0;
 case WM_KEYDOWN:
  if(a==VK_ESCAPE)app.closeCapture();else if(a==VK_RETURN||(a=='C'&&(GetKeyState(VK_CONTROL)&0x8000)))app.copied();else if(a=='S'&&(GetKeyState(VK_CONTROL)&0x8000))app.save(false);
  else if(app.selected&&a>=VK_LEFT&&a<=VK_DOWN){double step=(GetKeyState(VK_SHIFT)&0x8000)?10:1;bool size=GetKeyState(VK_MENU)&0x8000;
   if(a==VK_LEFT){if(size)app.selection.width=std::max(1.0,app.selection.width-step);else app.selection.x-=step;}
   if(a==VK_RIGHT){if(size)app.selection.width+=step;else app.selection.x+=step;}
   if(a==VK_UP){if(size)app.selection.height=std::max(1.0,app.selection.height-step);else app.selection.y-=step;}
   if(a==VK_DOWN){if(size)app.selection.height+=step;else app.selection.y+=step;}
   app.selection=sl_clamp(app.selection,{0,0,double(app.desktop->image.width),double(app.desktop->image.height)});InvalidateRect(w,nullptr,FALSE);
  }return 0;
 case WM_CLOSE:app.closeCapture();return 0;
 }return DefWindowProc(w,m,a,b);
}
LRESULT CALLBACK OCRProc(HWND w,UINT m,WPARAM a,LPARAM b){
 if(m==WM_DPICHANGED){applyWindowDpi(w,HIWORD(a),reinterpret_cast<RECT*>(b));return 0;}
 if(m==WM_NCDESTROY)releaseDpiFont(w);
 if(m==WM_COMMAND&&LOWORD(a)==1&&app.ocrEdit){SendMessage(app.ocrEdit,EM_SETSEL,0,-1);SendMessage(app.ocrEdit,WM_COPY,0,0);return 0;}
 if(m==WM_SIZE&&app.ocrEdit){MoveWindow(app.ocrEdit,dip(w,15),dip(w,15),std::max(1,int(LOWORD(b))-dip(w,30)),std::max(1,int(HIWORD(b))-dip(w,75)),TRUE);MoveWindow(GetDlgItem(w,1),dip(w,15),std::max(dip(w,15),int(HIWORD(b))-dip(w,45)),dip(w,160),dip(w,30),TRUE);return 0;}
 if(m==WM_CLOSE){++app.ocrGeneration;DestroyWindow(w);app.ocrWindow=app.ocrEdit=nullptr;if(app.overlay){ShowWindow(app.overlay,SW_SHOW);SetForegroundWindow(app.overlay);}return 0;}
 return DefWindowProc(w,m,a,b);
}
LRESULT CALLBACK SettingsProc(HWND w,UINT m,WPARAM a,LPARAM b){if(m==WM_DPICHANGED){applyWindowDpi(w,HIWORD(a),reinterpret_cast<RECT*>(b));return 0;}if(m==WM_NCDESTROY)releaseDpiFont(w);if(m==WM_COMMAND){app.command(LOWORD(a));return 0;}if(m==WM_CLOSE){ShowWindow(w,SW_HIDE);return 0;}return DefWindowProc(w,m,a,b);}
void App::showSettings(){
 if(settings){ShowWindow(settings,SW_SHOW);SetForegroundWindow(settings);return;}
 settings=CreateWindowEx(WS_EX_APPWINDOW,L"SnapliqSettings",L"Snapliq 设置",WS_OVERLAPPED|WS_CAPTION|WS_SYSMENU|WS_MINIMIZEBOX,CW_USEDEFAULT,CW_USEDEFAULT,570,500,nullptr,nullptr,GetModuleHandle(nullptr),nullptr);
 auto child=[&](const wchar_t* cls,const wchar_t* title,DWORD style,int x,int y,int width,int height,int id){return CreateWindowEx(0,cls,title,WS_CHILD|WS_VISIBLE|style,x,y,width,height,settings,reinterpret_cast<HMENU>(INT_PTR(id)),GetModuleHandle(nullptr),nullptr);};
 child(L"STATIC",PRODUCT_NAME,0,24,22,480,28,0);child(L"STATIC",L"Capture. Record. Share. · 独立桌面截图开发版",0,24,54,500,25,0);
 child(L"STATIC",L"全局截图快捷键",0,24,104,145,25,0);
 hotkeyControl=child(HOTKEY_CLASS,L"",WS_BORDER|WS_TABSTOP,180,100,180,28,0);
 BYTE flags=((mods&MOD_CONTROL)?HOTKEYF_CONTROL:0)|((mods&MOD_ALT)?HOTKEYF_ALT:0)|((mods&MOD_SHIFT)?HOTKEYF_SHIFT:0);SendMessage(hotkeyControl,HKM_SETHOTKEY,MAKEWORD(vk,flags),0);
 child(L"BUTTON",L"应用",BS_PUSHBUTTON|WS_TABSTOP,385,100,95,28,APPLYKEY);
 child(L"BUTTON",L"默认保存位置…",BS_PUSHBUTTON|WS_TABSTOP,24,153,210,32,FOLDER);
 child(L"BUTTON",L"显示悬浮球",BS_PUSHBUTTON|WS_TABSTOP,255,153,210,32,RESTORE);
 child(L"BUTTON",L"登录时启动 Snapliq",BS_AUTOCHECKBOX|WS_TABSTOP,24,205,400,28,STARTUP);
 DWORD bytes=0;bool enabled=RegGetValue(HKEY_CURRENT_USER,L"Software\\Microsoft\\Windows\\CurrentVersion\\Run",L"SnapliqDevelopment",RRF_RT_REG_SZ,nullptr,nullptr,&bytes)==ERROR_SUCCESS;CheckDlgButton(settings,STARTUP,enabled?BST_CHECKED:BST_UNCHECKED);
 child(L"BUTTON",L"开始截图",BS_DEFPUSHBUTTON|WS_TABSTOP,24,257,180,34,REGION);
 child(L"BUTTON",L"屏幕录制…",BS_PUSHBUTTON|WS_TABSTOP,230,257,190,34,RECORD);
 child(L"BUTTON",L"智能框选窗口",BS_AUTOCHECKBOX|WS_TABSTOP,24,300,220,28,SMART);CheckDlgButton(settings,SMART,readInt(L"smart",0)?BST_CHECKED:BST_UNCHECKED);
 child(L"BUTTON",L"识别窗口内控件",BS_AUTOCHECKBOX|WS_TABSTOP,255,300,250,28,CONTROLS);CheckDlgButton(settings,CONTROLS,readInt(L"controls",0)?BST_CHECKED:BST_UNCHECKED);
 child(L"BUTTON",L"Connect Snapliq for Chrome",BS_PUSHBUTTON|WS_TABSTOP,24,330,300,28,CONNECT_CHROME);
 child(L"STATIC",L"关闭设置后，系统托盘和快捷键继续运行。",0,24,360,500,24,0);
 SendMessage(settings,WM_SETICON,ICON_BIG,reinterpret_cast<LPARAM>(LoadIcon(GetModuleHandle(nullptr),MAKEINTRESOURCE(1))));
 applyWindowDpi(settings);ShowWindow(settings,SW_SHOW);SetForegroundWindow(settings);
}
int WINAPI wWinMain(HINSTANCE instance,HINSTANCE,PWSTR,int){
 int argc=0;auto argv=CommandLineToArgvW(GetCommandLine(),&argc);
 if(argv&&argc>1&&std::wstring(argv[1]).starts_with(L"chrome-extension://")){auto origin=std::wstring(argv[1]);LocalFree(argv);return NativeBridge::runHost(origin.c_str());}
 if(argv)LocalFree(argv);
 HANDLE single=CreateMutex(nullptr,FALSE,L"Local\\Snapliq.Development");if(GetLastError()==ERROR_ALREADY_EXISTS){if(single)CloseHandle(single);return 0;}
 winrt::init_apartment(winrt::apartment_type::single_threaded);INITCOMMONCONTROLSEX controls{sizeof(controls),ICC_WIN95_CLASSES};InitCommonControlsEx(&controls);
 for(auto entry:std::vector<std::pair<const wchar_t*,WNDPROC>>{{L"SnapliqHost",HostProc},{L"SnapliqOrb",OrbProc},{L"SnapliqOverlay",OverlayProc},{L"SnapliqSettings",SettingsProc},{L"SnapliqOCR",OCRProc}}){
  WNDCLASS cls{};cls.hInstance=instance;cls.lpszClassName=entry.first;cls.lpfnWndProc=entry.second;cls.hCursor=LoadCursor(nullptr,IDC_CROSS);cls.hIcon=LoadIcon(instance,MAKEINTRESOURCE(1));cls.hbrBackground=reinterpret_cast<HBRUSH>(COLOR_WINDOW+1);RegisterClass(&cls);
 }
 app.host=CreateWindowEx(WS_EX_TOOLWINDOW,L"SnapliqHost",PRODUCT_NAME,WS_POPUP,0,0,0,0,nullptr,nullptr,instance,nullptr);
 app.orb=CreateWindowEx(WS_EX_TOPMOST|WS_EX_TOOLWINDOW|WS_EX_NOACTIVATE,L"SnapliqOrb",PRODUCT_NAME,WS_POPUP,0,0,48,48,app.host,nullptr,instance,nullptr);SetWindowDisplayAffinity(app.orb,WDA_EXCLUDEFROMCAPTURE);
 app.placeOrb(readInt(L"orbX",0)!=0);app.refreshOrb();
 app.tray.cbSize=sizeof(app.tray);app.tray.hWnd=app.host;app.tray.uID=1;app.tray.uCallbackMessage=TRAY;app.tray.uFlags=NIF_MESSAGE|NIF_ICON|NIF_TIP;app.tray.hIcon=LoadIcon(instance,MAKEINTRESOURCE(2));wcscpy_s(app.tray.szTip,PRODUCT_NAME);Shell_NotifyIcon(NIM_ADD,&app.tray);
 app.bridge.start([](int action){PostMessage(app.host,WM_COMMAND,action,0);});
 app.refreshTrayIcon();app.registerKey();SetTimer(app.host,1,60000,nullptr);app.showSettings();
 MSG message;while(GetMessage(&message,nullptr,0,0)>0){if(app.settings&&IsWindowVisible(app.settings)&&IsDialogMessage(app.settings,&message))continue;TranslateMessage(&message);DispatchMessage(&message);}
 if(single)CloseHandle(single);return 0;
}
