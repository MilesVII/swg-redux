#version 330

const float MAG = 6.0;

uniform float progress;
uniform vec2 resolution;
uniform vec2 origin;
uniform sampler2D texture0;

float remap(float v, float fl, float fh, float tl, float th) {
	return (v - fl) / (fh - fl) * (th - tl) + tl;
}

void main() {
	vec2 fragCoord = gl_FragCoord.xy;
	vec2 originalPick = fragCoord;

	float dst = distance(origin, fragCoord) / length(resolution);
	float prg = progress;
	float xpl = remap(prg, 0.0, 1.0, -1.0, 2.0);
	float mag = clamp(1.0 - abs(dst - xpl), 0.0, 2.0);
	mag = pow(mag, 7.2);

	vec2 offset = normalize(originalPick - origin);
	vec2 sideOffset = vec2(-offset.y, offset.x);
	vec2 pickR = originalPick + (offset - sideOffset) * mag * MAG;
	vec2 pickG = originalPick;
	vec2 pickB = originalPick + (offset + sideOffset) * mag * MAG;

	float r = texture(texture0, pickR / resolution).r;
	float g = texture(texture0, pickG / resolution).g;
	float b = texture(texture0, pickB / resolution).b;
	gl_FragColor = vec4(r, g, b, 1.0);
}
