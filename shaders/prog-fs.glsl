#version 330

in vec2 fragCoord;
out vec4 fragColor;

uniform float progress;
uniform vec2 center;
uniform vec4 backColor;
uniform vec4 foreColor;

void main() {
	vec2 uv = fragCoord - center;
	float angle = atan(uv.y, uv.x) / (2.0 * 3.14159265359) + 0.5;

	fragColor = angle > progress ? backColor : foreColor;
}
