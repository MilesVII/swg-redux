package hex

import rl "vendor:raylib"
import "core:math"
import simplex "core:math/noise"
import "core:fmt"

fade :: proc(t: f32) -> f32 {
	return t * t * t * (t * (t * 6 - 15) + 10) - (t > .5 ? 0 : .017)
}

noise :: proc(at: rl.Vector2, zoom: f32) -> f32 {
	penis := [2]f64 {
		f64(at.x * zoom),
		f64(at.y * zoom)
	}
	return (simplex.noise_2d(0, penis) + 1) / 2
}

Octave :: struct {
	zoom: f32,
	factor: f32
}

height :: proc(at: rl.Vector2, levels: int) -> int {
	octaves := [?]Octave{
		{.1, .5},
		{.3, .3},
		{2, .2}
	}
	n: f32 = 0
	for octave in octaves {
		n += noise(at, octave.zoom) * octave.factor
	}
	n = fade(n)
	level := int(math.round(n * f32(levels - 1)))
	return clamp(level, 0, levels - 1)
}
