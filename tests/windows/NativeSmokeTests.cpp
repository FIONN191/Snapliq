#include "capture.h"
#include "recorder-video.h"
#include <propvarutil.h>
#include <cmath>
#include <cstddef>
#include <winrt/base.h>
#include <wincodec.h>
#include <algorithm>
#include <array>
#include <filesystem>
#include <fstream>
#include <iostream>
#include <iterator>
#include <stdexcept>
#include <string>
#include <vector>

// Deterministic native image/codec checks use Snapliq production functions with
// generated pixels. No desktop or clipboard access; these are not WGC, audio
// device, physical display or full-application recording tests.
namespace {
unsigned checks = 0;

void expect(bool condition, const char* message) {
    ++checks;
    if (!condition) throw std::runtime_error(message);
}

template<class Action> void expectFailure(Action action, const char* message) {
    bool failed = false;
    try { action(); } catch (const winrt::hresult_error&) { failed = true; }
    catch (const std::exception&) { failed = true; }
    expect(failed, message);
}

Image pattern(int width, int height, unsigned seed) {
    Image image;
    image.width = width;
    image.height = height;
    image.bgra.resize(static_cast<size_t>(width) * height * 4);
    for (int y = 0; y < height; ++y) {
        for (int x = 0; x < width; ++x) {
            const auto p = (static_cast<size_t>(y) * width + x) * 4;
            image.bgra[p] = static_cast<uint8_t>((x * 17 + y * 29 + seed) % 256);
            image.bgra[p + 1] = static_cast<uint8_t>((x * 11 + y * 43 + seed * 3) % 256);
            image.bgra[p + 2] = static_cast<uint8_t>((x * 37 + y * 7 + seed * 5) % 256);
            // Deliberately nonopaque: screenshot crop must make output opaque,
            // whereas the PNG encoder must preserve the alpha supplied to it.
            image.bgra[p + 3] = static_cast<uint8_t>(64 + (x * 9 + y * 13) % 192);
        }
    }
    return image;
}

Image decodePNG(const std::vector<uint8_t>& bytes) {
    auto factory = winrt::create_instance<IWICImagingFactory>(CLSID_WICImagingFactory);
    winrt::com_ptr<IWICStream> stream;
    winrt::check_hresult(factory->CreateStream(stream.put()));
    winrt::check_hresult(stream->InitializeFromMemory(
        const_cast<BYTE*>(bytes.data()), static_cast<DWORD>(bytes.size())));
    winrt::com_ptr<IWICBitmapDecoder> decoder;
    winrt::check_hresult(factory->CreateDecoderFromStream(
        stream.get(), nullptr, WICDecodeMetadataCacheOnLoad, decoder.put()));
    GUID container{};
    winrt::check_hresult(decoder->GetContainerFormat(&container));
    expect(container == GUID_ContainerFormatPng, "Encoded file must be a PNG");
    UINT frameCount = 0;
    winrt::check_hresult(decoder->GetFrameCount(&frameCount));
    expect(frameCount == 1, "Screenshot PNG must contain one image");
    winrt::com_ptr<IWICBitmapFrameDecode> frame;
    winrt::check_hresult(decoder->GetFrame(0, frame.put()));
    UINT width = 0, height = 0;
    winrt::check_hresult(frame->GetSize(&width, &height));
    winrt::com_ptr<IWICFormatConverter> converter;
    winrt::check_hresult(factory->CreateFormatConverter(converter.put()));
    winrt::check_hresult(converter->Initialize(frame.get(), GUID_WICPixelFormat32bppBGRA,
        WICBitmapDitherTypeNone, nullptr, 0, WICBitmapPaletteTypeCustom));
    Image decoded;
    decoded.width = static_cast<int>(width);
    decoded.height = static_cast<int>(height);
    decoded.bgra.resize(static_cast<size_t>(width) * height * 4);
    winrt::check_hresult(converter->CopyPixels(nullptr, width * 4,
        static_cast<UINT>(decoded.bgra.size()), decoded.bgra.data()));
    return decoded;
}

void expectImage(const Image& actual, const Image& expected) {
    expect(actual.width == expected.width, "Image width changed");
    expect(actual.height == expected.height, "Image height changed");
    expect(actual.bgra.size() == expected.bgra.size(), "Image buffer size changed");
    for (size_t i = 0; i < expected.bgra.size(); ++i)
        expect(actual.bgra[i] == expected.bgra[i], "Image pixel channel or orientation changed");
}

void expectCrop(const Image& source, RECT requested, RECT expected) {
    const auto cropped = cropImage(source, requested);
    expect(cropped.width == expected.right - expected.left, "Crop width is incorrect");
    expect(cropped.height == expected.bottom - expected.top, "Crop height is incorrect");
    for (int y = 0; y < cropped.height; ++y) {
        for (int x = 0; x < cropped.width; ++x) {
            const size_t output = (static_cast<size_t>(y) * cropped.width + x) * 4;
            const size_t input = (static_cast<size_t>(y + expected.top) * source.width
                + x + expected.left) * 4;
            for (int channel = 0; channel < 3; ++channel)
                expect(cropped.bgra[output + channel] == source.bgra[input + channel],
                    "Crop selected the wrong pixel");
            expect(cropped.bgra[output + 3] == 255, "Desktop crop must be opaque");
        }
    }
    expectImage(decodePNG(encodePNG(cropped)), cropped);
}

struct TemporaryDirectory {
    std::filesystem::path path;
    TemporaryDirectory() {
        GUID id{};
        winrt::check_hresult(CoCreateGuid(&id));
        wchar_t text[40]{};
        expect(StringFromGUID2(id, text, 40) != 0, "Unable to format test directory ID");
        path = std::filesystem::temp_directory_path() / (std::wstring(L"Snapliq-native-test-") + text);
        expect(std::filesystem::create_directory(path), "Unable to create test directory");
    }
    ~TemporaryDirectory() {
        std::error_code ignored;
        std::filesystem::remove_all(path, ignored);
    }
};

std::vector<uint8_t> readFile(const std::filesystem::path& path) {
    std::ifstream file(path, std::ios::binary);
    expect(file.is_open(), "Saved PNG cannot be opened");
    return std::vector<uint8_t>(std::istreambuf_iterator<char>(file),
        std::istreambuf_iterator<char>());
}

size_t fileCount(const std::filesystem::path& directory) {
    return static_cast<size_t>(std::distance(std::filesystem::directory_iterator(directory),
        std::filesystem::directory_iterator()));
}

void checkImagesAndSaving() {
    // Odd dimensions and a distinct value at every pixel expose row-stride,
    // channel-order and vertical-flip regressions that a solid image would hide.
    const auto original = pattern(13, 9, 3);
    const auto originalBytes = original.bgra;
    const auto encoded = encodePNG(original);
    const std::array<uint8_t, 8> signature{137, 80, 78, 71, 13, 10, 26, 10};
    expect(encoded.size() > signature.size(), "PNG output is empty");
    expect(std::equal(signature.begin(), signature.end(), encoded.begin()), "PNG signature is invalid");
    expectImage(decodePNG(encoded), original);

    expectCrop(original, {2, 1, 11, 8}, {2, 1, 11, 8});
    expectCrop(original, {-8, -4, 5, 4}, {0, 0, 5, 4});
    expectCrop(original, {11, 7, 90, 60}, {11, 7, 13, 9});
    expectCrop(original, {-8, -4, 90, 60}, {0, 0, 13, 9});
    expectCrop(original, {12, 8, 13, 9}, {12, 8, 13, 9});
    expectFailure([&] { cropImage(original, {5, 2, 5, 6}); }, "Zero-width crop must fail");
    expectFailure([&] { cropImage(original, {2, 4, 8, 4}); }, "Zero-height crop must fail");
    expectFailure([&] { cropImage(original, {11, 7, 3, 2}); }, "Reversed crop must fail");
    expectFailure([&] { cropImage(original, {20, 20, 22, 22}); }, "Off-image crop must fail");
    expect(original.bgra == originalBytes, "Crop or PNG encoding mutated the captured image");

    TemporaryDirectory directory;
    const auto path = directory.path / L"截图 空格 roundtrip.png";
    saveImage(original, path.wstring(), false);
    auto saved = readFile(path);
    expectImage(decodePNG(saved), original);
    expect(fileCount(directory.path) == 1, "Successful save left a temporary file");

    const auto replacement = pattern(7, 5, 42);
    expectFailure([&] { saveImage(replacement, path.wstring(), false); },
        "Save without overwrite must reject an existing file");
    expect(readFile(path) == saved, "Rejected overwrite damaged the existing PNG");
    expect(fileCount(directory.path) == 1, "Rejected overwrite left a temporary file");

    saveImage(replacement, path.wstring(), true);
    expectImage(decodePNG(readFile(path)), replacement);
    expect(fileCount(directory.path) == 1, "Overwrite left a temporary file");
    expectFailure([&] {
        saveImage(original, (directory.path / L"missing" / L"image.png").wstring(), false);
    }, "Unavailable destination must report failure");
    expect(fileCount(directory.path) == 1, "Failed destination changed the parent directory");
}

struct Apartment {
    Apartment() { winrt::init_apartment(winrt::apartment_type::multi_threaded); }
    ~Apartment() { winrt::uninit_apartment(); }
};

struct MediaFoundation {
    MediaFoundation() { winrt::check_hresult(MFStartup(MF_VERSION)); }
    ~MediaFoundation() { MFShutdown(); }
};

constexpr int videoWidth = 160, videoHeight = 96;
constexpr UINT sourcePitch = videoWidth * 4 + 32;
using Color = std::array<BYTE, 4>;
const std::array<Color, 4> videoColors{{
    {16, 32, 220, 255}, {32, 208, 20, 255},
    {208, 36, 20, 255}, {24, 208, 208, 255}
}};
const std::array<POINT, 4> probes{{{20, 12}, {120, 12}, {20, 72}, {120, 72}}};

void checkDecodedPixels(IMFSample* sample, LONG stride) {
    winrt::com_ptr<IMFMediaBuffer> buffer;
    winrt::check_hresult(sample->ConvertToContiguousBuffer(buffer.put()));
    auto twoD = buffer.try_as<IMF2DBuffer>();
    BYTE* firstRow = nullptr;
    LONG pitch = stride;
    DWORD length = 0;
    if (twoD) {
        winrt::check_hresult(twoD->Lock2D(&firstRow, &pitch));
    } else {
        winrt::check_hresult(buffer->Lock(&firstRow, nullptr, &length));
        if (pitch < 0) firstRow += static_cast<size_t>(-pitch) * (videoHeight - 1);
    }
    try {
        expect(std::abs(pitch) >= videoWidth * 4, "Decoded row stride is too small");
        if (!twoD) expect(length >= static_cast<ULONG>(std::abs(pitch) * videoHeight),
            "Decoded RGB buffer is truncated");
        for (size_t n = 0; n < probes.size(); ++n) {
            const auto p = probes[n];
            const auto pixel = firstRow + ptrdiff_t(p.y) * pitch + p.x * 4;
            for (int channel = 0; channel < 3; ++channel) {
                // H.264 and RGB/YUV conversion are lossy; broad solid probes
                // away from boundaries still distinguish every corner/channel.
                expect(std::abs(int(pixel[channel]) - int(videoColors[n][channel])) <= 38,
                    "MP4 decoded color/channel/orientation differs from generated input");
            }
        }
    } catch (...) {
        if (twoD) twoD->Unlock2D(); else buffer->Unlock();
        throw;
    }
    if (twoD) winrt::check_hresult(twoD->Unlock2D());
    else winrt::check_hresult(buffer->Unlock());
}

void checkVideoCodec() {
    MediaFoundation foundation;
    TemporaryDirectory directory;
    const auto path = directory.path / L"generated-static-tail.mp4";
    // Unequal quadrants plus row padding catch vertical flips, channel swaps,
    // wrong row-pitch handling and packed-buffer assumptions.
    std::vector<BYTE> pixels(static_cast<size_t>(sourcePitch) * videoHeight, 0xA5);
    for (int y = 0; y < videoHeight; ++y) {
        for (int x = 0; x < videoWidth; ++x) {
            const size_t quadrant = (y >= 32 ? 2 : 0) + (x >= 64 ? 1 : 0);
            std::copy(videoColors[quadrant].begin(), videoColors[quadrant].end(),
                pixels.begin() + static_cast<size_t>(y) * sourcePitch + x * 4);
        }
    }
    const auto original = pixels;
    auto writer = snapliq::recording::makeMP4Writer(path.wstring());
    const DWORD stream = snapliq::recording::addVideoStream(writer.get(), videoWidth, videoHeight);
    winrt::check_hresult(writer->BeginWriting());
    auto frame = snapliq::recording::copyBGRAFrame(pixels.data(), sourcePitch, videoWidth, videoHeight);
    DWORD packedLength = 0;
    winrt::check_hresult(frame->GetCurrentLength(&packedLength));
    expect(packedLength == videoWidth * videoHeight * 4, "Encoder input retained GPU row padding");
    expect(pixels == original, "Frame packing mutated source pixels");
    snapliq::recording::writeVideoSample(writer.get(), stream, frame.get(), 0,
        snapliq::recording::videoFrameDuration);
    int64_t last = 0;
    expect(snapliq::recording::writeVideoTail(writer.get(), stream, frame.get(), 20000000, last),
        "Static desktop must have a final frame through the stop time");
    winrt::check_hresult(writer->Finalize());
    writer = nullptr;
    frame = nullptr;
    expect(std::filesystem::file_size(path) > 0, "MP4 was not finalized");

    winrt::com_ptr<IMFAttributes> attributes;
    winrt::check_hresult(MFCreateAttributes(attributes.put(), 1));
    winrt::check_hresult(attributes->SetUINT32(MF_SOURCE_READER_ENABLE_VIDEO_PROCESSING, TRUE));
    winrt::com_ptr<IMFSourceReader> reader;
    winrt::check_hresult(MFCreateSourceReaderFromURL(path.c_str(), attributes.get(), reader.put()));
    winrt::com_ptr<IMFMediaType> nativeType;
    winrt::check_hresult(reader->GetNativeMediaType(MF_SOURCE_READER_FIRST_VIDEO_STREAM, 0, nativeType.put()));
    GUID codec{};
    winrt::check_hresult(nativeType->GetGUID(MF_MT_SUBTYPE, &codec));
    expect(codec == MFVideoFormat_H264, "Recorded MP4 must contain H.264 video");
    PROPVARIANT duration{};
    winrt::check_hresult(reader->GetPresentationAttribute(MF_SOURCE_READER_MEDIASOURCE, MF_PD_DURATION, &duration));
    const auto durationType = duration.vt;
    const auto durationTicks = duration.uhVal.QuadPart;
    PropVariantClear(&duration);
    expect(durationType == VT_UI8, "MP4 duration must be an unsigned timestamp");
    expect(durationTicks >= 19500000 && durationTicks <= 20500000,
        "Static recording duration must remain two seconds after encoding");

    winrt::com_ptr<IMFMediaType> output;
    winrt::check_hresult(MFCreateMediaType(output.put()));
    winrt::check_hresult(output->SetGUID(MF_MT_MAJOR_TYPE, MFMediaType_Video));
    winrt::check_hresult(output->SetGUID(MF_MT_SUBTYPE, MFVideoFormat_RGB32));
    winrt::check_hresult(reader->SetCurrentMediaType(MF_SOURCE_READER_FIRST_VIDEO_STREAM, nullptr, output.get()));
    output = nullptr;
    winrt::check_hresult(reader->GetCurrentMediaType(MF_SOURCE_READER_FIRST_VIDEO_STREAM, output.put()));
    UINT32 width = 0, height = 0, strideBits = 0;
    winrt::check_hresult(MFGetAttributeSize(output.get(), MF_MT_FRAME_SIZE, &width, &height));
    expect(width == videoWidth && height == videoHeight, "MP4 frame dimensions changed");
    LONG stride = videoWidth * 4;
    if (SUCCEEDED(output->GetUINT32(MF_MT_DEFAULT_STRIDE, &strideBits))) stride = static_cast<LONG>(strideBits);
    else winrt::check_hresult(MFGetStrideForBitmapInfoHeader(MFVideoFormat_RGB32.Data1, width, &stride));

    unsigned decoded = 0;
    LONGLONG first = -1, previous = -1;
    bool ended = false;
    for (unsigned attempts = 0; attempts < 256 && !ended; ++attempts) {
        DWORD flags = 0;
        LONGLONG timestamp = 0;
        winrt::com_ptr<IMFSample> sample;
        winrt::check_hresult(reader->ReadSample(MF_SOURCE_READER_FIRST_VIDEO_STREAM, 0,
            nullptr, &flags, &timestamp, sample.put()));
        expect((flags & MF_SOURCE_READERF_ERROR) == 0, "MP4 decode failed");
        if (sample) {
            expect(timestamp >= 0 && timestamp >= previous, "Decoded presentation time moved backward");
            if (decoded == 0) first = timestamp;
            previous = timestamp;
            checkDecodedPixels(sample.get(), stride);
            ++decoded;
        }
        ended = (flags & MF_SOURCE_READERF_ENDOFSTREAM) != 0;
    }
    expect(ended, "MP4 decoder did not reach end of stream");
    expect(decoded >= 2, "Static recording lost its first or last frame");
    expect(first <= 500000, "MP4 does not start near zero");
    expect(previous >= 19000000 && previous <= 20000000, "MP4 tail does not reach the stop time");
    std::cout << "PASS: production H.264 encode/decode, asymmetric BGRA orientation, row padding, "
        << "MP4 finalization and 2-second static tail (" << decoded << " decoded frames).\n";
}

}

int main() {
    try {
        Apartment apartment;
        checkImagesAndSaving();
        checkVideoCodec();
        std::cout << "PASS: " << checks << " Windows production image/codec checks.\n"
            << "No desktop capture, microphone or clipboard access was performed.\n";
        return 0;
    } catch (const winrt::hresult_error& error) {
        std::cerr << "FAIL: " << winrt::to_string(error.message()) << "\n";
    } catch (const std::exception& error) {
        std::cerr << "FAIL: " << error.what() << "\n";
    }
    return 1;
}
