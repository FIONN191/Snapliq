import AppKit
@main struct BridgeHarness {
 static func main(){
  let path=CommandLine.arguments[1],report=CommandLine.arguments[2]
  let bridge=DesktopBridge(path:path)
  bridge.onAction={action in try? Data(action.utf8).write(to:URL(fileURLWithPath:report))}
  bridge.start()
  RunLoop.current.run(until:Date().addingTimeInterval(15))
  bridge.stop()
 }
}
