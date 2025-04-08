package shaded

import rl "vendor:raylib"

import "core:math"

import "../utils"

StripedState :: struct {
	width: f32,
	direction: rl.Vector2
}

StripedShader :: Shader(StripedState)

createStripedShader :: proc() -> StripedShader {
	shader := rl.LoadShader(nil, "shaders/stripe-fs.glsl")
	state: StripedState

	return Shader(StripedState){ shader, state }
}

updateStripedShader :: proc(shader: StripedShader) {
	shader := shader
	t := utils.flicker

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
