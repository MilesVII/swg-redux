package shaded

import rl "vendor:raylib"

ProgressHexState :: struct {
	value: f32,
	center: rl.Vector2,
	backColor: rl.Color,
	foreColor: rl.Color
}

ProgressShader :: Shader(ProgressHexState)

PROGRESS_FILL_TIME_S := f32(.320)

createProgressShader :: proc() -> ProgressShader {
	shader := rl.LoadShader("shaders/default-vs.glsl", "shaders/prog-fs.glsl")
	state: ProgressHexState

	return Shader(ProgressHexState){ shader, state }
}

@(private="file")
convertColor :: proc(color: rl.Color) -> [4]f32 {
	return [4]f32 {
		f32(color.r) / 255,
		f32(color.g) / 255,
		f32(color.b) / 255,
		f32(color.a) / 255,
	}
}

updateProgressShader :: proc(shader: ProgressShader) {
	shader := shader
	colorB := convertColor(shader.state.backColor)
	colorF := convertColor(shader.state.foreColor)
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
		rl.GetShaderLocation(shader.shader, "backColor"),
		&colorB,
		.VEC4
	)
	rl.SetShaderValue(
		shader.shader,
		rl.GetShaderLocation(shader.shader, "foreColor"),
		&colorF,
		.VEC4
	)
}

deleteProgressHex :: proc(shader: ProgressShader) {
	rl.UnloadShader(shader.shader)
}
