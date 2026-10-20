package networking

import "core:net"
import "core:mem"
import "core:slice"
import "core:crypto/hash"
import "core:fmt"
import "core:sync"
import "core:thread"
import "core:time"
import synchan "core:sync/chan"

// PING is a heartbeat the server and lobby echo back
// CONNECTED, DISCONNECTED and DIAL_FAILED never travel over the wire:
// listener and dialer threads inject them so the main thread can track connections
Message :: enum { JOIN, UPDATE, ORDERS, GENERAL, PING, CONNECTED, DISCONNECTED, DIAL_FAILED }
MessageHeader :: struct {
	message: Message,
	me: [16]rune,
	payloadSize: u32
}
Package :: struct {
	header: MessageHeader,
	payload: []u8,
	socket: net.TCP_Socket,
	// unique per connection, unlike socket handles which get reused by the OS
	connection: int,
	// the dialAsync attempt that opened this connection, 0 for accepted ones
	ticket: int
}

// guards against hostile or corrupted headers asking for huge allocations
MAX_PAYLOAD_SIZE :: 64 * mem.Megabyte

@(private="file")
ACCEPT_RETRY_DELAY := time.Millisecond * 100

tx: synchan.Chan(Package, .Send)
rx: synchan.Chan(Package, .Recv)
verbose := true

@(private="file")
connectionCounter: int
@(private="file")
ticketCounter: int

init :: proc() {
	channel, err := synchan.create_buffered(
		synchan.Chan(Package),
		16, context.allocator
	)
	if err != nil do fmt.panicf("failed to create sync channel: %s", err)
	tx = synchan.as_send(channel)
	rx = synchan.as_recv(channel)
}

openServerSocket :: proc(address: net.Address, port: int) -> net.TCP_Socket {
	socket, err := net.listen_tcp(net.Endpoint{
		port = port,
		address = address
	})
	if err != nil {
		fmt.panicf("listen error : %s", err)
	}
	disableInheritance(socket)

	return socket
}

// checks whether a port can be bound right now
portAvailable :: proc(address: net.Address, port: int) -> bool {
	socket, err := net.listen_tcp(net.Endpoint{
		port = port,
		address = address
	})
	if err != nil do return false
	net.close(socket)
	return true
}

dial :: proc(to: net.Address, port: int) -> (net.TCP_Socket, bool) {
	socket, err := net.dial_tcp(to, port)

	if err != nil {
		fmt.printfln("can't dial %v:%d; %v", to, port, err)
		return socket, false
	}
	disableInheritance(socket)

	return socket, true
}

hang :: proc(socket: net.TCP_Socket) {
	net.close(socket)
}

// makes the listener thread of the socket quit and report DISCONNECTED
// without closing the handle, so it can't be reused while the thread still holds it
kick :: proc(socket: net.TCP_Socket) {
	net.shutdown(socket, .Both)
}

// accepts clients forever on a separate thread
// every client gets a listener thread, see `listen`
startAccepting :: proc(socket: net.TCP_Socket) {
	acceptor :: proc(socket: net.TCP_Socket) {
		for {
			clientSocket, _, acceptErr := net.accept_tcp(socket)
			if acceptErr != nil {
				if verbose do fmt.println("accept error:", acceptErr)
				time.sleep(ACCEPT_RETRY_DELAY)
				continue
			}
			disableInheritance(clientSocket)
			listen(clientSocket)
		}
	}

	thread.create_and_start_with_poly_data(socket, acceptor, self_cleanup = true)
}

// reads packages from the socket on a separate thread and forwards them to `rx`
// sends CONNECTED first and DISCONNECTED once the socket is closed or broken
// returns the connection id that marks every package from this socket
listen :: proc(socket: net.TCP_Socket, ticket := 0) -> int {
	Listener :: struct {
		socket: net.TCP_Socket,
		connection: int,
		ticket: int
	}
	listener :: proc(l: Listener) {
		local :: proc(message: Message, l: Listener) {
			synchan.send(tx, Package {
				header = { message = message },
				socket = l.socket,
				connection = l.connection,
				ticket = l.ticket
			})
		}

		local(.CONNECTED, l)
		listenBlocking(tx, l.socket, l.connection)
		local(.DISCONNECTED, l)
	}

	connection := sync.atomic_add(&connectionCounter, 1) + 1
	thread.create_and_start_with_poly_data(
		Listener { socket, connection, ticket },
		listener,
		self_cleanup = true
	)
	return connection
}

// dials on a separate thread, so a dead network can't freeze the caller;
// the result is a CONNECTED package (then packages as with `listen`) or a DIAL_FAILED one,
// both carrying the returned ticket
dialAsync :: proc(to: net.Address, port: int) -> (ticket: int) {
	Dial :: struct {
		to: net.Address,
		port: int,
		ticket: int
	}
	dialer :: proc(d: Dial) {
		socket, ok := dial(d.to, d.port)
		if ok do listen(socket, d.ticket)
		else do synchan.send(tx, Package { header = { message = .DIAL_FAILED }, ticket = d.ticket })
	}

	ticket = sync.atomic_add(&ticketCounter, 1) + 1
	thread.create_and_start_with_poly_data(Dial { to, port, ticket }, dialer, self_cleanup = true)
	return ticket
}

// returns once the socket is closed or broken
listenBlocking :: proc(channel: synchan.Chan(Package, .Send), socket: net.TCP_Socket, connection: int) {
	for {
		ok, header, payload := readPackage(socket)
		if !ok do break
		if verbose {
			if header.payloadSize == 0 {
				fmt.println("[net] hear", header.message, "empty")
			} else {
				fmt.printfln("[net] hear %v %06x %d bytes", header.message, chksum(payload), len(payload))
			}
		}

		synchan.send(channel, Package { header = header, payload = payload, socket = socket, connection = connection })
	}
}

say :: proc(socket: net.TCP_Socket, header: ^MessageHeader, payload: []u8 = nil, freePayload: bool = true) -> bool {
	defer if freePayload && payload != nil do delete(payload)

	header.payloadSize = u32(len(payload))
	headerSlice := mem.slice_ptr(header, 1)
	headerBytes := slice.to_bytes(headerSlice)

	if verbose {
		if header.payloadSize == 0 {
			fmt.println("[net] say", header.message, "empty")
		} else {
			fmt.printfln("[net] say %v %06x %d bytes", header.message, chksum(payload), len(payload))
		}
	}

	_, err := net.send_tcp(socket, headerBytes)
	if err != nil {
		if verbose do fmt.println("no voice (header): ", err)
		return false
	}

	if header.payloadSize > 0 {
		_, err2 := net.send_tcp(socket, payload)
		if err2 != nil {
			if verbose do fmt.println("no voice (payload): ", err2)
			return false
		}
	}
	return true
}

@(private)
readPackage :: proc(socket: net.TCP_Socket) -> (bool, MessageHeader, []u8) {
	header: MessageHeader
	headerSlice := mem.slice_ptr(&header, 1)
	headerBuffer := slice.to_bytes(headerSlice)

	if !fillBuffer(socket, headerBuffer) do return false, header, nil

	// local-only and unknown message kinds can't come from a peer
	if header.message >= .CONNECTED || header.message < .JOIN {
		if verbose do fmt.println("peer sent invalid message kind, dropping connection")
		return false, header, nil
	}
	if header.payloadSize > MAX_PAYLOAD_SIZE {
		if verbose do fmt.println("peer sent oversized payload, dropping connection")
		return false, header, nil
	}

	if header.payloadSize == 0 do return true, header, nil

	payloadBuffer := make([]u8, header.payloadSize)
	if !fillBuffer(socket, payloadBuffer) {
		delete(payloadBuffer)
		return false, header, nil
	}

	return true, header, payloadBuffer
}

@(private)
fillBuffer :: proc(socket: net.TCP_Socket, buffer: []u8) -> bool {
	receivedSize := 0
	for receivedSize < len(buffer) {
		size, err := net.recv_tcp(socket, buffer[receivedSize:])
		if err != nil {
			if verbose do fmt.printfln("error while reading socket: %s", err)
			return false
		}
		// zero bytes without an error means the peer closed the connection
		if size == 0 do return false
		receivedSize += size
	}
	return true
}

// tail of SHA256, only used to eyeball payloads in logs
@(private)
chksum :: proc(payload: []u8) -> u32 {
	digest: [32]u8
	hash.hash_bytes_to_buffer(.SHA256, payload, digest[:])
	return u32(digest[29]) << 16 | u32(digest[30]) << 8 | u32(digest[31])
}
