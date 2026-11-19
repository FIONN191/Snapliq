#pragma once
#include <atomic>
#include <string_view>

namespace localization {
enum class Language { simplifiedChinese, english };
// Capture/OCR/recording workers may create user-facing errors while the UI switches.
// Literal strings retain their lifetime; translation never waits for I/O or a lock.
inline std::atomic<Language> selectedLanguage{Language::simplifiedChinese};
inline Language language() noexcept { return selectedLanguage.load(std::memory_order_relaxed); }
inline void setLanguage(Language value) noexcept { selectedLanguage.store(value,std::memory_order_relaxed); }
inline Language fromPreference(std::wstring_view value) noexcept {
 return value==L"en"?Language::english:Language::simplifiedChinese;
}
inline const wchar_t* preference(Language value) noexcept { return value==Language::english?L"en":L"zh-Hans"; }
inline const wchar_t* tr(const wchar_t* chinese,const wchar_t* english) noexcept {
 return language()==Language::english?english:chinese;
}
}
using localization::tr;
