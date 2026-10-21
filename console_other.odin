#+build !windows
package main

// terminals are inherited as usual outside Windows, see console_windows.odin
attachParentConsole :: proc() {}
ensureConsole :: proc() {}
