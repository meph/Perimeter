@ctype mat4 Mat4f

//Chaos (energy sea) surface with bump distortion, port of D3D9 shader/Chaos/chaos.psh

@vs vs
//Uniforms
uniform chaos_vs_params {
    mat4 un_mvp;
    //Scroll offsets of surface layers (0 and 1) and bump layers (2 and 3)
    mat4 tex0_mat;
    mat4 tex1_mat;
    mat4 tex2_mat;
    mat4 tex3_mat;
};

//Vertex Buffer inputs
layout(location=0) in vec3 vs_position;
layout(location=1) in vec4 vs_color;
layout(location=2) in vec2 vs_texcoord0;

//Fragment shader outputs
layout(location=0) out vec4 fs_color;
layout(location=1) out vec2 fs_uv0;
layout(location=2) out vec2 fs_uv1;
layout(location=3) out vec2 fs_uv2;
layout(location=4) out vec2 fs_uv3;

void main() {
    gl_Position = un_mvp * vec4(vs_position, 1.0f);
    fs_color = vs_color;
    fs_uv0 = (tex0_mat * vec4(vs_texcoord0, 1, 1)).xy;
    fs_uv1 = (tex1_mat * vec4(vs_texcoord0, 1, 1)).xy;
    fs_uv2 = (tex2_mat * vec4(vs_texcoord0, 1, 1)).xy;
    fs_uv3 = (tex3_mat * vec4(vs_texcoord0, 1, 1)).xy;
}
@end

@fs fs
uniform sampler un_sampler0;
//Surface layers
uniform texture2D un_tex0;
uniform texture2D un_tex1;
//Bump map
uniform texture2D un_tex2;

//Fragment shader inputs from Vertex shader
layout(location=0) in vec4 fs_color;
layout(location=1) in vec2 fs_uv0;
layout(location=2) in vec2 fs_uv1;
layout(location=3) in vec2 fs_uv2;
layout(location=4) in vec2 fs_uv3;

//Fragment shader outputs
out vec4 frag_color;

//Strength of distortion, same as CC in original shader
const float bump_k = 0.1;

void main() {
    //Two scrolling samples of bump map give the texture coordinate offset
    vec2 offset = (texture(sampler2D(un_tex2, un_sampler0), fs_uv2).xy
                 + texture(sampler2D(un_tex2, un_sampler0), fs_uv3).xy) * bump_k;
    vec4 c0 = texture(sampler2D(un_tex0, un_sampler0), fs_uv0 + offset);
    vec4 c1 = texture(sampler2D(un_tex1, un_sampler0), fs_uv1 + offset);
    frag_color = (c0 + c1) * fs_color;
}
@end

@program program vs fs
