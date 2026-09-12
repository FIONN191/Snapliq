import json,subprocess,zipfile,hashlib,plistlib,os,argparse
from pathlib import Path
parser=argparse.ArgumentParser();parser.add_argument("--desktop-only",action="store_true");args=parser.parse_args()
root=Path(__file__).resolve().parent.parent
out=root/"outputs";version=json.loads((root/"brand/product.json").read_text())["version"]
app=Path(os.environ.get("SNAPLIQ_APP_PATH",str(out/"builds"/version/"Snapliq.app")))
info=plistlib.loads((app/"Contents/Info.plist").read_bytes())
if info["CFBundleShortVersionString"] != version:raise SystemExit("Refusing to package an app whose version differs from brand/product.json")
subprocess.run(["codesign","--verify","--deep","--strict",str(app)],check=True)
subprocess.run(["ditto","-c","-k","--keepParent",str(app),str(out/f"Snapliq-{version}-macOS-arm64-development.zip")],check=True)
if not args.desktop_only:subprocess.run(["python3",str(root/"scripts/build-chrome.py")],check=True,cwd=root)
with zipfile.ZipFile(out/f"Snapliq-{version}-source.zip","w",zipfile.ZIP_DEFLATED) as archive:
    directories=["apps","core","tests","scripts","packaging","config","brand","assets","docs",".github",".agents/skills/ui-ux-pro-max"]
    files=[root/"README.md",root/"CMakeLists.txt",root/".gitignore"]
    for directory in directories:files.extend((root/directory).rglob("*"))
    files.extend((out/"design-system").rglob("*"))
    files.extend(out.glob("Snapliq-*-validation.md"))
    for evidence_version in {"v0.2.0","v0.2.1","v"+version}:
        files.extend((out/"evidence"/evidence_version).rglob("*"))
    for file in sorted(set(files)):
        if not file.is_file() or "__pycache__" in file.parts or file.suffix in (".pyc",):continue
        archive.write(file,file.relative_to(root))
paths=[out/f"Snapliq-{version}-source.zip",out/f"Snapliq-{version}-macOS-arm64-development.zip"]
if not args.desktop_only:paths.append(out/"Snapliq-for-Chrome-development.zip")
dmg=out/f"Snapliq-{version}-macOS-arm64-development.dmg"
if dmg.exists():paths.append(dmg)
(out/f"Snapliq-{version}-checksums.json").write_text(json.dumps({p.name:hashlib.sha256(p.read_bytes()).hexdigest() for p in paths},indent=2)+"\n")
print("Packaged development source and Apple Silicon desktop app"+("; Chrome companion unchanged." if args.desktop_only else "; Chrome companion rebuilt.")+" Windows binary and release notarization are not implied.")
