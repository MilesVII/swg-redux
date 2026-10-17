package shaded

import rl "vendor:raylib"

PostFXState :: struct {
	windowSize: [2]f32,
	elapsedTime: f32,
	oddFrame: bool,
	// 0 shows the original image, 1 the full effect
	intensity: f32,
	// interference, blur, scanlines
	distortion: f32,
	// color shifts and smearing
	decoloration: f32,
	// size of a virtual CRT pixel, 1 keeps the look of a 640x480 window at any size
	pixelScale: f32,
}

PostFXShader :: Shader(PostFXState)

createPostFXShader :: proc() -> PostFXShader {
	shader := rl.LoadShader("shaders/default-vs.glsl", "shaders/postfx-fs.glsl")
	state := PostFXState { intensity = 1, distortion = 1, decoloration = 1, pixelScale = 1 }

	return Shader(PostFXState){ shader, state }
}

updatePostFXShader :: proc(shader: ^PostFXShader) {
	fmod :: proc(v: f32, limit: f32) -> f32 {
		v := v
		for v >= limit do v -= limit
		return v
	}

	shader.state.elapsedTime = fmod(shader.state.elapsedTime + rl.GetFrameTime(), 1000)
	shader.state.oddFrame = !shader.state.oddFrame
	shaderState := shader.state
	oddFrame := shaderState.oddFrame ? 1 : 0

	rl.SetShaderValue(
		shader.shader,
		rl.GetShaderLocation(shader.shader, "windowSize"),
		&shaderState.windowSize,
		.VEC2
	)
	rl.SetShaderValue(
		shader.shader,
		rl.GetShaderLocation(shader.shader, "elapsedTime"),
		&shaderState.elapsedTime,
		.FLOAT
	)
	rl.SetShaderValue(
		shader.shader,
		rl.GetShaderLocation(shader.shader, "oddFrame"),
		&oddFrame,
		.INT
	)
	setFloat :: proc(shader: rl.Shader, name: cstring, value: f32) {
		value := value
		rl.SetShaderValue(shader, rl.GetShaderLocation(shader, name), &value, .FLOAT)
	}
	setFloat(shader.shader, "intensity", shaderState.intensity)
	setFloat(shader.shader, "distortion", shaderState.distortion)
	setFloat(shader.shader, "decoloration", shaderState.decoloration)
	setFloat(shader.shader, "pixelScale", shaderState.pixelScale)
}

deletePostFXShader :: proc(shader: PostFXShader) {
	rl.UnloadShader(shader.shader)
}
