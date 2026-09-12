from pathlib import Path
import subprocess,struct,shutil
root=Path("assets");generated=root/"generated";generated.mkdir(parents=True,exist_ok=True)
geometry='<path d="M14 34V14H34 M30 50H50V30" fill="none" stroke="currentColor" stroke-width="6.5" stroke-linecap="round" stroke-linejoin="round"/><circle cx="32" cy="32" r="3.6" fill="currentColor"/>'
for label,color in [("black","#000000"),("white","#FFFFFF")]:
 (root/("symbol-"+label+".svg")).write_text('<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 64 64" color="'+color+'">'+geometry+'</svg>')
layers=root/"icon-composer-layers";layers.mkdir(exist_ok=True)
(layers/"capture-corners.svg").write_text('<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 64 64"><path d="M14 34V14H34 M30 50H50V30" fill="none" stroke="#EEEEEE" stroke-width="6.5" stroke-linecap="round" stroke-linejoin="round"/></svg>')
(layers/"capture-dot.svg").write_text('<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 64 64"><circle cx="32" cy="32" r="3.6" fill="#EEEEEE"/></svg>')
(layers/"README.md").write_text("Editable layers for Icon Composer. Configure background separately: graphite or light silver. Outline the corner strokes in the vector editor before production import. No pre-baked system mask, blur, refraction or specular highlight. This directory is not a compiled .icon asset; Icon Composer and macOS 26+ verification remain required. Legacy macOS .icns is provided separately.\n")
for name,bg,fg in [("dark","#191A1C","#F1F3F5"),("light","#F3F4F5","#17191C")]:
 (root/("app-"+name+".svg")).write_text('<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 64 64"><g id="background"><rect width="64" height="64" rx="13" fill="'+bg+'"/></g><g id="symbol" color="'+fg+'">'+geometry+'</g></svg>')
subprocess.run(["swift","-module-cache-path",".build/macos/ModuleCache","scripts/render-icons.swift",str(generated)],check=True)
iconset=generated/"Snapliq.iconset";iconset.mkdir(exist_ok=True)
for size in [16,32,128,256,512]:
 for factor in [1,2]:
  suffix="@2x" if factor==2 else ""
  shutil.copyfile(generated/("dark-"+str(size*factor)+".png"),iconset/("icon_"+str(size)+"x"+str(size)+suffix+".png"))
subprocess.run(["iconutil","-c","icns",str(iconset),"-o",str(generated/"Snapliq.icns")],check=True)
for style in ["dark","light","black","white"]:
 images=[(n,(generated/(style+"-"+str(n)+".png")).read_bytes()) for n in [16,24,32,48,64,128,256]]
 offset=6+16*len(images);header=struct.pack("<HHH",0,1,len(images));payload=b""
 for n,data in images:
  header+=struct.pack("<BBBBHHII",n%256,n%256,0,0,1,32,len(data),offset);payload+=data;offset+=len(data)
 (generated/("Snapliq-"+style+".ico")).write_bytes(header+payload)
for name,style,sizes in [("chrome","black",[16,24,32,48,128]),("tray","black",[16,20,24,32,40,48]),("menubar","black",[18,36]),("orb","orb",[48,96])]:
 folder=generated/name;folder.mkdir(exist_ok=True)
 for n in sizes:
  source=generated/(style+"-"+str(n)+".png")
  if source.exists():shutil.copyfile(source,folder/(str(n)+".png"))
print("Editable SVGs, ICNS, ICO and dedicated toolbar assets generated")
