#version 330
// flat colored shapes faded by ordered dithering instead of blending, alpha is the coverage

in vec2 fragTexCoord;
in vec4 fragColor;

uniform float ditherScale;

out vec4 finalColor;

float bayer2(vec2 a) { a = floor(a); return fract(a.x / 2.0 + a.y * a.y * 0.75); }
float bayer4(vec2 a) { return bayer2(0.5 * a) * 0.25 + bayer2(a); }
float bayer8(vec2 a) { return bayer4(0.5 * a) * 0.25 + bayer2(a); }

void main() {
	if (bayer8(gl_FragCoord.xy / max(ditherScale, 1.0)) >= fragColor.a) discard;
	finalColor = vec4(fragColor.rgb, 1.0);
}
