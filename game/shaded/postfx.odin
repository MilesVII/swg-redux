package shaded

import rl "vendor:raylib"

PostFXState :: struct {
	windowSize: [2]f32,
	elapsedTime: f32,
	oddFrame: bool,
}

PostFXShader :: Shader(PostFXState)

createPostFXShader :: proc() -> PostFXShader {
	shader := rl.LoadShader("shaders/default-vs.glsl", "shaders/postfx-fs.glsl")
	state: PostFXState

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
}

deletePostFXShader :: proc(shader: PostFXShader) {
	rl.UnloadShader(shader.shader)
}
