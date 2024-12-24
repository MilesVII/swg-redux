package networking

import "core:net"
import "core:mem"
import "core:slice"
import "core:encoding/uuid"
import "core:encoding/hex"
import "core:crypto/hash"
import "core:fmt"
import "core:strings"

PORT :: 8000

Message :: enum { JOIN, UPDATE, ORDERS }
MessageHeader :: struct {
	message: Message,
	me: uuid.Identifier,
	payloadSize: u32
}

openServerSocket :: proc() -> net.TCP_Socket {
	socket, err := net.listen_tcp(net.Endpoint{
		port = PORT,
		address = net.IP4_Loopback
	})
	if err != nil {
		fmt.panicf("listen error : %s", err)
	}

	return socket
}

dial :: proc() -> net.TCP_Socket {
	socket, err := net.dial_tcp(net.IP4_Loopback, PORT)

	if err != nil {
		fmt.panicf("can't dial localhost:%s; %s", PORT, err)
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

listenBlocking :: proc(onPackage: proc(socket: net.TCP_Socket, header: MessageHeader, payload: string), socket: net.TCP_Socket) {
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
		onPackage(socket, header, payload)
	}
}

say :: proc(socket: net.TCP_Socket, header: ^MessageHeader, payload: string = "") {
	header.payloadSize = u32(len(payload))
	// bytes := transmute([^]u8)&payload;
	headerSlice := mem.slice_ptr(header, 1)
	headerBytes := slice.to_bytes(headerSlice)

	fmt.println(
		"[net] say",
		header.message,
		header.payloadSize == 0 ? "empty" : transmute(string)hex.encode(hash.hash_string(.SHA256, payload)),
		len(payload),
		"bytes"
	)

	net.send_tcp(socket, headerBytes)

	if header.payloadSize > 0 {
		net.send_tcp(socket, transmute([]u8)payload)
	}
}

@(private)
readPackage :: proc(socket: net.TCP_Socket) -> (bool, MessageHeader, string) {
	header : MessageHeader
	headerSlice := mem.slice_ptr(&header, 1)
	headerBuffer := slice.to_bytes(headerSlice)

	_, e := net.recv_tcp(socket, headerBuffer)
	if e != nil {
		fmt.printfln("error while reading socket (header): %s", e)
		return false, header, ""
	}

	if header.payloadSize == 0 do return true, header, ""

	payloadBuffer := make([]u8, header.payloadSize)
	defer delete(payloadBuffer)

	_, e2 := net.recv_tcp(socket, payloadBuffer)
	if e2 != nil {
		fmt.printfln("error while reading socket (payload): %s", e2)
		return false, header, ""
	}

	payload, e3 := strings.clone_from_bytes(payloadBuffer)
	if e3 != nil {
		fmt.printfln("failed to convert bytes to string: %s", e3)
		return false, header, ""
	}
	return true, header, payload
}
