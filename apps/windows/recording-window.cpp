#include "recording-window.h"
#include "dpi.h"
#include "recording-preferences.h"
#include <winrt/base.h>
#include <shellapi.h>
#include <dwmapi.h>
LRESULT CALLBACK RecordingWindow::proc(HWND w,UINT m,WPARAM a,LPARAM b){
 auto self=reinterpret_cast<RecordingWindow*>(GetWindowLongPtr(w,GWLP_USERDATA));
 if(m==WM_NCCREATE){self=reinterpret_cast<RecordingWindow*>(reinterpret_cast<CREATESTRUCT*>(b)->lpCreateParams);SetWindowLongPtr(w,GWLP_USERDATA,reinterpret_cast<LONG_PTR>(self));}
 if(self){
  if(m==WM_DPICHANGED){applyWindowDpi(w,HIWORD(a),reinterpret_cast<RECT*>(b));return 0;}
  if(m==WM_NCDESTROY)releaseDpiFont(w);
  if(m==WM_COMMAND){switch(LOWORD(a)){case 1:self->begin();return 0;case 2:self->recorder_.pause();self->update();return 0;case 3:self->recorder_.stop();SetWindowText(self->label_,tr(L"正在封装…",L"Finishing…"));return 0;
   case 4:case 5:
    try{recording_preferences::setEnabled(LOWORD(a)==4?recording_preferences::systemAudioKey:recording_preferences::microphoneKey,SendMessage(LOWORD(a)==4?self->system_:self->microphone_,BM_GETCHECK,0,0)==BST_CHECKED);}
    catch(const winrt::hresult_error& e){
     SendMessage(LOWORD(a)==4?self->system_:self->microphone_,BM_SETCHECK,recording_preferences::enabled(LOWORD(a)==4?recording_preferences::systemAudioKey:recording_preferences::microphoneKey)?BST_CHECKED:BST_UNCHECKED,0);
     MessageBox(w,e.message().c_str(),L"Snapliq",MB_OK|MB_ICONWARNING);
    }return 0;
  }}
  if(m==WM_CLOSE){ShowWindow(w,SW_HIDE);return 0;}
 }
 return DefWindowProc(w,m,a,b);
}
void RecordingWindow::registerClass(){
 WNDCLASS c{};c.hInstance=GetModuleHandle(nullptr);c.lpszClassName=L"SnapliqRecording";c.lpfnWndProc=proc;c.hCursor=LoadCursor(nullptr,IDC_ARROW);c.hbrBackground=reinterpret_cast<HBRUSH>(COLOR_WINDOW+1);RegisterClass(&c);
}
void RecordingWindow::present(){
 if(recorder_.active()){update();return;}
 if(!picker_){
  registerClass();auto instance=GetModuleHandle(nullptr);
  picker_=CreateWindowEx(WS_EX_TOOLWINDOW,L"SnapliqRecording",tr(L"Snapliq 屏幕录制",L"Snapliq Screen recording"),WS_OVERLAPPED|WS_CAPTION|WS_SYSMENU,CW_USEDEFAULT,CW_USEDEFAULT,650,400,owner_,nullptr,instance,this);
  auto child=[&](const wchar_t* cls,const wchar_t* title,DWORD style,int x,int y,int width,int height,int id){return CreateWindowEx(0,cls,title,WS_CHILD|WS_VISIBLE|style,x,y,width,height,picker_,reinterpret_cast<HMENU>(INT_PTR(id)),instance,nullptr);};
  auto label=[&](const wchar_t* cls,const wchar_t* zh,const wchar_t* en,DWORD style,int x,int y,int width,int height,int id){auto w=child(cls,tr(zh,en),style,x,y,width,height,id);labels_.add(w,zh,en);return w;};
  label(L"STATIC",L"录制整个屏幕或单个窗口 · MP4 · 30 fps",L"Record an entire screen or one window · MP4 · 30 fps",0,20,20,590,24,0);
  source_=child(L"COMBOBOX",L"",CBS_DROPDOWNLIST|WS_VSCROLL|WS_TABSTOP,20,60,590,300,0);
  system_=label(L"BUTTON",L"录制系统声音",L"Record system audio",BS_AUTOCHECKBOX|WS_TABSTOP,20,110,270,28,4);
  microphone_=label(L"BUTTON",L"录制麦克风",L"Record microphone",BS_AUTOCHECKBOX|WS_TABSTOP,320,110,270,28,5);
  label(L"BUTTON",L"开始录制",L"Start recording",BS_DEFPUSHBUTTON|WS_TABSTOP,20,155,300,34,1);
  label(L"STATIC",L"停止后自动保存到默认文件夹；未设置时使用视频 / Snapliq。",L"Saves automatically when stopped. Default folder: Videos / Snapliq.",0,20,205,590,38,0);
  label(L"STATIC",L"整个屏幕包含桌面、浏览器和其他应用，切换软件不中断。",L"Includes the desktop, browser and other apps. Switching apps keeps recording.",0,20,250,590,42,0);
  label(L"STATIC",L"系统禁止捕获的内容除外；关闭设置不会停止录制。",L"Protected content is excluded. Closing settings keeps recording.",0,20,305,590,38,0);
 }
 SendMessage(system_,BM_SETCHECK,recording_preferences::enabled(recording_preferences::systemAudioKey)?BST_CHECKED:BST_UNCHECKED,0);
 SendMessage(microphone_,BM_SETCHECK,recording_preferences::enabled(recording_preferences::microphoneKey)?BST_CHECKED:BST_UNCHECKED,0);
 applyWindowDpi(picker_);
 choices_.clear();sourceNames_.clear();SendMessage(source_,CB_RESETCONTENT,0,0);
 EnumDisplayMonitors(nullptr,nullptr,[](HMONITOR monitor,HDC,LPRECT bounds,LPARAM data)->BOOL{
  auto self=reinterpret_cast<RecordingWindow*>(data);RecordingOptions o;o.monitor=monitor;self->choices_.push_back(o);
  self->sourceNames_.push_back(std::to_wstring(self->choices_.size())+L" · "+std::to_wstring(bounds->right-bounds->left)+L" × "+std::to_wstring(bounds->bottom-bounds->top));return TRUE;
 },reinterpret_cast<LPARAM>(this));
 POINT point;GetCursorPos(&point);const auto current=MonitorFromPoint(point,MONITOR_DEFAULTTOPRIMARY);size_t selected=0;
 for(size_t i=0;i<choices_.size();++i)if(choices_[i].monitor==current){selected=i;break;}
 for(auto const& target:desktopWindows()){RecordingOptions o;o.window=target.window;choices_.push_back(o);sourceNames_.push_back(target.label);}
 refreshSourceLabels();SendMessage(source_,CB_SETCURSEL,selected,0);ShowWindow(picker_,SW_SHOW);SetForegroundWindow(picker_);
}
void RecordingWindow::refreshSourceLabels(){
 if(!source_)return;
 const auto selected=SendMessage(source_,CB_GETCURSEL,0,0);
 SendMessage(source_,WM_SETREDRAW,FALSE,0);SendMessage(source_,CB_RESETCONTENT,0,0);
 for(size_t i=0;i<choices_.size();++i){
  auto title=std::wstring(choices_[i].monitor?tr(L"整个屏幕 ",L"Entire screen "):tr(L"窗口 · ",L"Window · "))+(sourceNames_[i].empty()?std::wstring(tr(L"无标题窗口",L"Untitled window")):sourceNames_[i]);
  SendMessage(source_,CB_ADDSTRING,0,reinterpret_cast<LPARAM>(title.c_str()));
 }
 if(selected!=CB_ERR)SendMessage(source_,CB_SETCURSEL,selected,0);
 SendMessage(source_,WM_SETREDRAW,TRUE,0);InvalidateRect(source_,nullptr,TRUE);
}
void RecordingWindow::refreshLanguage(){
 labels_.refresh();
 if(picker_)SetWindowText(picker_,tr(L"Snapliq 屏幕录制",L"Snapliq Screen recording"));
 if(controls_)SetWindowText(controls_,tr(L"Snapliq 屏幕录制",L"Snapliq Recording"));
 refreshSourceLabels();
 if(recorder_.active())update();
}
void RecordingWindow::begin(){
 if(recorder_.active())return;
 auto index=SendMessage(source_,CB_GETCURSEL,0,0);if(index<0||size_t(index)>=choices_.size())return;
 try {
  auto options=choices_[size_t(index)];options.systemAudio=SendMessage(system_,BM_GETCHECK,0,0)==BST_CHECKED;options.microphone=SendMessage(microphone_,BM_GETCHECK,0,0)==BST_CHECKED;
  ShowWindow(picker_,SW_HIDE);start_(options);
 }catch(const winrt::hresult_error& e){MessageBox(picker_,e.message().c_str(),L"Snapliq",MB_OK|MB_ICONWARNING);}
}
void RecordingWindow::update(){
 if(!recorder_.active()){if(controls_)ShowWindow(controls_,SW_HIDE);return;}
 if(!controls_){
  registerClass();
  controls_=CreateWindowEx(WS_EX_TOPMOST|WS_EX_TOOLWINDOW|WS_EX_NOACTIVATE,L"SnapliqRecording",tr(L"Snapliq 屏幕录制",L"Snapliq Recording"),WS_POPUP|WS_BORDER,50,50,480,56,owner_,nullptr,GetModuleHandle(nullptr),this);
  label_=CreateWindow(L"STATIC",tr(L"准备录制…",L"Preparing…"),WS_CHILD|WS_VISIBLE,12,18,235,25,controls_,nullptr,GetModuleHandle(nullptr),nullptr);
  pause_=CreateWindow(L"BUTTON",tr(L"暂停",L"Pause"),WS_CHILD|WS_VISIBLE|WS_TABSTOP,255,12,95,30,controls_,reinterpret_cast<HMENU>(2),GetModuleHandle(nullptr),nullptr);
  auto stop=CreateWindow(L"BUTTON",tr(L"停止",L"Stop"),WS_CHILD|WS_VISIBLE|WS_TABSTOP,365,12,95,30,controls_,reinterpret_cast<HMENU>(3),GetModuleHandle(nullptr),nullptr);labels_.add(stop,L"停止",L"Stop");
 }
 applyWindowDpi(controls_);
 auto seconds=int(recorder_.seconds());wchar_t text[80];swprintf_s(text,L"%s %02d:%02d",recorder_.stopping()?tr(L"正在保存",L"Saving"):!recorder_.started()?tr(L"准备中",L"Preparing"):recorder_.paused()?tr(L"Ⅱ 已暂停",L"Ⅱ Paused"):tr(L"● 录制中",L"● Recording"),seconds/60,seconds%60);SetWindowText(label_,text);SetWindowText(pause_,recorder_.paused()?tr(L"继续",L"Resume"):tr(L"暂停",L"Pause"));
 EnableWindow(pause_,recorder_.started()&&!recorder_.stopping());
 if(SetWindowDisplayAffinity(controls_,WDA_EXCLUDEFROMCAPTURE))ShowWindow(controls_,SW_SHOWNOACTIVATE);
 else ShowWindow(controls_,SW_HIDE); // Tray retains pause/stop on systems that cannot exclude controls.
}
void RecordingWindow::close(){if(picker_)DestroyWindow(picker_);if(controls_)DestroyWindow(controls_);picker_=source_=system_=microphone_=controls_=label_=pause_=nullptr;labels_.clear();choices_.clear();sourceNames_.clear();}
