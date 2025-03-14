package networking

import "core:net"
import "core:mem"
import "core:slice"
import "core:encoding/hex"
import "core:crypto/hash"
import "core:fmt"
import "core:strings"
import synchan "core:sync/chan"

Message :: enum { JOIN, UPDATE, ORDERS }
MessageHeader :: struct {
	message: Message,
	me: [16]rune,
	payloadSize: u32
}
Package :: struct {
	header: MessageHeader,
	payload: string,
	socket: net.TCP_Socket
}

tx: synchan.Chan(Package, .Send)
rx: synchan.Chan(Package, .Recv)

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

	return socket
}

dial :: proc(to: net.Address, port: int) -> net.TCP_Socket {
	socket, err := net.dial_tcp(to, port)

	if err != nil {
		fmt.panicf("can't dial localhost:%s; %s", port, err)
	}

	return socket
}

waitForClient :: proc(socket: net.TCP_Socket) -> net.TCP_Socket {
	clientSocket, clientEndpoint, acceptErr := net.accept_tcp(socket)

	if acceptErr != nil {
		fmt.panicf("%s",acceptErr)
	}

	return clientSocket
}

listenBlocking :: proc(channel: synchan.Chan(Package, .Send), socket: net.TCP_Socket) {
	for {
		ok, header, payload := readPackage(socket)
		if !ok do break
		fmt.println(
			"[net] hear",
			header.message,
			header.payloadSize == 0 ? "empty" : transmute(string)hex.encode(hash.hash_string(.SHA256, payload)),
			len(payload),
			"bytes"
		)
		
		synchan.send(channel, Package { header, payload, socket })
	}
}

say :: proc(socket: net.TCP_Socket, header: ^MessageHeader, payload: string = "") {
	header.payloadSize = u32(len(payload))
	// bytes := transmute([^]u8)&payload
	headerSlice := mem.slice_ptr(header, 1)
	headerBytes := slice.to_bytes(headerSlice)

	fmt.println(
		"[net] say",
		header.message,
		header.payloadSize == 0 ? "empty" : transmute(string)hex.encode(hash.hash_string(.SHA256, payload)),
		len(payload),
		"bytes"
	)

	_, err := net.send_tcp(socket, headerBytes)
	if err != nil do fmt.println("no voice (header): ", err)

	if header.payloadSize > 0 {
		_, err2 := net.send_tcp(socket, transmute([]u8)payload)
		if err2 != nil do fmt.println("no voice (payload): ", err2)
	}
}

@(private)
readPackage :: proc(socket: net.TCP_Socket) -> (bool, MessageHeader, string) {
	header: MessageHeader
	headerSlice := mem.slice_ptr(&header, 1)
	headerBuffer := slice.to_bytes(headerSlice)

	if !fillBuffer(socket, headerBuffer) do return false, header, ""

	if header.payloadSize == 0 do return true, header, ""

	payloadBuffer := make([]u8, header.payloadSize)
	defer delete(payloadBuffer)
	if !fillBuffer(socket, payloadBuffer) do return false, header, ""

	payload, e3 := strings.clone_from_bytes(payloadBuffer)
	if e3 != nil {
		fmt.printfln("failed to convert bytes to string: %s", e3)
		return false, header, ""
	}

	return true, header, payload
}

@(private)
fillBuffer :: proc(socket: net.TCP_Socket, buffer: []u8) -> bool {
	receivedSize: u32 = 0
	for {
		size, e2 := net.recv_tcp(socket, buffer[receivedSize:])
		receivedSize += u32(size)
		if e2 != nil {
			fmt.printfln("error while reading socket: %s", e2)
			return false
		}

		if (receivedSize == u32(len(buffer))) do return true
	}
}
