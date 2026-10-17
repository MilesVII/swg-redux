package hex

import rl "vendor:raylib"
import "core:math"
import simplex "core:math/noise"

fade :: proc(t: f32) -> f32 {
	return t * t * t * (t * (t * 6 - 15) + 10) - (t > .5 ? 0 : .017)
}

noise :: proc(at: rl.Vector2, zoom: f32, seed := i64(0)) -> f32 {
	penis := [2]f64 {
		f64(at.x * zoom),
		f64(at.y * zoom)
	}
	return (simplex.noise_2d(seed, penis) + 1) / 2
}

Octave :: struct {
	zoom: f32,
	factor: f32
}

// continuous terrain height, roughly 0..1
elevation :: proc(at: rl.Vector2, seed := i64(0)) -> f32 {
	octaves := [?]Octave{
		{.1, .5},
		{.3, .3},
		{2, .2}
	}
	n: f32 = 0
	for octave in octaves {
		n += noise(at, octave.zoom, seed) * octave.factor
	}
	return fade(n)
}

height :: proc(at: rl.Vector2, levels: int, seed := i64(0)) -> int {
	return heightLevel(elevation(at, seed), levels)
}

heightLevel :: proc(elevation: f32, levels: int) -> int {
	level := int(math.round(elevation * f32(levels - 1)))
	return clamp(level, 0, levels - 1)
}
