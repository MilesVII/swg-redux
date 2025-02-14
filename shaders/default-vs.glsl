#version 330

// worldspace
in vec3 vertexPosition;
in vec4 vertexColor;

uniform mat4 mvp;

// worldspace
out vec2 fragCoord;
out vec4 fragColor;

void main() {
	vec4 projected = mvp * vec4(vertexPosition, 1.0);
	fragCoord = vertexPosition.xy;
	// screenspace
	gl_Position = projected;
	fragColor = vertexColor;
}
