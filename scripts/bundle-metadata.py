import json,plistlib,sys
from pathlib import Path
brand=json.loads(Path("brand/product.json").read_text())
identity=json.loads(Path("config/development.json").read_text())
chrome=json.loads(Path("config/chrome-development.json").read_text())
info={"SnapliqChromeExtensionID":chrome["extensionId"],"CFBundleName":brand["desktopName"],"CFBundleDisplayName":brand["desktopName"],"CFBundleIdentifier":identity["macBundleIdentifier"],"CFBundleExecutable":"Snapliq","CFBundlePackageType":"APPL","CFBundleShortVersionString":brand["version"],"CFBundleVersion":"4","NSMicrophoneUsageDescription":"Snapliq uses the microphone only when you enable microphone recording.","SnapliqDataDirectory":identity["dataDirectory"],"LSMinimumSystemVersion":"14.0","LSUIElement":True,"NSHighResolutionCapable":True,"CFBundleIconFile":"AppIcon","SnapliqTagline":brand["tagline"],"NSPrincipalClass":"NSApplication"}
(Path(sys.argv[1] if len(sys.argv)>1 else "outputs/candidate/Snapliq.app")/"Contents/Info.plist").write_bytes(plistlib.dumps(info))
