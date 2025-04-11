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
	payload: []u8,
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
			header.payloadSize == 0 ? "empty" : chksum(payload),
			len(payload),
			"bytes"
		)
		
		synchan.send(channel, Package { header, payload, socket })
	}
}

say :: proc(socket: net.TCP_Socket, header: ^MessageHeader, payload: []u8 = nil) {
	header.payloadSize = u32(len(payload))
	// bytes := transmute([^]u8)&payload
	headerSlice := mem.slice_ptr(header, 1)
	headerBytes := slice.to_bytes(headerSlice)

	fmt.println(
		"[net] say",
		header.message,
		header.payloadSize == 0 ? "empty" : chksum(payload),
		len(payload),
		"bytes"
	)

	_, err := net.send_tcp(socket, headerBytes)
	if err != nil do fmt.println("no voice (header): ", err)

	if header.payloadSize > 0 {
		_, err2 := net.send_tcp(socket, payload)
		if err2 != nil do fmt.println("no voice (payload): ", err2)
	}
}

@(private)
readPackage :: proc(socket: net.TCP_Socket) -> (bool, MessageHeader, []u8) {
	header: MessageHeader
	headerSlice := mem.slice_ptr(&header, 1)
	headerBuffer := slice.to_bytes(headerSlice)

	if !fillBuffer(socket, headerBuffer) do return false, header, nil

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

@(private)
chksum :: proc(payload: []u8) -> string {
	hashsum := transmute(string)hex.encode(hash.hash_bytes(.SHA256, payload))
	substring, ok := strings.substring_from(hashsum, len(hashsum) - 6)
	return ok ? substring : hashsum
}
