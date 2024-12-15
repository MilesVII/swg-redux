package utils

import rl "vendor:raylib"

TAU :: (rl.PI * 2)

includes :: proc(array: ^[dynamic]$T, value: ^T) -> bool {
	for v in array {
		if v == value^ do return true
	}
	return false
}
