#version 330

in vec2 fragCoord;
in vec4 fragColor;
out vec4 finalColor;

uniform float progress;
// worldspace
uniform vec2 center;
// worldspace
uniform float radius;

void main() {
	float offset = distance(fragCoord, center) / radius;
	float lo = progress * 2.0 - 1.0;
	float hi = progress * 2.0;

	finalColor = (offset >= lo && offset < hi) ? fragColor : vec4(.0, .0, .0, .0);
}
