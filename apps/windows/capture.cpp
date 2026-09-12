#include "capture.h"
#include <d3d11.h>
#include <dxgi1_2.h>
#include <windows.graphics.capture.interop.h>
#include <windows.graphics.directx.direct3d11.interop.h>
#include <winrt/Windows.Graphics.Capture.h>
#include <winrt/Windows.Graphics.DirectX.h>
#include <winrt/Windows.Graphics.DirectX.Direct3D11.h>
#include <wincodec.h>
#include <shlwapi.h>
#include <mutex>
#include <memory>
#include <condition_variable>
#include <chrono>
#include <stdexcept>
#include <cstring>
#include <algorithm>
using namespace winrt;
using namespace winrt::Windows::Graphics::Capture;
using namespace winrt::Windows::Graphics::DirectX;
using namespace winrt::Windows::Graphics::DirectX::Direct3D11;
static Image monitorImage(HMONITOR monitor){
 if(!GraphicsCaptureSession::IsSupported())throw std::runtime_error("Windows Graphics Capture is unavailable on this device.");
 com_ptr<ID3D11Device> d3d;com_ptr<ID3D11DeviceContext> ctx;
 check_hresult(D3D11CreateDevice(nullptr,D3D_DRIVER_TYPE_HARDWARE,nullptr,D3D11_CREATE_DEVICE_BGRA_SUPPORT,nullptr,0,D3D11_SDK_VERSION,d3d.put(),nullptr,ctx.put()));
 auto dxgi=d3d.as<IDXGIDevice>();com_ptr<IInspectable> inspectable;
 check_hresult(CreateDirect3D11DeviceFromDXGIDevice(dxgi.get(),inspectable.put()));
 auto device=inspectable.as<IDirect3DDevice>();
 GraphicsCaptureItem item{nullptr};
 auto factory=get_activation_factory<GraphicsCaptureItem,IGraphicsCaptureItemInterop>();
 check_hresult(factory->CreateForMonitor(monitor,guid_of<GraphicsCaptureItem>(),put_abi(item)));
 auto pool=Direct3D11CaptureFramePool::CreateFreeThreaded(device,DirectXPixelFormat::B8G8R8A8UIntNormalized,2,item.Size());
 auto session=pool.CreateCaptureSession(item);session.IsCursorCaptureEnabled(false);
 struct FrameState{std::mutex mutex;std::condition_variable cv;bool done=false;Image image;std::exception_ptr failure;};
 auto state=std::make_shared<FrameState>();
 auto token=pool.FrameArrived([state,d3d,ctx](auto const& sender,auto const&){
  std::lock_guard lock(state->mutex);if(state->done)return;
  auto& image=state->image;
  try{
   auto frame=sender.TryGetNextFrame();if(!frame)return;
   const auto size=frame.ContentSize();if(size.Width<=0||size.Height<=0)return;
   if(uint64_t(size.Width)*size.Height>160000000)throw std::runtime_error("Capture image is too large.");
   auto access=frame.Surface().template as<::Windows::Graphics::DirectX::Direct3D11::IDirect3DDxgiInterfaceAccess>();
   com_ptr<ID3D11Texture2D> texture;check_hresult(access->GetInterface(__uuidof(ID3D11Texture2D),texture.put_void()));
   D3D11_TEXTURE2D_DESC desc;texture->GetDesc(&desc);
   if(UINT(size.Width)>desc.Width||UINT(size.Height)>desc.Height)throw std::runtime_error("Display resized during capture; try again.");
   desc.Usage=D3D11_USAGE_STAGING;desc.BindFlags=0;desc.CPUAccessFlags=D3D11_CPU_ACCESS_READ;desc.MiscFlags=0;
   com_ptr<ID3D11Texture2D> staging;check_hresult(d3d->CreateTexture2D(&desc,nullptr,staging.put()));
   ctx->CopyResource(staging.get(),texture.get());
   D3D11_MAPPED_SUBRESOURCE mapped{};check_hresult(ctx->Map(staging.get(),0,D3D11_MAP_READ,0,&mapped));
   try{
    image.width=size.Width;image.height=size.Height;image.bgra.resize(size_t(image.width)*image.height*4);
    for(int y=0;y<image.height;y++)std::memcpy(image.bgra.data()+size_t(y)*image.width*4,static_cast<uint8_t*>(mapped.pData)+size_t(y)*mapped.RowPitch,size_t(image.width)*4);
   }catch(...){ctx->Unmap(staging.get(),0);throw;}
   ctx->Unmap(staging.get(),0);frame.Close();
  }catch(...){state->failure=std::current_exception();}
  state->done=true;state->cv.notify_one();
 });
 session.StartCapture();
 bool timedOut=false;
 {std::unique_lock lock(state->mutex);timedOut=!state->cv.wait_for(lock,std::chrono::seconds(5),[&]{return state->done;});if(timedOut)state->done=true;}
 pool.FrameArrived(token);session.Close();pool.Close();
 if(timedOut)throw std::runtime_error("Capture timed out. Check protected content, screen state and system permissions.");
 if(state->failure)std::rethrow_exception(state->failure);return std::move(state->image);
}
Desktop captureDesktop(){
 auto start=std::chrono::steady_clock::now();init_apartment(apartment_type::multi_threaded);
 struct Monitor{HMONITOR handle;RECT bounds;};std::vector<Monitor> monitors;
 EnumDisplayMonitors(nullptr,nullptr,[](HMONITOR m,HDC,LPRECT r,LPARAM data)->BOOL{reinterpret_cast<std::vector<Monitor>*>(data)->push_back({m,*r});return TRUE;},reinterpret_cast<LPARAM>(&monitors));
 if(monitors.empty())throw std::runtime_error("No displays are available.");
 Desktop out;out.bounds=monitors[0].bounds;
 for(auto& m:monitors){out.bounds.left=std::min(out.bounds.left,m.bounds.left);out.bounds.top=std::min(out.bounds.top,m.bounds.top);out.bounds.right=std::max(out.bounds.right,m.bounds.right);out.bounds.bottom=std::max(out.bounds.bottom,m.bounds.bottom);}
 out.image.width=out.bounds.right-out.bounds.left;out.image.height=out.bounds.bottom-out.bounds.top;
 if(uint64_t(out.image.width)*out.image.height>160000000)throw std::runtime_error("Virtual desktop exceeds the image memory limit.");
 out.image.bgra.resize(size_t(out.image.width)*out.image.height*4,0);
 for(auto& m:monitors){
  auto image=monitorImage(m.handle);
  if(image.width!=m.bounds.right-m.bounds.left||image.height!=m.bounds.bottom-m.bounds.top)throw std::runtime_error("Display geometry changed or unsupported capture scaling. Try again.");
  for(int y=0;y<image.height;y++)std::memcpy(out.image.bgra.data()+(size_t(m.bounds.top-out.bounds.top+y)*out.image.width+m.bounds.left-out.bounds.left)*4,image.bgra.data()+size_t(y)*image.width*4,size_t(image.width)*4);
 }
 out.captureMs=std::chrono::duration<double,std::milli>(std::chrono::steady_clock::now()-start).count();return out;
}
Image cropImage(const Image& source,RECT rect){
 rect.left=std::clamp<LONG>(rect.left,0,source.width);rect.right=std::clamp<LONG>(rect.right,0,source.width);rect.top=std::clamp<LONG>(rect.top,0,source.height);rect.bottom=std::clamp<LONG>(rect.bottom,0,source.height);
 Image out;out.width=rect.right-rect.left;out.height=rect.bottom-rect.top;
 if(out.width<=0||out.height<=0)throw std::runtime_error("Select a region first.");
 out.bgra.resize(size_t(out.width)*out.height*4);
 for(int y=0;y<out.height;y++)std::memcpy(out.bgra.data()+size_t(y)*out.width*4,source.bgra.data()+(size_t(y+rect.top)*source.width+rect.left)*4,size_t(out.width)*4);
 for(size_t i=3;i<out.bgra.size();i+=4)out.bgra[i]=255;
 return out;
}
std::vector<uint8_t> encodePNG(const Image& image){
 auto factory=create_instance<IWICImagingFactory>(CLSID_WICImagingFactory);
 com_ptr<IStream> stream;check_hresult(CreateStreamOnHGlobal(nullptr,TRUE,stream.put()));
 com_ptr<IWICBitmapEncoder> encoder;check_hresult(factory->CreateEncoder(GUID_ContainerFormatPng,nullptr,encoder.put()));
 check_hresult(encoder->Initialize(stream.get(),WICBitmapEncoderNoCache));
 com_ptr<IWICBitmapFrameEncode> frame;check_hresult(encoder->CreateNewFrame(frame.put(),nullptr));check_hresult(frame->Initialize(nullptr));
 check_hresult(frame->SetSize(image.width,image.height));auto format=GUID_WICPixelFormat32bppBGRA;
 check_hresult(frame->SetPixelFormat(&format));if(format!=GUID_WICPixelFormat32bppBGRA)throw std::runtime_error("PNG pixel format unsupported.");
 check_hresult(frame->WritePixels(image.height,image.width*4,static_cast<UINT>(image.bgra.size()),const_cast<BYTE*>(image.bgra.data())));
 check_hresult(frame->Commit());check_hresult(encoder->Commit());
 STATSTG stat{};check_hresult(stream->Stat(&stat,STATFLAG_NONAME));HGLOBAL memory;check_hresult(GetHGlobalFromStream(stream.get(),&memory));
 auto data=static_cast<uint8_t*>(GlobalLock(memory));if(!data)throw std::runtime_error("PNG memory unavailable.");
 std::vector<uint8_t> png(data,data+static_cast<size_t>(stat.cbSize.QuadPart));GlobalUnlock(memory);return png;
}
void copyImage(HWND owner,const Image& image){
 auto png=encodePNG(image);
 auto dib=GlobalAlloc(GMEM_MOVEABLE,sizeof(BITMAPV5HEADER)+image.bgra.size());
 auto encoded=GlobalAlloc(GMEM_MOVEABLE,png.size());
 if(!dib||!encoded){if(dib)GlobalFree(dib);if(encoded)GlobalFree(encoded);throw std::runtime_error("Clipboard allocation failed.");}
 auto h=static_cast<BITMAPV5HEADER*>(GlobalLock(dib));ZeroMemory(h,sizeof(*h));h->bV5Size=sizeof(*h);h->bV5Width=image.width;h->bV5Height=-image.height;h->bV5Planes=1;h->bV5BitCount=32;h->bV5Compression=BI_BITFIELDS;
 h->bV5RedMask=0x00ff0000;h->bV5GreenMask=0x0000ff00;h->bV5BlueMask=0x000000ff;h->bV5AlphaMask=0xff000000;h->bV5CSType=LCS_sRGB;
 std::memcpy(h+1,image.bgra.data(),image.bgra.size());GlobalUnlock(dib);
 auto data=GlobalLock(encoded);std::memcpy(data,png.data(),png.size());GlobalUnlock(encoded);
 if(!OpenClipboard(owner)){GlobalFree(dib);GlobalFree(encoded);throw std::runtime_error("Clipboard is busy. Try again.");}
 EmptyClipboard();bool ok=SetClipboardData(CF_DIBV5,dib)!=nullptr;if(!ok)GlobalFree(dib);
 bool pngOK=SetClipboardData(RegisterClipboardFormat(L"PNG"),encoded)!=nullptr;if(!pngOK)GlobalFree(encoded);CloseClipboard();
 if(!ok&&!pngOK)throw std::runtime_error("Clipboard write failed.");
}
void saveImage(const Image& image,const std::wstring& path,bool overwrite){
 auto png=encodePNG(image);GUID id;check_hresult(CoCreateGuid(&id));wchar_t guid[40];StringFromGUID2(id,guid,40);
 auto temp=path+L"."+guid+L".tmp";
 auto file=CreateFile(temp.c_str(),GENERIC_WRITE,0,nullptr,CREATE_NEW,FILE_ATTRIBUTE_NORMAL,nullptr);
 if(file==INVALID_HANDLE_VALUE)throw hresult_error(HRESULT_FROM_WIN32(GetLastError()));
 DWORD written=0;bool ok=WriteFile(file,png.data(),static_cast<DWORD>(png.size()),&written,nullptr)&&written==png.size();
 if(ok)ok=FlushFileBuffers(file)!=FALSE;CloseHandle(file);
 if(!ok){DeleteFile(temp.c_str());throw std::runtime_error("File write failed. Check disk space and access.");}
 if(!MoveFileEx(temp.c_str(),path.c_str(),MOVEFILE_WRITE_THROUGH|(overwrite?MOVEFILE_REPLACE_EXISTING:0))){auto error=GetLastError();DeleteFile(temp.c_str());throw hresult_error(HRESULT_FROM_WIN32(error));}
}
