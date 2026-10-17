#version 330

in vec3 fragPosition;
in vec3 fragNormal;
in vec4 fragColor;
in vec2 fragFade;
in vec2 fragExtra;
in float fragOther;

uniform float time;
uniform float fadeDuration;
uniform float ditherScale;
uniform vec3 sunDirection;
// xyz: position, w: intensity
uniform vec4 lights[8];
uniform int lightCount;

out vec4 finalColor;

// ordered dithering threshold in [0, 1)
float bayer2(vec2 a) { a = floor(a); return fract(a.x / 2.0 + a.y * a.y * 0.75); }
float bayer4(vec2 a) { return bayer2(0.5 * a) * 0.25 + bayer2(a); }
float bayer8(vec2 a) { return bayer4(0.5 * a) * 0.25 + bayer2(a); }

vec3 flashLight(vec3 position, vec3 normal) {
	vec3 sum = vec3(0.0);
	for (int i = 0; i < lightCount; i++) {
		vec3 toLight = lights[i].xyz - position;
		float d2 = dot(toLight, toLight);
		float facing = max(dot(normal, normalize(toLight)), 0.0) * 0.7 + 0.3;
		sum += vec3(1.0, 0.62, 0.3) * lights[i].w * facing / (1.0 + d2 * 1.8);
	}
	return sum;
}

void main() {
	float progress = clamp((time - fragFade.x) / fadeDuration, 0.0, 1.0);
	float threshold = bayer8(gl_FragCoord.xy / ditherScale);

	if (fragExtra.y < 0.5) {
		if (threshold >= fragFade.y * progress) discard;
	} else {
		// leave the pixels the replacing look already took
		if (threshold >= fragFade.y * (1.0 - progress)) discard;
		if (threshold < fragOther * progress) discard;
	}

	vec3 normal = normalize(fragNormal);
	float diffuse = max(dot(normal, sunDirection), 0.0);
	vec3 color = fragColor.rgb * (0.38 + 0.62 * diffuse);

	// darker hex outlines on tile tops
	color *= mix(1.0, 0.62, smoothstep(0.88, 0.98, fragExtra.x));

	vec3 flash = flashLight(fragPosition, normal);
	color += (fragColor.rgb + 0.25) * flash;
	finalColor = vec4(color, 1.0);
}
