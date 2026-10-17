#version 330

in vec3 vertexPosition;
in vec3 vertexNormal;
in vec4 vertexColor;
// x: fade start time, y: target coverage
in vec2 vertexTexCoord;
// x: rim factor (0 at the hex center, 1 on its edge), y: 0 fades in, 1 fades out
in vec2 vertexTexCoord2;
// x: coverage of the look replacing this one (fade out only)
in vec4 vertexTangent;

uniform mat4 mvp;
uniform mat4 matModel;

out vec3 fragPosition;
out vec3 fragNormal;
out vec4 fragColor;
out vec2 fragFade;
out vec2 fragExtra;
out float fragOther;

void main() {
	fragPosition = (matModel * vec4(vertexPosition, 1.0)).xyz;
	fragNormal = vertexNormal;
	fragColor = vertexColor;
	fragFade = vertexTexCoord;
	fragExtra = vertexTexCoord2;
	fragOther = vertexTangent.x;
	gl_Position = mvp * vec4(vertexPosition, 1.0);
}
