#version 330

in vec3 vertexPosition;

uniform mat4 mvp;

out vec2 fragCoord;

void main() {
	vec4 projected = mvp * vec4(vertexPosition, 1.0);
	fragCoord = vertexPosition.xy;
	gl_Position = projected;
}
