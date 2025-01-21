package shaded

import rl "vendor:raylib"

ShockState :: struct {
	progress: f32,
	resolution: rl.Vector2,
	origin: rl.Vector2,
}

ShockShader :: Shader(ShockState)

createShockShader :: proc() -> ShockShader {
	shader := rl.LoadShader(nil, "shaders/shock-fs.glsl");
	state: ShockState

	return ShockShader{ shader, state }
}

updateShockShader :: proc(shader: ShockShader, tex: rl.RenderTexture2D) {
	shader := shader
	rl.SetShaderValue(
		shader.shader,
		rl.GetShaderLocation(shader.shader, "progress"),
		&shader.state.progress,
		.FLOAT
	)
	rl.SetShaderValue(
		shader.shader,
		rl.GetShaderLocation(shader.shader, "resolution"),
		&shader.state.resolution,
		.VEC2
	)
	rl.SetShaderValue(
		shader.shader,
		rl.GetShaderLocation(shader.shader, "origin"),
		&shader.state.origin,
		.VEC2
	)
}

deleteShockShader :: proc(shader: ShockShader) {
	rl.UnloadShader(shader.shader)
}
