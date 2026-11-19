#pragma once
#include <windows.h>
#include <vector>
#include "localization.h"

// Only chrome text is bound here. Editable content, combo selections, focus and
// recording/capture state stay in their existing controls during a language change.
class LocalizedControls {
 struct Label { HWND window;const wchar_t* chinese;const wchar_t* english; };
 std::vector<Label> labels_;
public:
 void add(HWND window,const wchar_t* chinese,const wchar_t* english){
  if(window)labels_.push_back({window,chinese,english});
 }
 void refresh() const {
  for(const auto& label:labels_)if(IsWindow(label.window))SetWindowTextW(label.window,tr(label.chinese,label.english));
 }
 void clear(){labels_.clear();}
};
