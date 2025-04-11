package game

import "core:fmt"
import "core:encoding/json"
// import "core:encoding/cbor"

encode :: proc(data: $T) -> []u8 {
	bytes, err := json.marshal(data, {
		pretty = true
	})
	if err != nil do fmt.panicf("failed to marshal grid with \"%s\"", err)
	return bytes
}

decode :: proc(data: []u8, buffer: ^$T) {
	err := json.unmarshal(data, buffer)
	if err != nil do fmt.panicf("failed to unmarshal grid with \"%s\"", err)
}

// encode :: proc(data: $T) -> string {
// 	bytes, err := cbor.marshal(data)
// 	if err != nil do fmt.panicf("failed to marshal grid with \"%s\"", err)
// 	// fmt.println("marshed ", len(bytes), " bytes")
// 	return transmute(string)bytes
// }

// decode :: proc(data: string, buffer: ^$T) {
// 	// fmt.println("unmarshing ", len(gridData), " bytes")
// 	err := cbor.unmarshal(data, buffer)
// 	if err != nil do fmt.panicf("failed to unmarshal grid with \"%s\"", err)
// }
