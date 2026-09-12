import subprocess,time,json,os,signal,sys
if sys.argv[1:] != ["--run-interactive"]:raise SystemExit("Run explicitly with --run-interactive; this records a generated native window and operates its controls.")
from pathlib import Path
root=Path(__file__).resolve().parent.parent;folder=root/'work'/('recording-controls-'+str(time.time_ns()));folder.mkdir(parents=True)
ready=folder/'ready.pid';ready.unlink(missing_ok=True)
with (folder/'test.log').open('w') as log:
 p=subprocess.Popen([str(root/'.build/macos/recording_control_tests'),str(folder),str(root/'.build/macos/accessibility_fixture')],stdout=log,stderr=log)
 try:
  for _ in range(150):
   if ready.exists() or p.poll() is not None:break
   time.sleep(.1)
  assert ready.exists(),(folder/'test.log').read_text()
  pid=ready.read_text().strip()
  for action in ['pause','pause','stop']:
   time.sleep(1)
   subprocess.run([str(root/'.build/macos/ax_control'),pid,'snapliq.recording.'+action],check=True,timeout=8)
  assert p.wait(timeout=15)==0,(folder/'test.log').read_text()
 finally:
  if p.poll() is None:p.terminate();p.wait(timeout=5)
  metadata=folder/"fixture.json"
  if metadata.exists():
   child=json.loads(metadata.read_text())["pid"]
   command=subprocess.run(["ps","-p",str(child),"-o","command="],capture_output=True,text=True).stdout
   if str(root/".build/macos/accessibility_fixture") in command:
    try:os.kill(child,signal.SIGTERM)
    except ProcessLookupError:pass
print((folder/'test.log').read_text())
