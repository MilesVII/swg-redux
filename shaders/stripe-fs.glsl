#version 330

in vec4 fragColor;
out vec4 finalColor;

uniform float t;
uniform float width;
uniform vec2 direction;

void main() {
	float projected = dot(gl_FragCoord.xy, direction);
	float value = mod(projected, width) / width;
	float valueShifted = mod(value + t, 1.0);
	bool transparent = (valueShifted > 0.5);
	
	finalColor = transparent ? vec4(0, 0, 0, 0) : fragColor;
}
