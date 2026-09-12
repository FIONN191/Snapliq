#include "desktop-services.h"
#include <algorithm>
#include <dwmapi.h>
#include <objbase.h>
#include <uiautomation.h>
#include <winrt/base.h>
#include <winrt/Windows.Foundation.h>
#include <winrt/Windows.Foundation.Collections.h>
#include <winrt/Windows.Media.Ocr.h>
#include <winrt/Windows.Globalization.h>
#include <winrt/Windows.Graphics.Imaging.h>
#include <winrt/Windows.Security.Cryptography.h>
#include <winrt/Windows.Storage.Streams.h>
#include <chrono>
using namespace winrt;
std::vector<WindowTarget> desktopWindows(){
 std::vector<WindowTarget> result;
 EnumWindows([](HWND w,LPARAM data)->BOOL{
  DWORD pid;GetWindowThreadProcessId(w,&pid);if(pid==GetCurrentProcessId()||!IsWindowVisible(w))return TRUE;
  DWORD cloaked=0;DwmGetWindowAttribute(w,DWMWA_CLOAKED,&cloaked,sizeof(cloaked));if(cloaked)return TRUE;
  RECT r;if(FAILED(DwmGetWindowAttribute(w,DWMWA_EXTENDED_FRAME_BOUNDS,&r,sizeof(r)))&&!GetWindowRect(w,&r))return TRUE;
  if(r.right-r.left<20||r.bottom-r.top<20)return TRUE;
  wchar_t title[512]{};GetWindowText(w,title,512);
  reinterpret_cast<std::vector<WindowTarget>*>(data)->push_back({w,r,*title?title:L"Window"});return TRUE;
 },reinterpret_cast<LPARAM>(&result));return result;
}
RECT controlCandidate(HWND window,POINT point){
 RECT fallback{};GetWindowRect(window,&fallback);
 auto automation=create_instance<IUIAutomation>(CLSID_CUIAutomation8);
 if(auto limits=automation.try_as<IUIAutomation2>()){limits->put_ConnectionTimeout(50);limits->put_TransactionTimeout(50);}
 com_ptr<IUIAutomationElement> element;check_hresult(automation->ElementFromHandle(window,element.put()));
 com_ptr<IUIAutomationTreeWalker> walker;check_hresult(automation->get_ControlViewWalker(walker.put()));
 auto deadline=std::chrono::steady_clock::now()+std::chrono::milliseconds(12);
 RECT best=fallback;int visited=0;
 for(int depth=0;depth<12&&std::chrono::steady_clock::now()<deadline;depth++){
  com_ptr<IUIAutomationElement> child;walker->GetFirstChildElement(element.get(),child.put());com_ptr<IUIAutomationElement> hit;
  while(child&&visited++<128&&std::chrono::steady_clock::now()<deadline){
   RECT r{};if(SUCCEEDED(child->get_CurrentBoundingRectangle(&r))&&PtInRect(&r,point)&&r.right-r.left>3&&r.bottom-r.top>3){hit=child;IntersectRect(&best,&r,&fallback);break;}
   com_ptr<IUIAutomationElement> next;walker->GetNextSiblingElement(child.get(),next.put());child=std::move(next);
  }
  if(!hit)break;element=std::move(hit);
 }
 return best;
}
std::wstring recognizeText(const Image& original){
 using namespace winrt::Windows::Media::Ocr;
 using namespace winrt::Windows::Graphics::Imaging;
 using winrt::Windows::Security::Cryptography::CryptographicBuffer;
 OcrEngine engine{nullptr};
 for(auto const& language:OcrEngine::AvailableRecognizerLanguages()){
  auto tag=std::wstring(language.LanguageTag());if(tag.rfind(L"zh",0)==0){engine=OcrEngine::TryCreateFromLanguage(language);break;}
 }
 if(!engine)engine=OcrEngine::TryCreateFromUserProfileLanguages();
 if(!engine)throw std::runtime_error("Install an English or Chinese OCR language pack in Windows Settings.");
 const int limit=int(OcrEngine::MaxImageDimension());
 double scale=std::min(1.0,double(limit)/std::max(original.width,original.height));
 const int width=std::max(1,int(original.width*scale)),height=std::max(1,int(original.height*scale));
 std::vector<uint8_t> pixels(size_t(width)*height*4);
 for(int y=0;y<height;y++)for(int x=0;x<width;x++){
  auto from=(size_t(std::min(original.height-1,int(y/scale)))*original.width+std::min(original.width-1,int(x/scale)))*4;
  auto to=(size_t(y)*width+x)*4;for(int k=0;k<4;k++)pixels[to+k]=original.bgra[from+k];
 }
 SoftwareBitmap bitmap(BitmapPixelFormat::Bgra8,width,height,BitmapAlphaMode::Premultiplied);
 bitmap.CopyFromBuffer(CryptographicBuffer::CreateFromByteArray(pixels));
 auto result=engine.RecognizeAsync(bitmap).get();
 std::wstring text;
 for(auto const& line:result.Lines()){if(!text.empty())text+=L"\r\n";text+=line.Text();}
 return text;
}
