#version 330

in vec2 fragCoord;
out vec4 fragColor;

uniform float progress;
uniform vec2 center;

void main() {
	vec2 uv = fragCoord - center;
	float angle = atan(uv.y, uv.x) / (2.0 * 3.14159265359) + 0.5;

	vec3 color = angle > progress ? vec3(1.0, 0.0, 0.0) : vec3(0, 1.0, 0.0);

	fragColor = vec4(color, 1.0);
}
