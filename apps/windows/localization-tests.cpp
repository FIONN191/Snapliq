// Exercise the production settings/OCR language-change path with real Win32
// controls. This does not capture a screen, record audio, or register shortcuts.
#include "main.cpp"
#include <iostream>
#include <stdexcept>

namespace {
unsigned checks=0;
void expect(bool value,const char* message){++checks;if(!value)throw std::runtime_error(message);}
std::wstring windowText(HWND window){
 std::wstring value(size_t(GetWindowTextLengthW(window))+1,L'\0');
 value.resize(size_t(GetWindowTextW(window,value.data(),int(value.size()))));return value;
}
void chooseLanguage(int index){
 SendDlgItemMessageW(app.settings,LANGUAGE,CB_SETCURSEL,index,0);
 SendMessageW(app.settings,WM_COMMAND,MAKEWPARAM(LANGUAGE,CBN_SELCHANGE),reinterpret_cast<LPARAM>(GetDlgItem(app.settings,LANGUAGE)));
}
}
int main(){
 // The App singleton only reads existing preferences during construction. All
 // test writes go into this unique key, removed again on exit.
 const auto testKey=L"Software\\Snapliq\\LocalizationTest-"+std::to_wstring(GetCurrentProcessId())+L"-"+std::to_wstring(GetTickCount64());
 PREFS=testKey.c_str();int result=0;
 try{
  winrt::init_apartment(winrt::apartment_type::single_threaded);
  INITCOMMONCONTROLSEX controls{sizeof(controls),ICC_WIN95_CLASSES};InitCommonControlsEx(&controls);
  for(const auto& entry:std::vector<std::pair<const wchar_t*,WNDPROC>>{{L"SnapliqSettings",SettingsProc},{L"SnapliqOCR",OCRProc}}){
   WNDCLASSW cls{};cls.hInstance=GetModuleHandleW(nullptr);cls.lpszClassName=entry.first;cls.lpfnWndProc=entry.second;
   expect(RegisterClassW(&cls)!=0,"Could not register fixture class");
  }
  localization::setLanguage(localization::fromPreference(readString(L"interfaceLanguage")));
  expect(localization::language()==localization::Language::simplifiedChinese,"Fresh install should use Simplified Chinese");
  app.host=CreateWindowW(L"STATIC",L"fixture",0,0,0,1,1,HWND_MESSAGE,nullptr,GetModuleHandleW(nullptr),nullptr);
  app.showSettings();ShowWindow(app.settings,SW_HIDE);
  expect(windowText(app.settings)==L"Snapliq 设置","Settings should start in Chinese");
  const auto settingsWindow=app.settings;
  const WORD draftKey=MAKEWORD('Q',HOTKEYF_CONTROL|HOTKEYF_SHIFT);
  SendMessageW(app.hotkeyControl,HKM_SETHOTKEY,draftKey,0);
  CheckDlgButton(app.settings,ORB_LOCK,BST_CHECKED);
  SendDlgItemMessageW(app.settings,ORB_SIZE,TBM_SETPOS,TRUE,72);
  app.ocrWindow=CreateWindowW(L"SnapliqOCR",L"提取文字 · Snapliq",WS_OVERLAPPED,0,0,400,300,app.host,nullptr,GetModuleHandleW(nullptr),nullptr);
  app.ocrEdit=CreateWindowW(L"EDIT",L"",WS_CHILD|ES_MULTILINE,0,0,350,200,app.ocrWindow,nullptr,GetModuleHandleW(nullptr),nullptr);
  CreateWindowW(L"BUTTON",L"复制文本",WS_CHILD,0,210,120,30,app.ocrWindow,reinterpret_cast<HMENU>(1),GetModuleHandleW(nullptr),nullptr);
  const std::wstring edited=L"已编辑的中文 OCR\r\nEdited English text";
  SetWindowTextW(app.ocrEdit,edited.c_str());SendMessageW(app.ocrEdit,EM_SETSEL,2,8);
  // A pre-existing capture selection must survive a UI-language change.
  app.desktop=std::make_unique<Desktop>();app.desktop->image.width=23;app.selected=true;app.selection={-20,10,320,180};
  chooseLanguage(1);
  expect(windowText(app.settings)==L"Snapliq Settings","Settings title should update immediately");
  expect(windowText(GetDlgItem(app.settings,REGION))==L"Take screenshot","Settings actions should update immediately");
  expect(readString(L"interfaceLanguage")==L"en","English should persist");
  expect(app.settings==settingsWindow,"Language switching must not recreate settings");
  expect(SendMessageW(app.hotkeyControl,HKM_GETHOTKEY,0,0)==draftKey,"Unsaved shortcut edits must survive switching");
  expect(IsDlgButtonChecked(app.settings,ORB_LOCK)==BST_CHECKED,"Checkbox state must survive switching");
  expect(SendDlgItemMessageW(app.settings,ORB_SIZE,TBM_GETPOS,0,0)==72,"Slider value must survive switching");
  expect(windowText(app.ocrWindow)==L"Extract text · Snapliq","OCR window title should translate");
  expect(windowText(GetDlgItem(app.ocrWindow,1))==L"Copy text","OCR action should translate");
  expect(windowText(app.ocrEdit)==edited,"OCR text must not be translated or reset");
  DWORD start=0,end=0;SendMessageW(app.ocrEdit,EM_GETSEL,reinterpret_cast<WPARAM>(&start),reinterpret_cast<LPARAM>(&end));
  expect(start==2&&end==8,"OCR selection must survive switching");
  expect(app.selected&&app.selection.x==-20&&app.selection.width==320&&app.desktop->image.width==23,"Capture selection and image must survive switching");
  app.setOCRPlaceholder(App::OCRPlaceholder::loading);chooseLanguage(0);
  expect(windowText(app.ocrEdit)==L"正在本地识别中文和英文…","An untouched OCR progress prompt should translate");
  expect(readString(L"interfaceLanguage")==L"zh-Hans","Chinese should persist");
  // Simulate typing over a progress prompt; EN_CHANGE must protect that content.
  SetWindowTextW(app.ocrEdit,edited.c_str());
  SendMessageW(app.ocrWindow,WM_COMMAND,MAKEWPARAM(0,EN_CHANGE),reinterpret_cast<LPARAM>(app.ocrEdit));
  chooseLanguage(1);expect(windowText(app.ocrEdit)==edited,"Typing over progress must protect OCR content");
  localization::setLanguage(localization::Language::simplifiedChinese);
  localization::setLanguage(localization::fromPreference(readString(L"interfaceLanguage")));
  expect(localization::language()==localization::Language::english,"Persisted preference should restore on next launch");
  expect(localization::fromPreference(L"unsupported")==localization::Language::simplifiedChinese,"Unknown preference should safely fall back to Chinese");
  std::cout<<"Windows localization: "<<checks<<" checks passed\n";
 }catch(const winrt::hresult_error& error){std::cerr<<winrt::to_string(error.message())<<'\n';result=1;}
 catch(const std::exception& error){std::cerr<<error.what()<<'\n';result=1;}
 if(app.ocrWindow)DestroyWindow(app.ocrWindow);app.ocrWindow=app.ocrEdit=nullptr;
 if(app.settings)DestroyWindow(app.settings);app.settings=nullptr;
 if(app.host)DestroyWindow(app.host);app.host=nullptr;app.desktop.reset();
 RegDeleteTreeW(HKEY_CURRENT_USER,testKey.c_str());return result;
}
