package shaded

import rl "vendor:raylib"

ProgressHexState :: struct {
	value: f32,
	center: rl.Vector2
}

ProgressShader :: Shader(ProgressHexState)

createProgressShader :: proc() -> ProgressShader {
	shader := rl.LoadShader("shaders/prog-vs.glsl", "shaders/prog-fs.glsl");
	state: ProgressHexState

	return Shader(ProgressHexState){ shader, state }
}

updateProgressShader :: proc(shader: ProgressShader) {
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
}

deleteProgressHex :: proc(shader: ProgressShader) {
	rl.UnloadShader(shader.shader)
}
