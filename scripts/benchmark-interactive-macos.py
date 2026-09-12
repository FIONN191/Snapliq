#!/usr/bin/env python3
"""Opt-in desktop test. Chrome must be closed; Cmd+X must be accepted and enabled."""
import argparse,json,math,subprocess,time
from datetime import datetime
from pathlib import Path
root=Path(__file__).resolve().parent.parent
parser=argparse.ArgumentParser(description=__doc__)
parser.add_argument("--run-interactive",action="store_true",required=True)
parser.add_argument("--samples",type=int,default=100)
parser.add_argument("--output",type=Path,default=root/"work"/("capture-"+datetime.now().strftime("%Y%m%d-%H%M%S")))
parser.add_argument("--configuration",required=True,help="Actual device, OS, logical and captured display sizes, refresh rate")
parser.add_argument("--crop",type=int,nargs=4,default=[300,240,720,480])
parser.add_argument("--expected-pixels",type=int,nargs=2,default=[840,480])
args=parser.parse_args()
if args.samples<1:parser.error("samples must be positive")
def run(*values):return subprocess.check_output([str(x) for x in values],text=True,timeout=15,cwd=root).strip()
def chrome_absent():
 return subprocess.run(["pgrep","-f","/Google Chrome.app/Contents/MacOS/Google Chrome"],stdout=subprocess.DEVNULL).returncode==1
if not chrome_absent():raise SystemExit("Quit Chrome before starting the opt-in test.")
tools=root/".build/macos";tools.mkdir(parents=True,exist_ok=True)
for source,name in [("CaptureFixture","capture-fixture"),("InputDriver","input-driver"),("ClipboardCheck","clipboard-check"),("ClipboardPreserve","clipboard-preserve"),("TimedKey","timed-key")]:
 subprocess.run(["swiftc","-O","-module-cache-path",str(tools/"ModuleCache"),str(root/f"tests/macos/{source}.swift"),"-o",str(tools/name)],check=True)
out=args.output.resolve();out.mkdir(parents=True,exist_ok=False)
log=Path.home()/"Library/Application Support/Snapliq Development/Diagnostics/events.jsonl"
start=len(log.read_text().splitlines());samples=[]
def events():return [json.loads(x) for x in log.read_text().splitlines()[start:]]
def wait(name,offset):
 deadline=time.monotonic()+8
 while time.monotonic()<deadline:
  matches=[e for e in events()[offset:] if e["event"]==name]
  if matches:return matches[-1]
  time.sleep(.01)
 raise RuntimeError("Timed out: "+name)
def percentile(values,p):
 values=sorted(values);i=(len(values)-1)*p;lo=math.floor(i);hi=math.ceil(i)
 return values[lo]+(values[hi]-values[lo])*(i-lo)
backup=out/"clipboard-backup.plist"
run(tools/"clipboard-preserve","backup",backup)
fixture=None
try:
 fixture=subprocess.Popen([str(tools/"capture-fixture")],stdout=subprocess.DEVNULL,stderr=subprocess.DEVNULL)
 time.sleep(.5)
 for i in range(args.samples):
  if not chrome_absent():raise RuntimeError("Chrome started during the test")
  offset=len(events());pressed=float(run(tools/"timed-key","7","command"))
  wait("selectable",offset)
  run(tools/"input-driver","drag",*args.crop)
  confirmed=float(run(tools/"timed-key","36"));wait("clipboard_complete",offset)
  image=json.loads(run(tools/"clipboard-check",out/"last-capture.png"))
  if [image["width"],image["height"]]!=args.expected_pixels:raise RuntimeError("Unexpected pixel size: "+repr(image))
  batch=events()[offset:]
  sample={name:(next(e["uptime"] for e in batch if e["event"]==name)-(confirmed if name=="clipboard_complete" else pressed))*1000 for name in ["feedback_submitted","background_ready","selectable","clipboard_complete"]}
  if any(v<0 for v in sample.values()):raise RuntimeError("Invalid monotonic event sequence")
  samples.append(sample)
  if (i+1)%20==0:print(f"PASS {i+1}/{args.samples}",flush=True)
 report={"date":datetime.now().astimezone().isoformat(),"configuration":args.configuration,"samples":len(samples),"passed":len(samples),"chromeAbsentEveryIteration":True,"measurement":"CGEvent pre-post uptime to app milestone. Feedback and selectable are app submissions, NOT measured physical display presentation. Clipboard begins before Enter key-down.","latencyMs":{name:{"p50":percentile([s[name] for s in samples],.5),"p95":percentile([s[name] for s in samples],.95)} for name in samples[0]}}
 (out/"capture-performance.json").write_text(json.dumps(report,indent=2)+"\n");print(json.dumps(report,indent=2))
finally:
 # Cancel an unfinished selection before taking the fixture away.
 try:run(tools/"timed-key","53")
 finally:
  try:run(tools/"clipboard-preserve","restore",backup)
  finally:
   if fixture is not None:fixture.terminate();fixture.wait(timeout=5)
   (out/"capture-samples.json").write_text(json.dumps(samples,indent=2)+"\n")
   (out/"capture-events.jsonl").write_text("\n".join(json.dumps(e) for e in events())+"\n")
