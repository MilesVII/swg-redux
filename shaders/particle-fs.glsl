#version 330

in vec3 fragPosition;
// x: corner in -1..1 plus seed * 4, y: corner in -1..1
in vec2 fragTexCoord;
// alpha is the particle coverage
in vec4 fragColor;

uniform float emissive;
uniform float hardShape;
uniform float ditherScale;
uniform vec4 lights[8];
uniform int lightCount;

out vec4 finalColor;

float bayer2(vec2 a) { a = floor(a); return fract(a.x / 2.0 + a.y * a.y * 0.75); }
float bayer4(vec2 a) { return bayer2(0.5 * a) * 0.25 + bayer2(a); }
float bayer8(vec2 a) { return bayer4(0.5 * a) * 0.25 + bayer2(a); }

float hash(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

float valueNoise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(
		mix(hash(i), hash(i + vec2(1.0, 0.0)), f.x),
		mix(hash(i + vec2(0.0, 1.0)), hash(i + vec2(1.0, 1.0)), f.x),
		f.y
	);
}

void main() {
	float seed = floor((fragTexCoord.x + 2.0) / 4.0);
	vec2 uv = vec2(fragTexCoord.x - seed * 4.0, fragTexCoord.y);

	float mask = 1.0;
	if (hardShape < 0.5) {
		float n = valueNoise(uv * 2.2 + seed * 7.31) * 0.6 + valueNoise(uv * 5.1 - seed * 3.7) * 0.4;
		mask = 1.0 - smoothstep(0.45, 1.0, length(uv) + (n - 0.5) * 0.55);
	}

	float coverage = fragColor.a * mask;
	// every particle dithers through its own pixels so overlapping puffs build up density
	float threshold = fract(bayer8(gl_FragCoord.xy / ditherScale) + seed * 0.618034);
	if (threshold >= coverage) discard;

	vec3 color = fragColor.rgb;
	if (emissive < 0.5) {
		// light from above, dense centers darker
		float n = valueNoise(uv * 3.0 + seed * 1.7);
		float shade = mix(0.5, 1.15, uv.y * 0.5 + 0.5) * mix(0.8, 1.05, length(uv)) * mix(0.85, 1.1, n);
		color *= shade;
		for (int i = 0; i < lightCount; i++) {
			vec3 toLight = lights[i].xyz - fragPosition;
			color += vec3(1.0, 0.55, 0.25) * lights[i].w * 0.6 / (1.0 + dot(toLight, toLight) * 1.5);
		}
	}
	finalColor = vec4(color, 1.0);
}
