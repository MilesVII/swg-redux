package networking

import "core:net"
import "core:mem"
import "core:slice"
import "core:fmt"

PORT :: 8000

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

listen :: proc($GamePackage: typeid, onPackage: proc(payload: GamePackage), socket: net.TCP_Socket) {
	gamePackage: GamePackage

	for {
		status := readPackage(GamePackage, &gamePackage, socket)
		if status == PackageType.EXIT do break
		if status == PackageType.ERROR do break
		if status == PackageType.GAME do onPackage(gamePackage)
	}
}

say :: proc($GamePackage: typeid, payload: ^GamePackage, socket: net.TCP_Socket) {
	// bytes := transmute([^]u8)&payload;
	payloadSlice := mem.slice_ptr(payload, 1)
	bytes := slice.to_bytes(payloadSlice)
	net.send_tcp(socket, bytes)
}

EXIT_CODE := [8]byte {101, 120, 105, 116, 13, 10, 0, 0}

@(private)
checkExitCode :: proc(data: []u8) -> bool {
	if len(data) < 8 do return false

	for b, index in data[:8] do if b != EXIT_CODE[index] do return false

	return true
}

PackageType :: enum {
	ERROR, EXIT, NONGAME, GAME
}

@(private)
readPackage :: proc($GamePackage: typeid, buffer: ^GamePackage, socket: net.TCP_Socket) -> PackageType {
	packageSize :: size_of(GamePackage)
	bufferSize :: max(packageSize, len(EXIT_CODE))
	payloadBuffer: [bufferSize]byte

	length, err := net.recv_tcp(socket, payloadBuffer[:])
	if err != nil {
		fmt.println("error while recieving data %s", err)
		return PackageType.ERROR
	}

	payload := payloadBuffer[:length]
	if checkExitCode(payload[:]) {
		fmt.println("connection ended")
		return PackageType.EXIT
	}
	if length != packageSize {
		fmt.println("package is netiher exit code nor game package")
		return PackageType.NONGAME
	}

	gamePackage := cast(^GamePackage)&payloadBuffer

	buffer^ = gamePackage^
	return PackageType.GAME
}