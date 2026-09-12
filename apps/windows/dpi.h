#pragma once
#include <windows.h>
#include <algorithm>
#include <shellscalingapi.h>
inline UINT monitorDpi(HMONITOR monitor){UINT x=96,y=96;if(FAILED(GetDpiForMonitor(monitor,MDT_EFFECTIVE_DPI,&x,&y)))return 96;return x;}
inline int dip(HWND window,int value){return MulDiv(value,int(GetDpiForWindow(window)),96);}
inline void releaseDpiFont(HWND window){auto font=static_cast<HFONT>(RemoveProp(window,L"Snapliq.DpiFont"));if(font)DeleteObject(font);RemoveProp(window,L"Snapliq.Dpi");}
inline void applyWindowDpi(HWND window,UINT dpi=0,const RECT* suggested=nullptr){
 if(!dpi)dpi=GetDpiForWindow(window);
 auto stored=GetProp(window,L"Snapliq.Dpi");auto old=UINT(reinterpret_cast<UINT_PTR>(stored));if(!old)old=96;
 if(!dpi)dpi=96;
 if(stored&&dpi==old&&!suggested)return;
 SetProp(window,L"Snapliq.Dpi",reinterpret_cast<HANDLE>(UINT_PTR(dpi)));
 LOGFONT font{};font.lfHeight=-MulDiv(13,int(dpi),96);wcscpy_s(font.lfFaceName,L"Segoe UI");auto next=CreateFontIndirect(&font);
 struct Change{UINT from,to;HFONT font;};Change change{old,dpi,next};
 EnumChildWindows(window,[](HWND child,LPARAM value)->BOOL{
  auto& c=*reinterpret_cast<Change*>(value);RECT r;GetWindowRect(child,&r);MapWindowPoints(nullptr,GetParent(child),reinterpret_cast<POINT*>(&r),2);
  SetWindowPos(child,nullptr,MulDiv(r.left,c.to,c.from),MulDiv(r.top,c.to,c.from),MulDiv(r.right-r.left,c.to,c.from),MulDiv(r.bottom-r.top,c.to,c.from),SWP_NOZORDER|SWP_NOACTIVATE);
  SendMessage(child,WM_SETFONT,reinterpret_cast<WPARAM>(c.font),TRUE);return TRUE;
 },reinterpret_cast<LPARAM>(&change));
 auto previous=static_cast<HFONT>(GetProp(window,L"Snapliq.DpiFont"));SetProp(window,L"Snapliq.DpiFont",next);if(previous)DeleteObject(previous);
 RECT r;if(suggested)r=*suggested;else{GetWindowRect(window,&r);r.right=r.left+MulDiv(r.right-r.left,dpi,old);r.bottom=r.top+MulDiv(r.bottom-r.top,dpi,old);}
 SetWindowPos(window,nullptr,r.left,r.top,r.right-r.left,r.bottom-r.top,SWP_NOZORDER|SWP_NOACTIVATE);
}
