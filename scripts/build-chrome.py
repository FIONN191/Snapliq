import json,shutil,zipfile
from pathlib import Path
root=Path(__file__).resolve().parent.parent
brand=json.loads((root/"brand/product.json").read_text())
identity=json.loads((root/"config/chrome-development.json").read_text())
target=root/"outputs/chrome/Snapliq for Chrome"
target.mkdir(parents=True,exist_ok=True)
for source in (root/"apps/chrome").iterdir():
    if source.is_file():shutil.copy2(source,target/source.name)
(target/"icons").mkdir(exist_ok=True)
for size in (16,32,48,128):shutil.copy2(root/f"assets/generated/chrome/{size}.png",target/f"icons/{size}.png")
for size in (16,32):shutil.copy2(root/f"assets/generated/white-{size}.png",target/f"icons/white-{size}.png")
manifest={"manifest_version":3,"name":brand["extensionName"],"version":brand["version"],"description":"Snapliq 截图与录屏工具的配套入口。需要独立的 Snapliq 桌面应用。","key":identity["key"],"permissions":["nativeMessaging"],"action":{"default_popup":"popup.html","default_title":brand["extensionName"],"default_icon":{str(n):f"icons/{n}.png" for n in (16,32)}},"icons":{str(n):f"icons/{n}.png" for n in (16,32,48,128)},"content_security_policy":{"extension_pages":"script-src 'self'; object-src 'none'"}}
(target/"manifest.json").write_text(json.dumps(manifest,ensure_ascii=False,indent=2)+"\n")
with zipfile.ZipFile(root/"outputs/Snapliq-for-Chrome-development.zip","w",zipfile.ZIP_DEFLATED) as archive:
    for file in sorted(target.rglob("*")):
        if file.is_file():archive.write(file,file.relative_to(target))
print(f"Built {brand['extensionName']} {brand['version']} (development ID {identity['extensionId']})")
