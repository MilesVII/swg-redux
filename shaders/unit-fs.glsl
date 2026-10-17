#version 330

in vec3 fragPosition;
in vec2 fragTexCoord;
in vec3 fragNormal;
in vec4 fragColor;

uniform sampler2D texture0;
uniform vec4 colDiffuse;
uniform float coverage;
uniform float glow;
uniform float ditherScale;
uniform vec3 sunDirection;
uniform vec4 lights[8];
uniform int lightCount;

out vec4 finalColor;

float bayer2(vec2 a) { a = floor(a); return fract(a.x / 2.0 + a.y * a.y * 0.75); }
float bayer4(vec2 a) { return bayer2(0.5 * a) * 0.25 + bayer2(a); }
float bayer8(vec2 a) { return bayer4(0.5 * a) * 0.25 + bayer2(a); }

void main() {
	if (bayer8(gl_FragCoord.xy / ditherScale) >= coverage) discard;

	vec4 albedo = texture(texture0, fragTexCoord) * colDiffuse * fragColor;
	vec3 normal = normalize(fragNormal);
	float diffuse = max(dot(normal, sunDirection), 0.0);
	vec3 color = albedo.rgb * (0.4 + 0.6 * diffuse);

	for (int i = 0; i < lightCount; i++) {
		vec3 toLight = lights[i].xyz - fragPosition;
		float d2 = dot(toLight, toLight);
		float facing = max(dot(normal, normalize(toLight)), 0.0) * 0.7 + 0.3;
		color += vec3(1.0, 0.62, 0.3) * lights[i].w * facing / (1.0 + d2 * 1.8);
	}

	color += albedo.rgb * glow;
	finalColor = vec4(color, 1.0);
}
