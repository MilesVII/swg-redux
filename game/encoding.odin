package game

import "core:fmt"
import "core:encoding/cbor"

encode :: proc(data: $T) -> []u8 {
	bytes, err := cbor.marshal(data, cbor.Encoder_Flags{})
	if err != nil do fmt.panicf("failed to marshal grid with \"%s\"", err)
	return bytes
}

decode :: proc(data: []u8, buffer: ^$T) {
	err := cbor.unmarshal(string(data), buffer, { .Trusted_Input })
	if err != nil do fmt.panicf("failed to unmarshal grid with \"%s\"", err)
}
