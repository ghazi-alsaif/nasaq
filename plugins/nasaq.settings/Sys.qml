pragma Singleton
import QtQuick
import Quickshell

// Small helpers every page uses to act on the real system.
Singleton {
  function run(cmd) { Quickshell.execDetached(["bash", "-c", cmd]) }
  // Opens an interactive command in Omarchy's floating terminal.
  function term(cmd) { Quickshell.execDetached(["omarchy-launch-floating-terminal-with-presentation", "bash", "-c", cmd]) }
  function edit(path) { Quickshell.execDetached(["omarchy-launch-editor", path]) }
  function ipc(target, method, arg) {
    var c = ["omarchy-shell", "-q", target, method]
    if (arg !== undefined) c.push(String(arg))
    Quickshell.execDetached(c)
  }
  readonly property string home: Quickshell.env("HOME")
  // An app class handed over by "Window rules…" in the Overview; the
  // Workspaces & Windows page picks it up as the rule's app, then clears it.
  property string ruleClassHint: ""
  // Read-modify-write a JSON file atomically (python is always present on Omarchy).
  function jsonSet(path, key, valueJson) {
    Quickshell.execDetached(["python3", "-c",
      "import json,sys,os\np,k,v=sys.argv[1],sys.argv[2],json.loads(sys.argv[3])\n" +
      "d=json.load(open(p)) if os.path.exists(p) else {}\ncur=d\nks=k.split('.')\n" +
      "for x in ks[:-1]:\n  cur=cur.setdefault(x,{})\ncur[ks[-1]]=v\n" +
      "t=p+'.tmp'\nopen(t,'w').write(json.dumps(d,indent=2,ensure_ascii=False)+'\\n')\nos.replace(t,p)",
      path, key, valueJson])
  }
}
