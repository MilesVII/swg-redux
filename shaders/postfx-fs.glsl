#version 330
// https://www.shadertoy.com/view/3tVBWR

uniform sampler2D texture0;
uniform vec2 windowSize;
uniform float elapsedTime;
uniform int oddFrame;

out vec4 fragColor;

#define PI 3.14159265

#define BRIGHTNESS 1.0
#define SATURATION 0.75
#define BLUR 0.32
#define BLURSIZE 0.3
#define CHROMABLUR 0.23
#define CHROMASIZE 6.0
#define SUBCARRIER 1.1 //ripple
#define CROSSTALK 0.3 //ribbed pixels for pleasure
#define SCANFLICKER 0.0 //lines marching
#define INTERFERENCE1 1.5 //wind
#define INTERFERENCE2 0.003 //bottom gore
#define SCAN_DEFECT 0.2

const float XRES = 432.0;
const float YRES = 264.0;

// RGB -> YIQ
const mat3 yiq_mat = mat3(
	0.2989, 0.5959, 0.2115,
	0.5870, -0.2744, -0.5229,
	0.1140, -0.3216, 0.3114
);

// YIQ -> RGB
const mat3 yiq2rgb_mat = mat3(
	1.0, 1.0, 1.0,
	0.956, -0.2720, -1.1060,
	0.6210, -0.6474, 1.7046
);

#define KERNEL 25
const float luma_filter[KERNEL] = float[KERNEL](0.0105,0.0134,0.0057,-0.0242,-0.0824,-0.1562,-0.2078,-0.185,-0.0546,0.1626,0.3852,0.5095,0.5163,0.4678,0.2844,0.0515,-0.1308,-0.2082,-0.1891,-0.1206,-0.0511,-0.0065,0.0114,0.0127,0.008);
const float chroma_filter[KERNEL] = float[KERNEL](0.001,0.001,0.0001,0.0002,-0.0003,0.0062,0.012,-0.0079,0.0978,0.1059,-0.0394,0.2732,0.2941,0.1529,-0.021,0.1347,0.0415,-0.0032,0.0115,0.002,-0.0001,0.0002,0.001,0.001,0.001);

float hash12(vec2 p) {
	vec3 p3  = fract(vec3(p.xyx) * .1031);
	p3 += dot(p3, p3.yzx + 33.33);
	return fract((p3.x + p3.y) * p3.z);
}

float random(vec2 p, float t) {
	return hash12((p * 0.152 + t * 1500. + 50.0));
}

float peak(float x, float xpos, float scale) {
	return clamp((1.0 - x) * scale * log(1.0 / abs(x - xpos)), 0.0, 1.0);
}

vec3 get(vec2 uv, float off, float d, float yscale) {
	float offd = off * d;
	return texture(texture0, uv + vec2(offd, yscale * offd)).rgb;
}

void main() {
	vec2 uv = gl_FragCoord.xy / windowSize.xy;
	float scany = round(uv.y * YRES);

	float mframe = float(oddFrame % 2);
	float mscanl = mod(uv.y * YRES, 2.0);

	// --- STAGE 1: ENCODE TO NTSC-LIKE SIGNAL ---
	vec3 color = texture(texture0, uv).rgb;
	vec3 signalEnc = yiq_mat * color;
	vec2 chroma = vec2(signalEnc.y, signalEnc.z);
	float lchromaEnc = length(chroma);
	float phaseEnc = atan(signalEnc.y, signalEnc.z);

	phaseEnc += -0.3926991 + mscanl * 0.19634954; // line phase shift (22.5 deg)

	vec3 ntscSignal = vec3(signalEnc.x, lchromaEnc, phaseEnc / (2.0 * PI)); // final encoded signal

	// --- STAGE 2: DECODE CRT FROM SIGNAL (like old shader) ---
	uv.y += mframe * 1.0 / YRES * SCANFLICKER;

	float r = random(vec2(0.0, scany), elapsedTime);
	if (r > 0.995) r *= 3.0;
	float ifx1 = INTERFERENCE1 * 2.0 / windowSize.x * r;
	float ifx2 = INTERFERENCE2 * (r * peak(uv.y, 0.2, 0.2));
	uv.x += ifx1 - ifx2;

	float d = 1.0 / XRES * (BLURSIZE + ifx2 * 100.0);
	vec3 lsignal = vec3(0.0);
	vec3 csignal = vec3(0.0);
	for (int i = 0; i < KERNEL; i++) {
		float offset = float(i) - 12.0;
		vec3 l = get(uv, offset, d, 0.67);
		l = yiq_mat * l;
		lsignal += l * vec3(luma_filter[i], 0.0, 0.0);

		vec3 c = get(uv, offset, d * CHROMASIZE, 0.67);
		c = yiq_mat * c;
		csignal += c * vec3(0.0, chroma_filter[i], chroma_filter[i]);
	}

	vec3 lumat = ntscSignal * vec3(1.0, 0.0, 0.0);
	vec3 chroat = ntscSignal * vec3(0.0, 1.0, 1.0);
	vec3 signal = lumat * (1.0 - BLUR) + BLUR * lsignal + chroat * (1.0 - CHROMABLUR) + CHROMABLUR * csignal;

	float scanl = 0.5 + 0.5 * abs(sin(PI * uv.y * YRES));
	scanl = mix(1.0, scanl, SCAN_DEFECT);

	float lchroma = signal.y * SATURATION;
	float phase = signal.z * 2.0 * PI;

	signal.x *= BRIGHTNESS;
	signal.y = lchroma * sin(phase);
	signal.z = lchroma * cos(phase);

	float chroma_phase = elapsedTime * 60.0 * PI * 0.6667;
	float mod_phase = chroma_phase + (uv.x + uv.y * 0.1) * (0.4 * PI) * XRES * 2.0;
	float scarrier = SUBCARRIER * lchroma;

	float i_mod = cos(mod_phase);
	float q_mod = sin(mod_phase);

	signal.x *= CROSSTALK * scarrier * q_mod + 1.0 - ifx2 * 30.0;
	signal.y *= scarrier * i_mod + 1.0;
	signal.z *= scarrier * q_mod + 1.0;

	vec3 out_color = scanl * (yiq2rgb_mat * signal);
	fragColor = vec4(out_color, 1.0);
}
