#include "recorder.h"
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
int64_t hostTime(){LARGE_INTEGER q,f;QueryPerformanceCounter(&q);QueryPerformanceFrequency(&f);return int64_t(double(q.QuadPart)*10000000.0/double(f.QuadPart));}
struct Apartment {Apartment(){init_apartment(apartment_type::multi_threaded);}~Apartment(){uninit_apartment();}};
struct Foundation {Foundation(){check_hresult(MFStartup(MF_VERSION));}~Foundation(){MFShutdown();}};
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
 static constexpr int rate=48000,capacity=96000,block=480;
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
   com_ptr<IMFSample> sample;check_hresult(MFCreateSample(sample.put()));sample->AddBuffer(buffer.get());sample->SetSampleTime(next*10000000/rate);sample->SetSampleDuration(block*10000000/rate);
   check_hresult(writer->WriteSample(stream,sample.get()));next+=block;
  }
 }
};
}
void DesktopRecorder::start(RecordingOptions options,std::function<void(RecordingOutcome)> done){
 if(active_.exchange(true))throw std::runtime_error("Recording is already active.");join();stop_=false;paused_=false;started_=false;elapsed_=0;
 worker_=std::thread([this,options,done]{
  RecordingOutcome result;std::wstring temp;
  try {
   Apartment apartment;Foundation foundation;
   GUID guid;check_hresult(CoCreateGuid(&guid));wchar_t id[40];StringFromGUID2(guid,id,40);temp=options.path+L"."+id+L".partial.mp4";
   if(!GraphicsCaptureSession::IsSupported())throw std::runtime_error("Windows Graphics Capture is unavailable.");
   com_ptr<ID3D11Device> d3d;com_ptr<ID3D11DeviceContext> context;
   check_hresult(D3D11CreateDevice(nullptr,D3D_DRIVER_TYPE_HARDWARE,nullptr,D3D11_CREATE_DEVICE_BGRA_SUPPORT,nullptr,0,D3D11_SDK_VERSION,d3d.put(),nullptr,context.put()));
   com_ptr<IInspectable> native;check_hresult(CreateDirect3D11DeviceFromDXGIDevice(d3d.as<IDXGIDevice>().get(),native.put()));
   auto device=native.as<IDirect3DDevice>();auto factory=get_activation_factory<GraphicsCaptureItem,IGraphicsCaptureItemInterop>();
   GraphicsCaptureItem item{nullptr};
   if(options.window)check_hresult(factory->CreateForWindow(options.window,guid_of<GraphicsCaptureItem>(),put_abi(item)));
   else check_hresult(factory->CreateForMonitor(options.monitor,guid_of<GraphicsCaptureItem>(),put_abi(item)));
   const auto size=item.Size();const int width=size.Width/2*2,height=size.Height/2*2;
   if(width<=0||height<=0||uint64_t(width)*height>40000000)throw std::runtime_error("Unsupported recording dimensions.");
   com_ptr<IMFAttributes> attributes;check_hresult(MFCreateAttributes(attributes.put(),2));attributes->SetUINT32(MF_READWRITE_ENABLE_HARDWARE_TRANSFORMS,TRUE);
   com_ptr<IMFSinkWriter> writer;check_hresult(MFCreateSinkWriterFromURL(temp.c_str(),nullptr,attributes.get(),writer.put()));
   com_ptr<IMFMediaType> videoOut;MFCreateMediaType(videoOut.put());videoOut->SetGUID(MF_MT_MAJOR_TYPE,MFMediaType_Video);videoOut->SetGUID(MF_MT_SUBTYPE,MFVideoFormat_H264);
   videoOut->SetUINT32(MF_MT_AVG_BITRATE,std::min(24000000,std::max(4000000,width*height*5)));videoOut->SetUINT32(MF_MT_INTERLACE_MODE,MFVideoInterlace_Progressive);
   MFSetAttributeSize(videoOut.get(),MF_MT_FRAME_SIZE,width,height);MFSetAttributeRatio(videoOut.get(),MF_MT_FRAME_RATE,30,1);MFSetAttributeRatio(videoOut.get(),MF_MT_PIXEL_ASPECT_RATIO,1,1);
   DWORD videoStream;check_hresult(writer->AddStream(videoOut.get(),&videoStream));
   com_ptr<IMFMediaType> videoIn;MFCreateMediaType(videoIn.put());videoOut->CopyAllItems(videoIn.get());videoIn->SetGUID(MF_MT_SUBTYPE,MFVideoFormat_RGB32);videoIn->SetUINT32(MF_MT_DEFAULT_STRIDE,width*4);
   check_hresult(writer->SetInputMediaType(videoStream,videoIn.get(),nullptr));
   std::unique_ptr<AudioSource> system,mic;DWORD audioStream=0;Mixer mixer;
   if(options.systemAudio){system=std::make_unique<AudioSource>();system->start(true);}
   if(options.microphone){mic=std::make_unique<AudioSource>();mic->start(false);}
   if(system||mic){
    com_ptr<IMFMediaType> out;MFCreateMediaType(out.put());out->SetGUID(MF_MT_MAJOR_TYPE,MFMediaType_Audio);out->SetGUID(MF_MT_SUBTYPE,MFAudioFormat_AAC);
    out->SetUINT32(MF_MT_AUDIO_NUM_CHANNELS,2);out->SetUINT32(MF_MT_AUDIO_SAMPLES_PER_SECOND,48000);out->SetUINT32(MF_MT_AUDIO_BITS_PER_SAMPLE,16);out->SetUINT32(MF_MT_AUDIO_AVG_BYTES_PER_SECOND,20000);
    check_hresult(writer->AddStream(out.get(),&audioStream));
    com_ptr<IMFMediaType> in;MFCreateMediaType(in.put());in->SetGUID(MF_MT_MAJOR_TYPE,MFMediaType_Audio);in->SetGUID(MF_MT_SUBTYPE,MFAudioFormat_PCM);
    in->SetUINT32(MF_MT_AUDIO_NUM_CHANNELS,2);in->SetUINT32(MF_MT_AUDIO_SAMPLES_PER_SECOND,48000);in->SetUINT32(MF_MT_AUDIO_BITS_PER_SAMPLE,16);
    in->SetUINT32(MF_MT_AUDIO_BLOCK_ALIGNMENT,4);in->SetUINT32(MF_MT_AUDIO_AVG_BYTES_PER_SECOND,192000);
    check_hresult(writer->SetInputMediaType(audioStream,in.get(),nullptr));
   }
   check_hresult(writer->BeginWriting());
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
        context->CopyResource(staging.get(),texture.get());D3D11_MAPPED_SUBRESOURCE mapped;check_hresult(context->Map(staging.get(),0,D3D11_MAP_READ,0,&mapped));
        com_ptr<IMFMediaBuffer> buffer;HRESULT created=MFCreateMemoryBuffer(width*height*4,buffer.put());if(FAILED(created)){context->Unmap(staging.get(),0);check_hresult(created);}
        BYTE* data;HRESULT locked=buffer->Lock(&data,nullptr,nullptr);if(FAILED(locked)){context->Unmap(staging.get(),0);check_hresult(locked);}
        for(int y=0;y<height;y++)std::memcpy(data+size_t(y)*width*4,static_cast<BYTE*>(mapped.pData)+size_t(y)*mapped.RowPitch,width*4);
        context->Unmap(staging.get(),0);buffer->Unlock();buffer->SetCurrentLength(width*height*4);
        com_ptr<IMFSample> sample;MFCreateSample(sample.put());sample->AddBuffer(buffer.get());sample->SetSampleTime(time);sample->SetSampleDuration(333333);
        check_hresult(writer->WriteSample(videoStream,sample.get()));lastWritten=time;lastBuffer=buffer;result.frames++;started_=true;
       }
      };frame.Close();
     }
     for(auto source:{system.get(),mic.get()})if(source)source->drain([&](const BYTE* b,UINT32 n,DWORD flags,int64_t timestamp,const AudioSource& input){
      if(!paused&&!wasPaused&&origin)mixer.add(b,n,flags,timestamp,input,*origin,offset,system&&mic?0.7f:1.f);
     });
     if((system||mic)&&origin&&!paused)mixer.writeUntil(writer.get(),audioStream,std::max<int64_t>(0,(elapsed_.load()-1000000)*48000/10000000));
     Sleep(4);
    }
   }catch(const hresult_error& e){result.message=e.message().c_str();}catch(const std::exception& e){std::string text=e.what();result.message.assign(text.begin(),text.end());}
   item.Closed(closedToken);session.Close();pool.Close();system.reset();mic.reset();
   if(result.frames==0)throw std::runtime_error("No video frames captured.");
   const auto duration=std::max<int64_t>(elapsed_.load(),lastWritten+333333);
   if(lastBuffer&&duration>lastWritten+666666){com_ptr<IMFSample> tail;check_hresult(MFCreateSample(tail.put()));tail->AddBuffer(lastBuffer.get());tail->SetSampleTime(duration-333333);tail->SetSampleDuration(333333);check_hresult(writer->WriteSample(videoStream,tail.get()));lastWritten=duration-333333;result.frames++;}lastBuffer=nullptr;
   if(options.systemAudio||options.microphone)mixer.writeUntil(writer.get(),audioStream,(lastWritten+333333)*48000/10000000);
   check_hresult(writer->Finalize());writer=nullptr;result.droppedAudio=mixer.dropped;
   if(!MoveFileEx(temp.c_str(),options.path.c_str(),MOVEFILE_REPLACE_EXISTING|MOVEFILE_WRITE_THROUGH))throw hresult_error(HRESULT_FROM_WIN32(GetLastError()));
   result.saved=true;
  }catch(const hresult_error& e){result.message=e.message().c_str();}catch(const std::exception& e){std::string text=e.what();result.message.assign(text.begin(),text.end());}
  if(!result.saved&&!temp.empty())result.message+=L"\nPartial file (may be incomplete): "+temp;
  active_=false;done(std::move(result));
 });
}
