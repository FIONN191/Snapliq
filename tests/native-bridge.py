import json,os,socket,struct,subprocess,tempfile,time
from pathlib import Path
root=Path(__file__).resolve().parent.parent
with tempfile.TemporaryDirectory(prefix="snapliq-bridge-") as directory:
 path=Path(directory)/"bridge.sock";report=Path(directory)/"action"
 process=subprocess.Popen([str(root/".build/macos/bridge_tests"),str(path),str(report)])
 try:
  for _ in range(100):
   if path.exists():break
   time.sleep(.02)
  assert path.exists()
  assert path.stat().st_mode & 0o777 == 0o600
  def exchange(payload,header=None):
   with socket.socket(socket.AF_UNIX) as client:
    client.settimeout(4);client.connect(str(path));client.sendall(struct.pack("<I",len(payload) if header is None else header)+payload)
    prefix=client.recv(4);assert len(prefix)==4
    size=struct.unpack("<I",prefix)[0];data=b""
    while len(data)<size:data+=client.recv(size-len(data))
    return json.loads(data)
  assert exchange(b'{"action":"ping","requestId":"test"}')["requestId"]=="test"
  assert not report.exists()
  assert exchange(b'{"action":"capture"}')["accepted"]
  for _ in range(100):
   if report.exists():break
   time.sleep(.01)
  assert report.read_text()=="capture"
  for payload in (b'not json',b'{"action":"shell"}',b'{}'):
   assert exchange(payload)["error"]=="invalid_request"
  assert exchange(b"",65537)["error"]=="invalid_request"
  # An idle client is disconnected after the server timeout; the next client remains usable.
  with socket.socket(socket.AF_UNIX) as idle:
   idle.settimeout(4);idle.connect(str(path));time.sleep(2.2)
  assert exchange(b'{"action":"ping"}')["ok"]
  print("PASS native bridge: peer-only socket, permissions, bounded frames, allowlist, main-loop dispatch, idle timeout")
 finally:
  process.terminate();process.wait(timeout=5)
version=json.loads((root/"brand/product.json").read_text())["version"]
host=root/"outputs/builds"/version/"Snapliq.app/Contents/MacOS/SnapliqBridge"
bad=subprocess.run([str(host),"chrome-extension://invalid/"],input=b"",capture_output=True)
assert bad.returncode==2 and not bad.stdout
origin="chrome-extension://"+json.loads((root/"config/chrome-development.json").read_text())["extensionId"]+"/"
request=b'{"action":"shell"}'
good=subprocess.run([str(host),origin],input=struct.pack("<I",len(request))+request,capture_output=True,timeout=5)
assert good.returncode==0
size=struct.unpack("<I",good.stdout[:4])[0]
assert json.loads(good.stdout[4:4+size])["error"]=="invalid_request"
print("PASS bundled Chrome host: origin validation, framed reply, unsupported-action rejection, clean stdin EOF")
