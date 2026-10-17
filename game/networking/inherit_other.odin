#+build !windows
package networking

import "core:net"

// sockets are already created with CLOEXEC on other platforms
@(private)
disableInheritance :: proc(socket: net.TCP_Socket) {}
