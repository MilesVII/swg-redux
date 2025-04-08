package shaded

import rl "vendor:raylib"

SweepState :: struct {
	value: f32,
	center: rl.Vector2,
	radius: f32,
}

SweepShader :: Shader(SweepState)

createSweepShader :: proc() -> SweepShader {
	shader := rl.LoadShader("shaders/default-vs.glsl", "shaders/sweep-fs.glsl")
	state: SweepState

	return Shader(SweepState){ shader, state }
}

updateSweepShader :: proc(shader: SweepShader) {
	shader := shader
	rl.SetShaderValue(
		shader.shader,
		rl.GetShaderLocation(shader.shader, "progress"),
		&shader.state.value,
		.FLOAT
	)
	rl.SetShaderValue(
		shader.shader,
		rl.GetShaderLocation(shader.shader, "center"),
		&shader.state.center,
		.VEC2
	)
	rl.SetShaderValue(
		shader.shader,
		rl.GetShaderLocation(shader.shader, "radius"),
		&shader.state.radius,
		.FLOAT
	)
}

deleteSweepShader :: proc(shader: SweepShader) {
	rl.UnloadShader(shader.shader)
}
