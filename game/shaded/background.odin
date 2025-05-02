package shaded

import rl "vendor:raylib"

import "../hex"

BackgroundState :: struct {
	noiseOffset: [2]f32,
}

BackgroundShader :: Shader(BackgroundState)

createBackgroundShader :: proc() -> BackgroundShader {
	shader := rl.LoadShader("shaders/default-vs.glsl", "shaders/background-fs.glsl")
	state: BackgroundState

	return Shader(BackgroundState){ shader, state }
}

updateBackgroundShader :: proc(shader: ^BackgroundShader, offset:= [2]f32 {0, 0}, zoom := f32(0)) {
	shader.state.noiseOffset += rl.GetFrameTime() * hex.BASIS_Y * 1.2

	rl.SetShaderValue(
		shader.shader,
		rl.GetShaderLocation(shader.shader, "noiseOffset"),
		&shader.state.noiseOffset,
		.VEC2
	)
}

deleteBackgroundShader :: proc(shader: BackgroundShader) {
	rl.UnloadShader(shader.shader)
}
