#pragma once
#include <windows.h>
#include <winrt/base.h>
#include <mfapi.h>
#include <mfidl.h>
#include <mfreadwrite.h>
#include <algorithm>
#include <cstdint>
#include <cstring>

// Shared by the recorder and the native encode/decode smoke test. Pixel rows
// copied from a D3D texture stay top-down; MF_MT_DEFAULT_STRIDE is positive.
// https://learn.microsoft.com/windows/win32/medfound/mf-mt-default-stride-attribute
namespace snapliq::recording {
inline constexpr int64_t videoFrameDuration = 10000000 / 30;

inline winrt::com_ptr<IMFSinkWriter> makeMP4Writer(const std::wstring& path) {
 winrt::com_ptr<IMFAttributes> attributes;
 winrt::check_hresult(MFCreateAttributes(attributes.put(), 1));
 winrt::check_hresult(attributes->SetUINT32(MF_READWRITE_ENABLE_HARDWARE_TRANSFORMS, TRUE));
 winrt::com_ptr<IMFSinkWriter> writer;
 winrt::check_hresult(MFCreateSinkWriterFromURL(path.c_str(), nullptr, attributes.get(), writer.put()));
 return writer;
}

inline DWORD addVideoStream(IMFSinkWriter* writer, int width, int height) {
 if (!writer || width <= 0 || height <= 0 || width % 2 || height % 2 ||
     uint64_t(width) * uint64_t(height) > 40000000) winrt::throw_hresult(E_INVALIDARG);
 winrt::com_ptr<IMFMediaType> output;
 winrt::check_hresult(MFCreateMediaType(output.put()));
 winrt::check_hresult(output->SetGUID(MF_MT_MAJOR_TYPE, MFMediaType_Video));
 winrt::check_hresult(output->SetGUID(MF_MT_SUBTYPE, MFVideoFormat_H264));
 winrt::check_hresult(output->SetUINT32(MF_MT_AVG_BITRATE, std::clamp(width * height * 5, 4000000, 24000000)));
 winrt::check_hresult(output->SetUINT32(MF_MT_INTERLACE_MODE, MFVideoInterlace_Progressive));
 winrt::check_hresult(MFSetAttributeSize(output.get(), MF_MT_FRAME_SIZE, width, height));
 winrt::check_hresult(MFSetAttributeRatio(output.get(), MF_MT_FRAME_RATE, 30, 1));
 winrt::check_hresult(MFSetAttributeRatio(output.get(), MF_MT_PIXEL_ASPECT_RATIO, 1, 1));
 DWORD stream = 0;
 winrt::check_hresult(writer->AddStream(output.get(), &stream));
 winrt::com_ptr<IMFMediaType> input;
 winrt::check_hresult(MFCreateMediaType(input.put()));
 winrt::check_hresult(input->SetGUID(MF_MT_MAJOR_TYPE, MFMediaType_Video));
 winrt::check_hresult(input->SetGUID(MF_MT_SUBTYPE, MFVideoFormat_RGB32));
 winrt::check_hresult(input->SetUINT32(MF_MT_INTERLACE_MODE, MFVideoInterlace_Progressive));
 winrt::check_hresult(input->SetUINT32(MF_MT_DEFAULT_STRIDE, width * 4));
 winrt::check_hresult(MFSetAttributeSize(input.get(), MF_MT_FRAME_SIZE, width, height));
 winrt::check_hresult(MFSetAttributeRatio(input.get(), MF_MT_FRAME_RATE, 30, 1));
 winrt::check_hresult(MFSetAttributeRatio(input.get(), MF_MT_PIXEL_ASPECT_RATIO, 1, 1));
 winrt::check_hresult(writer->SetInputMediaType(stream, input.get(), nullptr));
 return stream;
}

inline winrt::com_ptr<IMFMediaBuffer> copyBGRAFrame(const BYTE* pixels, UINT sourceStride, int width, int height) {
 if (!pixels || width <= 0 || height <= 0 || uint64_t(width) * uint64_t(height) > 40000000 ||
     uint64_t(sourceStride) < uint64_t(width) * 4) winrt::throw_hresult(E_INVALIDARG);
 const DWORD rowBytes = static_cast<DWORD>(width) * 4;
 const DWORD bytes = rowBytes * static_cast<DWORD>(height);
 winrt::com_ptr<IMFMediaBuffer> buffer;
 winrt::check_hresult(MFCreateMemoryBuffer(bytes, buffer.put()));
 BYTE* target = nullptr;
 winrt::check_hresult(buffer->Lock(&target, nullptr, nullptr));
 for (int y = 0; y < height; ++y)
  std::memcpy(target + size_t(y) * rowBytes, pixels + size_t(y) * sourceStride, rowBytes);
 winrt::check_hresult(buffer->Unlock());
 winrt::check_hresult(buffer->SetCurrentLength(bytes));
 return buffer;
}

inline void writeVideoSample(IMFSinkWriter* writer, DWORD stream, IMFMediaBuffer* buffer, int64_t time, int64_t duration) {
 if (!writer || !buffer || time < 0 || duration <= 0) winrt::throw_hresult(E_INVALIDARG);
 winrt::com_ptr<IMFSample> sample;
 winrt::check_hresult(MFCreateSample(sample.put()));
 winrt::check_hresult(sample->AddBuffer(buffer));
 winrt::check_hresult(sample->SetSampleTime(time));
 winrt::check_hresult(sample->SetSampleDuration(duration));
 winrt::check_hresult(writer->WriteSample(stream, sample.get()));
}

// WGC sends frames when content changes. Retain the final image through stop,
// even when the desktop has been completely still for several seconds.
inline bool writeVideoTail(IMFSinkWriter* writer, DWORD stream, IMFMediaBuffer* buffer, int64_t elapsed, int64_t& lastWritten) {
 const auto duration = std::max(elapsed, lastWritten + videoFrameDuration);
 if (!buffer || duration <= lastWritten + 2 * videoFrameDuration) return false;
 const auto time = duration - videoFrameDuration;
 writeVideoSample(writer, stream, buffer, time, videoFrameDuration);
 lastWritten = time;
 return true;
}
}
