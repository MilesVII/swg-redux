package shaded

import rl "vendor:raylib"

import "core:math"

StripedState :: struct {
	period: f32,
	width: f32,
	direction: rl.Vector2
}

StripedShader :: Shader(StripedState)

createStripedShader :: proc() -> StripedShader {
	shader := rl.LoadShader(nil, "shaders/stripe-fs.glsl");
	state: StripedState

	return Shader(StripedState){ shader, state }
}

updateStripedShader :: proc(shader: StripedShader) {
	shader := shader
	t := math.mod(f32(rl.GetTime()), shader.state.period) / shader.state.period

	rl.SetShaderValue(
		shader.shader,
		rl.GetShaderLocation(shader.shader, "t"),
		&t,
		.FLOAT
	)
	rl.SetShaderValue(
		shader.shader,
		rl.GetShaderLocation(shader.shader, "width"),
		&shader.state.width,
		.FLOAT
	)
	rl.SetShaderValue(
		shader.shader,
		rl.GetShaderLocation(shader.shader, "direction"),
		&shader.state.direction,
		.VEC2
	)
}

deleteStripedShader :: proc(shader: StripedShader) {
	rl.UnloadShader(shader.shader)
}
