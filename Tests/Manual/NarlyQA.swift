import AppKit

@MainActor final class Delegate: NSObject, NSApplicationDelegate, NSWindowDelegate {
 var window: NSWindow!
 var label: NSTextField!
 var clicks = 0
 var targetApplication: URL? {
  let args = CommandLine.arguments
  if let index = args.firstIndex(of: "--app-path"), args.indices.contains(index + 1) {
   return URL(fileURLWithPath: args[index + 1])
  }
  return NSWorkspace.shared.urlForApplication(withBundleIdentifier: "app.narlymac.dev")
 }
 func applicationDidFinishLaunching(_ notification: Notification) {
  window = NSWindow(contentRect: NSRect(x:100,y:100,width:1000,height:700),styleMask:[.titled,.closable,.resizable,.miniaturizable],backing:.buffered,defer:false)
  window.title="Narly QA · \(targetApplication?.deletingPathExtension().lastPathComponent ?? "Dev unavailable")";window.collectionBehavior=[.fullScreenPrimary];window.delegate=self
  let content=NSView();content.wantsLayer=true;content.layer?.backgroundColor=NSColor.systemYellow.cgColor
  window.contentView=content
  let stack=NSStackView();stack.orientation = .vertical;stack.spacing=20;stack.translatesAutoresizingMaskIntoConstraints=false
  content.addSubview(stack)
  NSLayoutConstraint.activate([stack.leadingAnchor.constraint(equalTo:content.leadingAnchor,constant:45),stack.topAnchor.constraint(equalTo:content.topAnchor,constant:40)])
  label=NSTextField(labelWithString:"Sample links for Narly. Clicks received: 0");label.font = .systemFont(ofSize:20);stack.addArrangedSubview(label)
  for (title,selector) in [("Send Test Link",#selector(send)),("Send 10 Links",#selector(burst)),("Test Outside Click",#selector(countClick)),("Full Screen",#selector(fullscreen))] {
   let b=NSButton(title:title,target:self,action:selector);b.bezelStyle = .rounded;b.setAccessibilityIdentifier(title);stack.addArrangedSubview(b)
  }
  window.center();window.makeKeyAndOrderFront(nil);NSApp.activate(ignoringOtherApps:true)
 }
 func open(_ urls:[URL]) {
  guard let targetApplication else {
   let alert = NSAlert(); alert.messageText = "Build Narly Dev first"
   alert.informativeText = "Run bash scripts/run-manual-tests.sh from the checkout."
   alert.runModal(); return
  }
  let configuration=NSWorkspace.OpenConfiguration();configuration.activates=false
  NSWorkspace.shared.open(urls,withApplicationAt:targetApplication,configuration:configuration){_,error in
   if let error {print(error)}
  }
 }
 @objc func send() {open([URL(string:"https://example.com/?narly-qa=single&encoded=a%2Fb#fragment")!])}
 @objc func burst() {open((1...10).map{URL(string:"https://example.com/?narly-qa=burst-\($0)")!})}
 @objc func countClick(){clicks+=1;label.stringValue="Sample links for Narly. Clicks received: \(clicks)"}
 @objc func fullscreen(){window.toggleFullScreen(nil)}
 func applicationShouldTerminateAfterLastWindowClosed(_ sender:NSApplication)->Bool{true}
}
@main
@MainActor
struct NarlyQA {
 static func main() {
  let app = NSApplication.shared
  let delegate = Delegate()
  app.delegate = delegate
  app.setActivationPolicy(.regular)
  withExtendedLifetime(delegate) {
   _ = NSApplicationMain(CommandLine.argc, CommandLine.unsafeArgv)
  }
 }
}
