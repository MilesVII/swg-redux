#version 330

in vec3 vertexPosition;

uniform mat4 mvp;

out vec2 fragCoord;

void main() {
	fragCoord = vertexPosition.xz;
	gl_Position = mvp * vec4(vertexPosition, 1.0);
}
