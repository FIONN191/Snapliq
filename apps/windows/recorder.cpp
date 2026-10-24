#include "recorder.h"
#include "recorder-video.h"
#include <winrt/base.h>
#include <winrt/Windows.Foundation.h>
#include <winrt/Windows.Graphics.Capture.h>
#include <winrt/Windows.Graphics.DirectX.h>
#include <winrt/Windows.Graphics.DirectX.Direct3D11.h>
#include <windows.graphics.capture.interop.h>
#include <windows.graphics.directx.direct3d11.interop.h>
#include <d3d11.h>
#include <dxgi.h>
#include <mfapi.h>
#include <mfidl.h>
#include <mfreadwrite.h>
#include <mmdeviceapi.h>
#include <audioclient.h>
#include <ksmedia.h>
#include <vector>
#include <array>
#include <algorithm>
#include <cmath>
#include <cstring>
#include <optional>
#include <memory>
#include <stdexcept>
using namespace winrt;
using namespace winrt::Windows::Graphics::Capture;
using namespace winrt::Windows::Graphics::DirectX;
using namespace winrt::Windows::Graphics::DirectX::Direct3D11;
namespace {
constexpr int64_t mediaTicksPerSecond=10000000;
constexpr int audioSampleRate=48000;
// Divide first so long recordings do not overflow an intermediate product.
constexpr int64_t audioFramesToTicks(int64_t frames){
 return (frames/audioSampleRate)*mediaTicksPerSecond+(frames%audioSampleRate)*mediaTicksPerSecond/audioSampleRate;
}
constexpr int64_t mediaTicksToAudioFrames(int64_t ticks){
 return (ticks/mediaTicksPerSecond)*audioSampleRate+(ticks%mediaTicksPerSecond)*audioSampleRate/mediaTicksPerSecond;
}
static_assert(audioFramesToTicks(480)==100000,"480 audio frames at 48 kHz must last exactly 10 ms");
static_assert(mediaTicksToAudioFrames(100000)==480);
static_assert(audioFramesToTicks(48000)==10000000);
static_assert(audioFramesToTicks(48000LL*60*60*24*365)==10000000LL*60*60*24*365);
static_assert(mediaTicksToAudioFrames(10000000LL*60*60*24*365)==48000LL*60*60*24*365);
int64_t hostTime(){LARGE_INTEGER q,f;QueryPerformanceCounter(&q);QueryPerformanceFrequency(&f);return int64_t(double(q.QuadPart)*10000000.0/double(f.QuadPart));}
struct Apartment {Apartment(){init_apartment(apartment_type::multi_threaded);}~Apartment(){uninit_apartment();}};
struct Foundation {
 Foundation(){const auto hr=MFStartup(MF_VERSION);if(FAILED(hr))throw hresult_error(hr,L"无法启动 Windows 媒体组件。Windows N/KN 请在系统可选功能中安装 Media Feature Pack 并重启。其他版本请检查系统媒体组件是否被禁用。");}
 ~Foundation(){MFShutdown();}
};
void appendMessage(RecordingOutcome& outcome,const std::wstring& message){if(!outcome.message.empty())outcome.message+=L"\n";outcome.message+=message;}
template<class F> void finishStep(RecordingOutcome& outcome,const wchar_t* label,F step){
 try{step();}catch(const hresult_error& e){appendMessage(outcome,std::wstring(label)+L"："+e.message().c_str());}
 catch(const std::exception& e){std::string text=e.what();appendMessage(outcome,std::wstring(label)+L"："+std::wstring(text.begin(),text.end()));}
}
struct MappedTexture {
 ID3D11DeviceContext* context;ID3D11Texture2D* texture;D3D11_MAPPED_SUBRESOURCE data{};
 MappedTexture(ID3D11DeviceContext* owner,ID3D11Texture2D* source):context(owner),texture(source){check_hresult(context->Map(texture,0,D3D11_MAP_READ,0,&data));}
 ~MappedTexture(){context->Unmap(texture,0);}
};
struct AudioSource {
 com_ptr<IAudioClient> client;com_ptr<IAudioCaptureClient> capture;WAVEFORMATEX* format=nullptr;bool floating=false;
 ~AudioSource(){if(client)client->Stop();if(format)CoTaskMemFree(format);}
 void start(bool loopback){
  auto devices=create_instance<IMMDeviceEnumerator>(__uuidof(MMDeviceEnumerator));
  com_ptr<IMMDevice> device;check_hresult(devices->GetDefaultAudioEndpoint(loopback?eRender:eCapture,eConsole,device.put()));
  check_hresult(device->Activate(__uuidof(IAudioClient),CLSCTX_ALL,nullptr,client.put_void()));
  check_hresult(client->GetMixFormat(&format));
  floating=format->wFormatTag==WAVE_FORMAT_IEEE_FLOAT;
  if(format->wFormatTag==WAVE_FORMAT_EXTENSIBLE){auto ex=reinterpret_cast<WAVEFORMATEXTENSIBLE*>(format);floating=ex->SubFormat==KSDATAFORMAT_SUBTYPE_IEEE_FLOAT;}
  if((floating&&format->wBitsPerSample!=32)||(!floating&&format->wBitsPerSample!=16&&format->wBitsPerSample!=24&&format->wBitsPerSample!=32))throw std::runtime_error("Unsupported audio device format.");
  check_hresult(client->Initialize(AUDCLNT_SHAREMODE_SHARED,loopback?AUDCLNT_STREAMFLAGS_LOOPBACK:0,1000000,0,format,nullptr));
  check_hresult(client->GetService(__uuidof(IAudioCaptureClient),capture.put_void()));check_hresult(client->Start());
 }
 float value(const BYTE* p)const{
  if(floating){float f;std::memcpy(&f,p,4);return std::isfinite(f)?std::clamp(f,-1.f,1.f):0.f;}
  if(format->wBitsPerSample==16){int16_t v;std::memcpy(&v,p,2);return float(v)/32768.f;}
  if(format->wBitsPerSample==24){int32_t v=int32_t(p[0])|(int32_t(p[1])<<8)|(int32_t(p[2])<<16);if(v&0x800000)v|=int32_t(0xff000000);return float(v)/8388608.f;}
  int32_t v;std::memcpy(&v,p,4);return float(double(v)/2147483648.0);
 }
 template<class F> void drain(F consume){
  UINT32 available=0;check_hresult(capture->GetNextPacketSize(&available));
  while(available){
   BYTE* data=nullptr;UINT32 frames=0;DWORD flags=0;UINT64 position=0,qpc=0;
   check_hresult(capture->GetBuffer(&data,&frames,&flags,&position,&qpc));
   try{consume(data,frames,flags,static_cast<int64_t>(qpc),*this);}catch(...){capture->ReleaseBuffer(frames);throw;}
   check_hresult(capture->ReleaseBuffer(frames));check_hresult(capture->GetNextPacketSize(&available));
  }
 }
};
struct Mixer {
 static constexpr int rate=audioSampleRate,capacity=96000,block=480;
 static constexpr int64_t blockDuration=audioFramesToTicks(block);
 static_assert(blockDuration==100000);
 std::vector<std::array<float,2>> ring=std::vector<std::array<float,2>>(capacity);
 int64_t next=0,dropped=0;
 void add(const BYTE* bytes,UINT32 count,DWORD flags,int64_t timestamp,const AudioSource& input,int64_t origin,int64_t offset,float gain){
  if(flags&AUDCLNT_BUFFERFLAGS_TIMESTAMP_ERROR){dropped+=count;return;}
  auto base=static_cast<int64_t>(std::llround(double(timestamp-origin-offset)*rate/10000000.0));
  auto outputFrames=static_cast<int64_t>(double(count)*rate/input.format->nSamplesPerSec);
  for(int64_t i=0;i<outputFrames;i++){
   int64_t index=base+i;if(index<next||index>=next+capacity){dropped++;continue;}
   if(flags&AUDCLNT_BUFFERFLAGS_SILENT)continue;
   auto source=std::min<UINT32>(count-1,UINT32(i*input.format->nSamplesPerSec/rate));
   auto data=bytes+size_t(source)*input.format->nBlockAlign;
   const int step=input.format->wBitsPerSample/8;
   auto& slot=ring[size_t(index%capacity)];
   slot[0]+=input.value(data)*gain;slot[1]+=input.value(data+(input.format->nChannels>1?step:0))*gain;
  }
 }
 void writeUntil(IMFSinkWriter* writer,DWORD stream,int64_t frames){
  while(next+block<=frames){
   com_ptr<IMFMediaBuffer> buffer;check_hresult(MFCreateMemoryBuffer(block*4,buffer.put()));
   BYTE* data;check_hresult(buffer->Lock(&data,nullptr,nullptr));
   for(int i=0;i<block;i++){auto& slot=ring[size_t((next+i)%capacity)];for(int c=0;c<2;c++){auto sample=int16_t(std::clamp(slot[c],-1.f,1.f)*32767.f);std::memcpy(data+(i*2+c)*2,&sample,2);}slot={0,0};}
   buffer->Unlock();buffer->SetCurrentLength(block*4);
   com_ptr<IMFSample> sample;check_hresult(MFCreateSample(sample.put()));sample->AddBuffer(buffer.get());check_hresult(sample->SetSampleTime(audioFramesToTicks(next)));check_hresult(sample->SetSampleDuration(blockDuration));
   check_hresult(writer->WriteSample(stream,sample.get()));next+=block;
  }
 }
};
}
void DesktopRecorder::start(RecordingOptions options,std::function<void(RecordingOutcome)> done){
 if(active_.exchange(true))throw std::runtime_error("Recording is already active.");join();stop_=false;paused_=false;started_=false;elapsed_=0;
 try{worker_=std::thread([this,options,done]{
  RecordingOutcome result;std::wstring temp;
  try {
   Apartment apartment;Foundation foundation;
   GUID guid;check_hresult(CoCreateGuid(&guid));wchar_t id[40];StringFromGUID2(guid,id,40);temp=options.path+L"."+id+L".partial.mp4";
   if(!GraphicsCaptureSession::IsSupported())throw hresult_error(E_NOTIMPL,L"Windows 屏幕捕获不可用。需要 Windows 10 2004（19041）或更新版本，以及可用的图形设备和用户桌面会话。");
   com_ptr<ID3D11Device> d3d;com_ptr<ID3D11DeviceContext> context;
   check_hresult(D3D11CreateDevice(nullptr,D3D_DRIVER_TYPE_HARDWARE,nullptr,D3D11_CREATE_DEVICE_BGRA_SUPPORT,nullptr,0,D3D11_SDK_VERSION,d3d.put(),nullptr,context.put()));
   com_ptr<IInspectable> native;check_hresult(CreateDirect3D11DeviceFromDXGIDevice(d3d.as<IDXGIDevice>().get(),native.put()));
   auto device=native.as<IDirect3DDevice>();auto factory=get_activation_factory<GraphicsCaptureItem,IGraphicsCaptureItemInterop>();
   GraphicsCaptureItem item{nullptr};
   if(options.window)check_hresult(factory->CreateForWindow(options.window,guid_of<GraphicsCaptureItem>(),put_abi(item)));
   else check_hresult(factory->CreateForMonitor(options.monitor,guid_of<GraphicsCaptureItem>(),put_abi(item)));
   const auto size=item.Size();const int width=size.Width/2*2,height=size.Height/2*2;
   if(width<=0||height<=0||uint64_t(width)*height>40000000)throw std::runtime_error("Unsupported recording dimensions.");
   auto writer=snapliq::recording::makeMP4Writer(temp);
   DWORD videoStream=0;
   try{videoStream=snapliq::recording::addVideoStream(writer.get(),width,height);}
   catch(const hresult_error& e){throw hresult_error(e.code(),L"无法为 "+std::to_wstring(width)+L" × "+std::to_wstring(height)+L" 屏幕创建 H.264 编码器。请更新显卡驱动；若分辨率过高，可降低显示分辨率后重试。Windows N/KN 需要安装 Media Feature Pack。\n"+std::wstring(e.message().c_str()));}
   std::unique_ptr<AudioSource> system,mic;DWORD audioStream=0;Mixer mixer;
   if(options.systemAudio){
    system=std::make_unique<AudioSource>();
    try{system->start(true);}catch(const hresult_error& e){throw hresult_error(e.code(),L"无法录制系统声音，请检查默认播放设备，或在录屏设置中关闭系统声音。\n"+std::wstring(e.message().c_str()));}
   }
   if(options.microphone){
    mic=std::make_unique<AudioSource>();
    try{mic->start(false);}catch(const hresult_error& e){throw hresult_error(e.code(),L"无法录制麦克风，请检查默认输入设备和 Windows 麦克风隐私权限，或在录屏设置中关闭麦克风。\n"+std::wstring(e.message().c_str()));}
   }
   if(system||mic){
    com_ptr<IMFMediaType> out;MFCreateMediaType(out.put());out->SetGUID(MF_MT_MAJOR_TYPE,MFMediaType_Audio);out->SetGUID(MF_MT_SUBTYPE,MFAudioFormat_AAC);
    out->SetUINT32(MF_MT_AUDIO_NUM_CHANNELS,2);out->SetUINT32(MF_MT_AUDIO_SAMPLES_PER_SECOND,48000);out->SetUINT32(MF_MT_AUDIO_BITS_PER_SAMPLE,16);out->SetUINT32(MF_MT_AUDIO_AVG_BYTES_PER_SECOND,20000);
    check_hresult(writer->AddStream(out.get(),&audioStream));
    com_ptr<IMFMediaType> in;MFCreateMediaType(in.put());in->SetGUID(MF_MT_MAJOR_TYPE,MFMediaType_Audio);in->SetGUID(MF_MT_SUBTYPE,MFAudioFormat_PCM);
    in->SetUINT32(MF_MT_AUDIO_NUM_CHANNELS,2);in->SetUINT32(MF_MT_AUDIO_SAMPLES_PER_SECOND,48000);in->SetUINT32(MF_MT_AUDIO_BITS_PER_SAMPLE,16);
    in->SetUINT32(MF_MT_AUDIO_BLOCK_ALIGNMENT,4);in->SetUINT32(MF_MT_AUDIO_AVG_BYTES_PER_SECOND,192000);
    check_hresult(writer->SetInputMediaType(audioStream,in.get(),nullptr));
   }
   try{check_hresult(writer->BeginWriting());}catch(const hresult_error& e){throw hresult_error(e.code(),L"无法启动 MP4 编码器。请检查保存位置权限、剩余空间和 Windows 媒体组件；Windows N/KN 需要安装 Media Feature Pack。\n"+std::wstring(e.message().c_str()));}
   auto pool=Direct3D11CaptureFramePool::CreateFreeThreaded(device,DirectXPixelFormat::B8G8R8A8UIntNormalized,2,size);
   auto session=pool.CreateCaptureSession(item);session.IsCursorCaptureEnabled(true);
   std::optional<int64_t> origin;int64_t offset=0,pauseStarted=0,lastWritten=-1;bool wasPaused=false;com_ptr<IMFMediaBuffer> lastBuffer;
   auto closed=std::make_shared<std::atomic<bool>>(false);auto closedToken=item.Closed([closed](auto const&,auto const&){*closed=true;});
   const auto started=GetTickCount64();
   com_ptr<ID3D11Texture2D> staging;session.StartCapture();
   try{
    while(!stop_){
     const bool paused=paused_;const auto clock=hostTime();
     if(paused&&!wasPaused){pauseStarted=clock;wasPaused=true;}
     if(!paused&&wasPaused){if(origin)offset+=std::max<int64_t>(0,clock-pauseStarted);wasPaused=false;}
     if(origin)elapsed_=std::max<int64_t>(0,(paused?pauseStarted:clock)-*origin-offset);
     if(closed->load()){result.message=L"Capture source closed; saved available recording.";break;}
     if(!origin&&GetTickCount64()-started>10000)throw std::runtime_error("Timed out waiting for the first capture frame.");
     if(options.window&&!IsWindow(options.window)){result.message=L"Source window closed; saved available recording.";break;}
     auto frame=pool.TryGetNextFrame();
     if(frame){
      auto actual=frame.ContentSize();if(actual.Width!=size.Width||actual.Height!=size.Height){result.message=L"Source size changed; recording stopped.";break;}
      const int64_t raw=frame.SystemRelativeTime().count();
      if(!paused){
       if(!origin)origin=raw;
       const int64_t time=raw-*origin-offset;
       if(time>=lastWritten+333333||lastWritten<0){
        auto access=frame.Surface().as<::Windows::Graphics::DirectX::Direct3D11::IDirect3DDxgiInterfaceAccess>();
        com_ptr<ID3D11Texture2D> texture;check_hresult(access->GetInterface(__uuidof(ID3D11Texture2D),texture.put_void()));
        D3D11_TEXTURE2D_DESC desc;texture->GetDesc(&desc);
        if(!staging){desc.Usage=D3D11_USAGE_STAGING;desc.BindFlags=0;desc.MiscFlags=0;desc.CPUAccessFlags=D3D11_CPU_ACCESS_READ;check_hresult(d3d->CreateTexture2D(&desc,nullptr,staging.put()));}
        context->CopyResource(staging.get(),texture.get());
        com_ptr<IMFMediaBuffer> buffer;
        {MappedTexture mapped(context.get(),staging.get());buffer=snapliq::recording::copyBGRAFrame(static_cast<const BYTE*>(mapped.data.pData),mapped.data.RowPitch,width,height);}
        snapliq::recording::writeVideoSample(writer.get(),videoStream,buffer.get(),time,snapliq::recording::videoFrameDuration);lastWritten=time;lastBuffer=buffer;result.frames++;started_=true;
       }
      };frame.Close();
     }
     for(auto source:{system.get(),mic.get()})if(source)source->drain([&](const BYTE* b,UINT32 n,DWORD flags,int64_t timestamp,const AudioSource& input){
      if(!paused&&!wasPaused&&origin)mixer.add(b,n,flags,timestamp,input,*origin,offset,system&&mic?0.7f:1.f);
     });
     if((system||mic)&&origin&&!paused)mixer.writeUntil(writer.get(),audioStream,mediaTicksToAudioFrames(std::max<int64_t>(0,elapsed_.load()-1000000)));
     Sleep(4);
    }
   }catch(const hresult_error& e){result.message=e.message().c_str();}catch(const std::exception& e){std::string text=e.what();result.message.assign(text.begin(),text.end());}
   stop_=true;
   // A device disappearing during stop must not bypass MP4 finalization.
   finishStep(result,L"释放捕获事件失败",[&]{item.Closed(closedToken);});
   finishStep(result,L"停止屏幕捕获失败",[&]{session.Close();});
   finishStep(result,L"释放捕获缓冲失败",[&]{pool.Close();});
   system.reset();mic.reset();
   if(result.frames==0)throw std::runtime_error("No video frames captured.");
   finishStep(result,L"写入视频结束帧失败",[&]{if(snapliq::recording::writeVideoTail(writer.get(),videoStream,lastBuffer.get(),elapsed_.load(),lastWritten))result.frames++;});lastBuffer=nullptr;
   // Preserve captured video even if an audio device/encoder fails at stop.
   if(options.systemAudio||options.microphone)finishStep(result,L"写入剩余声音失败",[&]{mixer.writeUntil(writer.get(),audioStream,mediaTicksToAudioFrames(lastWritten+snapliq::recording::videoFrameDuration));});
   check_hresult(writer->Finalize());writer=nullptr;result.droppedAudio=mixer.dropped;
   if(!MoveFileEx(temp.c_str(),options.path.c_str(),MOVEFILE_WRITE_THROUGH))throw hresult_error(HRESULT_FROM_WIN32(GetLastError()));
   result.saved=true;result.path=options.path;
  }catch(const hresult_error& e){appendMessage(result,e.message().c_str());}catch(const std::exception& e){std::string text=e.what();appendMessage(result,std::wstring(text.begin(),text.end()));}
  if(!result.saved&&!temp.empty()){
   if(result.frames==0){DeleteFile(temp.c_str());}
   else result.message+=L"\nPartial file (may be incomplete): "+temp;
  }
  active_=false;done(std::move(result));
 });}catch(...){active_=false;throw;}
}
