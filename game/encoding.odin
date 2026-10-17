package game

import "core:fmt"
import "core:encoding/cbor"

encode :: proc(data: $T) -> []u8 {
	bytes, err := cbor.marshal(data, cbor.Encoder_Flags{})
	if err != nil do fmt.panicf("failed to marshal value with \"%s\"", err)
	return bytes
}

// payloads come from the network, so a malformed one is reported instead of crashing
@(require_results)
decode :: proc(data: []u8, buffer: ^$T) -> bool {
	err := cbor.unmarshal(string(data), buffer, { .Trusted_Input })
	if err != nil {
		fmt.printfln("failed to unmarshal value with \"%v\"", err)
		return false
	}
	return true
}
