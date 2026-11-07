@ctype mat4 Mat4f

@vs vs
//Uniforms
uniform mesh_normal_texture_vs_params {
    mat4 un_mvp;
    mat4 model;
    mat4 tex0_mat;
    //Model to shadow map texture space
    mat4 un_shadow;
    //Camera view, used for sphere mapped reflections
    mat4 view;
};

//Vertex Buffer inputs
layout(location=0) in vec3 vs_position;
layout(location=1) in vec3 vs_normal;
layout(location=2) in vec2 vs_texcoord0;
#if defined(SHADER_BUMP)
//Tangent space basis, S follows texture U and T follows texture V, normal acts as SxT
layout(location=3) in vec3 vs_tangent_s;
layout(location=4) in vec3 vs_tangent_t;
#endif

//Fragment shader outputs
layout(location=0) out vec3 fs_normal;
layout(location=1) out vec2 fs_uv0;
layout(location=3) out vec3 fs_shadow_uv;
layout(location=4) out vec3 fs_world_pos;
layout(location=8) out float fs_fog_z;
#if defined(SHADER_BUMP)
layout(location=5) out vec2 fs_uv1;
layout(location=6) out vec3 fs_tangent_s;
layout(location=7) out vec3 fs_tangent_t;
#else
//Sphere map coordinates from view space normal
layout(location=5) out vec2 fs_uv_reflection;
#endif

void main() {
    gl_Position = un_mvp * vec4(vs_position, 1.0f);
    fs_normal = (model * vec4(vs_normal, 0)).xyz;
    fs_uv0 = (tex0_mat * vec4(vs_texcoord0, 1, 1)).xy;
    fs_shadow_uv = (un_shadow * vec4(vs_position, 1.0f)).xyz;
    fs_world_pos = (model * vec4(vs_position, 1.0f)).xyz;
    fs_fog_z = gl_Position.w;
#if SOKOL_GLSL
    fs_shadow_uv.y = 1.0f - fs_shadow_uv.y;
#endif
#if defined(SHADER_BUMP)
    //Bump map uses untransformed texture coordinates
    fs_uv1 = vs_texcoord0;
    fs_tangent_s = (model * vec4(vs_tangent_s, 0)).xyz;
    fs_tangent_t = (model * vec4(vs_tangent_t, 0)).xyz;
#else
    fs_uv_reflection = (view * vec4(normalize(fs_normal), 0)).xy * 0.5 + 0.5;
#endif
}
@end
 
@fs fs
//Uniforms
uniform mesh_normal_texture_fs_params {
    vec4 diffuse;
    vec4 ambient;
    vec4 specular;
    vec4 emissive;
    vec3 light_dir;
    vec3 light_diffuse;
    vec3 light_ambient;
    vec3 light_specular;
    float spec_power; // specularPower
    float un_alpha_test;
    int material; // 0 - NONE; 1 - MAT_LIGHT
    int shadow; // 1 - apply shadow map
    //Point lights: xyz position and w is 1/radius^2, color is zero when unused
    vec4 point_pos0;
    vec4 point_color0;
    vec4 point_pos1;
    vec4 point_color1;
    int reflection; // 1 - add sphere mapped reflection texture from un_tex1
    vec4 fog_color;
    vec4 fog_params;
    //Camera position in world space, for specular highlights
    vec4 camera_pos;
};
uniform sampler un_sampler0;
uniform sampler un_sampler1; //shadow sampler
uniform texture2D un_tex0;
uniform texture2D un_tex3; //shadow map
#if defined(SHADER_BUMP)
//Normal map, RGB holds tangent space normal along S, T and SxT
uniform texture2D un_tex1;
#else
//Reflection texture
uniform texture2D un_tex1;
#endif

//Fragment shader inputs from Vertex shader
layout(location=0) in vec3 fs_normal;
layout(location=1) in vec2 fs_uv0;
layout(location=3) in vec3 fs_shadow_uv;
layout(location=4) in vec3 fs_world_pos;
layout(location=8) in float fs_fog_z;
#if defined(SHADER_BUMP)
layout(location=5) in vec2 fs_uv1;
layout(location=6) in vec3 fs_tangent_s;
layout(location=7) in vec3 fs_tangent_t;
#else
layout(location=5) in vec2 fs_uv_reflection;
#endif

//Fragment shader outputs
out vec4 frag_color;


const vec3 gamma_power = vec3(1.0/2.2);
const vec3 ambient_k = vec3(1);

//Color multiplier for fully shadowed area, same as SHADE in D3D shaders
const float shade = 0.5;
const float shadow_offset = 1.0 / 1024.0;

//Percentage closer filter over 4 samples, returns 1 when lit and 0 when shadowed
float shadow_lit() {
    float lit = texture(sampler2DShadow(un_tex3, un_sampler1), fs_shadow_uv + vec3(-shadow_offset, shadow_offset * 0.5, 0)).r;
    lit += texture(sampler2DShadow(un_tex3, un_sampler1), fs_shadow_uv + vec3(shadow_offset, -shadow_offset * 0.5, 0)).r;
    lit += texture(sampler2DShadow(un_tex3, un_sampler1), fs_shadow_uv + vec3(0, -shadow_offset, 0)).r;
    lit += texture(sampler2DShadow(un_tex3, un_sampler1), fs_shadow_uv + vec3(0, shadow_offset, 0)).r;
    return lit * 0.25;
}

//Point light attenuation as in D3D shaders: color / (1 + r^2 / radius^2)
vec3 point_light(vec4 pos, vec4 color) {
    vec3 delta = fs_world_pos - pos.xyz;
    return color.rgb / (1.0 + dot(delta, delta) * pos.w);
}

//Linear fog by camera depth like D3D: fog_params = (end, 1/(end-start), enabled, 0)
vec3 apply_fog(vec3 color, float depth, vec4 fog_color, vec4 fog_params) {
    if (fog_params.z <= 0.0) return color;
    float f = clamp((fog_params.x - depth) * fog_params.y, 0.0, 1.0);
    return mix(fog_color.rgb, color, f);
}

vec4 gamma(vec4 c) {
    return vec4(pow(abs(c.xyz), gamma_power), c.w);
}

vec4 phong(vec3 pos, vec3 nrm, vec3 l, vec3 eye,
            vec3 l_ambient, vec3 l_diffuse, vec3 l_specular,
            vec3 ambient, vec3 diffuse, vec3 specular, float spec_power) {
    vec3 n = normalize(nrm);
    vec3 v = normalize(eye - pos);
    float n_dot_l = max(dot(n, l), 0.0);
    vec3 r = reflect(-l, n);
    float r_dot_v = max(dot(r, v), 0.0);
    float diff = n_dot_l;
    float spec = pow(abs(r_dot_v), spec_power) * n_dot_l;
    vec3 ambient_v = l_ambient * ambient * ambient_k;
    vec3 diffuse_v = l_diffuse * diffuse * diff;
    vec3 specular_v = l_specular * specular * spec;
    return vec4(ambient_v + diffuse_v + specular_v, 1.0);
}

void main() {
    frag_color = texture(sampler2D(un_tex0, un_sampler0), fs_uv0);
#if defined(SHADER_BUMP)
    vec3 bump = texture(sampler2D(un_tex1, un_sampler0), fs_uv1).xyz * 2.0 - 1.0;
    vec3 normal = bump.x * normalize(fs_tangent_s)
                + bump.y * normalize(fs_tangent_t)
                + bump.z * normalize(fs_normal);
#else
    vec3 normal = fs_normal;
#endif
    if (material > 0) {
        frag_color = frag_color * gamma(
            phong(fs_world_pos, normal, -light_dir, camera_pos.xyz,
                    light_ambient, light_diffuse, light_specular,
                    ambient.xyz, diffuse.xyz, specular.xyz, spec_power
        ));
        //D3D added point lights to both diffuse (modulated by texture) and specular
        vec3 points = point_light(point_pos0, point_color0) + point_light(point_pos1, point_color1);
        frag_color.xyz += (texture(sampler2D(un_tex0, un_sampler0), fs_uv0).xyz + 1.0) * points;
        frag_color.a *= diffuse.a;
    } else {
        frag_color.xyz = frag_color.xyz * ambient.xyz * ambient_k;
    }
#if !defined(SHADER_BUMP)
    if (reflection > 0) {
        frag_color.xyz += texture(sampler2D(un_tex1, un_sampler0), fs_uv_reflection).xyz;
    }
#endif
    if (shadow > 0) {
        frag_color.xyz *= mix(shade, 1.0, shadow_lit());
    }
    frag_color.xyz = apply_fog(frag_color.xyz, fs_fog_z, fog_color, fog_params);
    if (un_alpha_test >= frag_color.a) {
        discard;
    }
}
@end

@program program vs fs