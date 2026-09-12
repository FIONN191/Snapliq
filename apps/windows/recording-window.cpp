#include "recording-window.h"
#include "dpi.h"
#include <shobjidl.h>
#include <winrt/base.h>
#include <shellapi.h>
#include <dwmapi.h>
LRESULT CALLBACK RecordingWindow::proc(HWND w,UINT m,WPARAM a,LPARAM b){
 auto self=reinterpret_cast<RecordingWindow*>(GetWindowLongPtr(w,GWLP_USERDATA));
 if(m==WM_NCCREATE){self=reinterpret_cast<RecordingWindow*>(reinterpret_cast<CREATESTRUCT*>(b)->lpCreateParams);SetWindowLongPtr(w,GWLP_USERDATA,reinterpret_cast<LONG_PTR>(self));}
 if(self){
  if(m==WM_DPICHANGED){applyWindowDpi(w,HIWORD(a),reinterpret_cast<RECT*>(b));return 0;}
  if(m==WM_NCDESTROY)releaseDpiFont(w);
  if(m==WM_COMMAND){switch(LOWORD(a)){case 1:self->begin();return 0;case 2:self->recorder_.pause();self->update();return 0;case 3:self->recorder_.stop();SetWindowText(self->label_,L"正在封装…");return 0;}}
  if(m==WM_CLOSE){ShowWindow(w,SW_HIDE);return 0;}
 }
 return DefWindowProc(w,m,a,b);
}
void RecordingWindow::present(){
 if(recorder_.active()){if(controls_)ShowWindow(controls_,SW_SHOWNOACTIVATE);return;}
 if(!picker_){
  WNDCLASS c{};c.hInstance=GetModuleHandle(nullptr);c.lpszClassName=L"SnapliqRecording";c.lpfnWndProc=proc;c.hCursor=LoadCursor(nullptr,IDC_ARROW);c.hbrBackground=reinterpret_cast<HBRUSH>(COLOR_WINDOW+1);RegisterClass(&c);
  picker_=CreateWindowEx(WS_EX_TOOLWINDOW,L"SnapliqRecording",L"Snapliq 屏幕录制",WS_OVERLAPPED|WS_CAPTION|WS_SYSMENU,CW_USEDEFAULT,CW_USEDEFAULT,550,300,owner_,nullptr,c.hInstance,this);
  auto child=[&](const wchar_t* cls,const wchar_t* title,DWORD style,int x,int y,int width,int height,int id){return CreateWindowEx(0,cls,title,WS_CHILD|WS_VISIBLE|style,x,y,width,height,picker_,reinterpret_cast<HMENU>(INT_PTR(id)),c.hInstance,nullptr);};
  child(L"STATIC",L"选择屏幕或窗口 · MP4 · 30 fps",0,20,20,490,24,0);
  source_=child(L"COMBOBOX",L"",CBS_DROPDOWNLIST|WS_VSCROLL,20,60,490,300,0);
  system_=child(L"BUTTON",L"录制系统声音",BS_AUTOCHECKBOX,20,110,220,28,0);
  microphone_=child(L"BUTTON",L"录制麦克风",BS_AUTOCHECKBOX,260,110,220,28,0);
  child(L"BUTTON",L"选择保存文件并开始…",BS_PUSHBUTTON,20,155,300,34,1);
  child(L"STATIC",L"关闭设置不会停止录制；区域视频裁剪尚未提供。",0,20,210,490,28,0);
 }
 applyWindowDpi(picker_);
 choices_.clear();SendMessage(source_,CB_RESETCONTENT,0,0);
 EnumDisplayMonitors(nullptr,nullptr,[](HMONITOR monitor,HDC,LPRECT bounds,LPARAM data)->BOOL{
  auto self=reinterpret_cast<RecordingWindow*>(data);RecordingOptions o;o.monitor=monitor;self->choices_.push_back(o);
  auto title=L"屏幕 "+std::to_wstring(self->choices_.size())+L" · "+std::to_wstring(bounds->right-bounds->left)+L" × "+std::to_wstring(bounds->bottom-bounds->top);
  SendMessage(self->source_,CB_ADDSTRING,0,reinterpret_cast<LPARAM>(title.c_str()));return TRUE;
 },reinterpret_cast<LPARAM>(this));
 for(auto const& target:desktopWindows()){RecordingOptions o;o.window=target.window;choices_.push_back(o);SendMessage(source_,CB_ADDSTRING,0,reinterpret_cast<LPARAM>(target.label.c_str()));}
 SendMessage(source_,CB_SETCURSEL,0,0);ShowWindow(picker_,SW_SHOW);SetForegroundWindow(picker_);
}
void RecordingWindow::begin(){
 auto index=SendMessage(source_,CB_GETCURSEL,0,0);if(index<0||size_t(index)>=choices_.size())return;
 try {
  auto dialog=winrt::create_instance<IFileSaveDialog>(CLSID_FileSaveDialog);
  COMDLG_FILTERSPEC type{L"MP4 video",L"*.mp4"};dialog->SetFileTypes(1,&type);dialog->SetDefaultExtension(L"mp4");dialog->SetFileName(L"Snapliq.mp4");
  if(FAILED(dialog->Show(picker_)))return;
  winrt::com_ptr<IShellItem> item;winrt::check_hresult(dialog->GetResult(item.put()));PWSTR path;winrt::check_hresult(item->GetDisplayName(SIGDN_FILESYSPATH,&path));
  auto options=choices_[size_t(index)];options.path=path;CoTaskMemFree(path);options.systemAudio=SendMessage(system_,BM_GETCHECK,0,0)==BST_CHECKED;options.microphone=SendMessage(microphone_,BM_GETCHECK,0,0)==BST_CHECKED;
  ShowWindow(picker_,SW_HIDE);start_(options);
 }catch(const winrt::hresult_error& e){MessageBox(picker_,e.message().c_str(),L"Snapliq",MB_OK|MB_ICONWARNING);}
}
void RecordingWindow::update(){
 if(!recorder_.active()){if(controls_)ShowWindow(controls_,SW_HIDE);return;}
 if(!controls_){
  controls_=CreateWindowEx(WS_EX_TOPMOST|WS_EX_TOOLWINDOW|WS_EX_NOACTIVATE,L"SnapliqRecording",L"Snapliq Recording",WS_POPUP|WS_BORDER,50,50,410,56,owner_,nullptr,GetModuleHandle(nullptr),this);
  label_=CreateWindow(L"STATIC",L"准备录制…",WS_CHILD|WS_VISIBLE,12,18,190,25,controls_,nullptr,GetModuleHandle(nullptr),nullptr);
  pause_=CreateWindow(L"BUTTON",L"暂停",WS_CHILD|WS_VISIBLE,205,12,85,30,controls_,reinterpret_cast<HMENU>(2),GetModuleHandle(nullptr),nullptr);
  CreateWindow(L"BUTTON",L"停止",WS_CHILD|WS_VISIBLE,305,12,85,30,controls_,reinterpret_cast<HMENU>(3),GetModuleHandle(nullptr),nullptr);
 }
 applyWindowDpi(controls_);
 auto seconds=int(recorder_.seconds());wchar_t text[80];swprintf_s(text,L"%s %02d:%02d",recorder_.stopping()?L"Finishing":!recorder_.started()?L"Preparing":recorder_.paused()?L"Ⅱ 已暂停":L"● 录制中",seconds/60,seconds%60);SetWindowText(label_,text);SetWindowText(pause_,recorder_.paused()?L"继续":L"暂停");
 EnableWindow(pause_,recorder_.started()&&!recorder_.stopping());
 if(SetWindowDisplayAffinity(controls_,WDA_EXCLUDEFROMCAPTURE))ShowWindow(controls_,SW_SHOWNOACTIVATE);
 else ShowWindow(controls_,SW_HIDE); // Tray retains pause/stop on systems that cannot exclude controls.
}
void RecordingWindow::close(){if(picker_)DestroyWindow(picker_);if(controls_)DestroyWindow(controls_);picker_=controls_=nullptr;}
