#+build windows
package networking

import "core:net"
import win32 "core:sys/windows"

// sockets are inheritable on Windows, so game servers spawned by the lobby
// would otherwise keep lobby sockets alive, including the listening one
@(private)
disableInheritance :: proc(socket: net.TCP_Socket) {
	win32.SetHandleInformation(win32.HANDLE(uintptr(socket)), win32.HANDLE_FLAG_INHERIT, 0)
}
