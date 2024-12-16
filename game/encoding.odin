package game

import "core:fmt"
import "core:encoding/json"

encode :: proc(data: $T) -> string {
	bytes, err := json.marshal(data, {
		pretty = true
	})
	if err != nil do fmt.panicf("failed to marshal grid with \"%s\"", err)
	// fmt.println("marshed ", len(bytes), " bytes")
	return transmute(string)bytes
}

decode :: proc(data: string, buffer: ^$T) {
	// fmt.println("unmarshing ", len(gridData), " bytes")
	err := json.unmarshal(transmute([]byte)data, buffer)
	if err != nil do fmt.panicf("failed to unmarshal grid with \"%s\"", err)
}
