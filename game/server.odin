package game

import "core:fmt"
import "core:net"
import "core:strings"
import "core:bytes"

PORT :: 8000

server :: proc() {
	socket, err := net.listen_tcp(net.Endpoint{
		port = PORT,
		address = net.IP4_Loopback
	})
	if err != nil {
		fmt.panicf("listen error : %s", err)
	}

	clientSocket, clientEndpoint, acceptErr := net.accept_tcp(socket)

	if acceptErr != nil {
		fmt.panicf("%s",acceptErr)
	}

	handleClient(clientSocket)
}


GAME_PACKAGE :: union {
	struct {
		id: i32
	},
	[8]byte
}
PACKAGE_SIZE :: size_of(GAME_PACKAGE)

EXIT_CODE := [8]byte {101, 120, 105, 116, 13, 10, 0, 0}

checkExitCode :: proc(data: []u8) -> bool {
	if len(data) < 8 do return false

	for b, index in data[:8] do if b != EXIT_CODE[index] do return false

	return true
}

handleClient :: proc(client_soc: net.TCP_Socket) {
	for {
		payload: [PACKAGE_SIZE]byte

		_ ,err := net.recv_tcp(client_soc, payload[:])
		if err != nil {
			fmt.panicf("error while recieving data %s", err)
		}
		
		if checkExitCode(payload[:]) {
			fmt.println("connection ended")
			break
		}
		// converting bytes data to string
		data, e := strings.clone_from_bytes(payload[:], context.allocator)
		fmt.println("client said: ", data)
	}
}