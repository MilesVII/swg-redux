#version 330

in vec2 fragCoord;

uniform vec2 noiseOffset;

out vec4 fragColor;

const vec2 BASIS_X = vec2(1.0, 0);
const vec2 BASIS_Y = vec2(0.5, 0.86602540378);

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
	vec2 uv = fragCoord;

	vec2 axial = worldToAxial(uv);

	float color = fracNoise(axial + noiseOffset) * 0.32;
	vec3 col = vec3(color, color, color);

	fragColor = vec4(col,1.0);
}
