#version 330
// the backdrop of the 2D client laid on the ground plane, fading out past the map edge

in vec2 fragCoord;

uniform vec2 noiseOffset;
uniform float mapRadius;
uniform float ditherScale;

out vec4 finalColor;

const vec2 BASIS_X = vec2(1.0, 0);
const vec2 BASIS_Y = vec2(0.5, 0.86602540378);

float bayer2(vec2 a) { a = floor(a); return fract(a.x / 2.0 + a.y * a.y * 0.75); }
float bayer4(vec2 a) { return bayer2(0.5 * a) * 0.25 + bayer2(a); }
float bayer8(vec2 a) { return bayer4(0.5 * a) * 0.25 + bayer2(a); }

// https://www.shadertoy.com/view/Msf3WH
vec2 hash(vec2 p) {
	p = vec2(dot(p,vec2(127.1,311.7)), dot(p,vec2(269.5,183.3)));
	return -1.0 + 2.0*fract(sin(p)*43758.5453123);
}

float noise(in vec2 p) {
	const float K1 = 0.366025404; // (sqrt(3)-1)/2;
	const float K2 = 0.211324865; // (3-sqrt(3))/6;

	vec2  i = floor( p + (p.x+p.y)*K1 );
	vec2  a = p - i + (i.x+i.y)*K2;
	float m = step(a.y,a.x); 
	vec2  o = vec2(m,1.0-m);
	vec2  b = a - o + K2;
	vec2  c = a - 1.0 + 2.0*K2;
	vec3  h = max( 0.5-vec3(dot(a,a), dot(b,b), dot(c,c) ), 0.0 );
	vec3  n = h*h*h*h*vec3( dot(a,hash(i+0.0)), dot(b,hash(i+o)), dot(c,hash(i+1.0)));
	return dot( n, vec3(70.0) );
}

float fracNoise(vec2 v) {
	vec2 uv = v * 0.05;

	mat2 m = mat2( 1.6, 1.2, -1.2, 1.6 );
	float f = 0.5000 * noise(uv); uv = m * uv;
	f += 0.2500 * noise(uv); uv = m * uv;
	f += 0.1250 * noise(uv); uv = m * uv;
	f += 0.0625 * noise(uv); uv = m * uv;

	return 0.5 + 0.5 * f;
}

vec2 axialToWorld(vec2 v) {
	return BASIS_X * v.x + BASIS_Y * v.y;
}

// https://www.redblobgames.com/grids/hexagons/more-pixel-to-hex.html#justin-pombrio
vec2 worldToAxial(vec2 v) {
	float sqrt3 = sqrt(3.0);
	float size = 1.0 / sqrt3;

	vec2 f = vec2(
		(sqrt3 / 3.0 * v.x - 1.0 / 3.0 * v.y),
		2.0 / 3.0 * v.y
	) / size;

	float fZ = -f.x - f.y;
	float a = ceil(f.x - f.y);
	float b = ceil(f.y - fZ);
	float c = ceil(fZ - f.x);

	return vec2(
		round((a - c) / 3.0),
		round((b - a) / 3.0)
	);
}

void main() {
	float edge = 1.0 - smoothstep(mapRadius + 1.0, mapRadius + 14.0, length(fragCoord));
	if (bayer8(gl_FragCoord.xy / ditherScale) >= edge) discard;

	vec2 axial = worldToAxial(fragCoord);
	float value = fracNoise(axial + noiseOffset) * 0.32;
	finalColor = vec4(vec3(value), 1.0);
}
