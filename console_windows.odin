#+build windows
package main

import "core:os"
import win32 "core:sys/windows"

// missing from core:sys/windows
foreign import kernel32 "system:Kernel32.lib"
@(default_calling_convention="system")
foreign kernel32 {
	SetStdHandle :: proc(nStdHandle: win32.DWORD, hHandle: win32.HANDLE) -> win32.BOOL ---
}
ATTACH_PARENT_PROCESS :: win32.DWORD(0xFFFFFFFF)

// Built with `-subsystem:windows` the executable gets no console window, which is what
// the client wants. Servers and lobbies still need their output: they take the terminal
// they were started from, or open a console of their own.

// uses the parent's console when there is one; nothing happens when output is already
// redirected to a file or pipe, or when the build has a console anyway
attachParentConsole :: proc() {
	if hasConsoleOutput() do return
	if win32.AttachConsole(ATTACH_PARENT_PROCESS) do useConsoleHandles()
}

// a console of its own, for servers and lobbies started by double click
ensureConsole :: proc() {
	if hasConsoleOutput() do return
	if win32.AllocConsole() do useConsoleHandles()
}

@(private="file")
hasConsoleOutput :: proc() -> bool {
	if win32.GetConsoleWindow() != nil do return true
	handle := win32.GetStdHandle(win32.STD_OUTPUT_HANDLE)
	return handle != nil && handle != win32.INVALID_HANDLE_VALUE
}

// points stdout and stderr at the console; inheritable, so spawned game servers can share it
@(private="file")
useConsoleHandles :: proc() {
	attributes := win32.SECURITY_ATTRIBUTES {
		nLength = size_of(win32.SECURITY_ATTRIBUTES),
		bInheritHandle = true
	}
	out := win32.CreateFileW(
		win32.L("CONOUT$"),
		win32.GENERIC_READ | win32.GENERIC_WRITE,
		win32.FILE_SHARE_READ | win32.FILE_SHARE_WRITE,
		&attributes,
		win32.OPEN_EXISTING,
		0,
		nil
	)
	if out == win32.INVALID_HANDLE_VALUE do return
	SetStdHandle(win32.STD_OUTPUT_HANDLE, out)
	SetStdHandle(win32.STD_ERROR_HANDLE, out)
	os.stdout = os.new_file(uintptr(out), "<stdout>")
	os.stderr = os.new_file(uintptr(out), "<stderr>")
}
