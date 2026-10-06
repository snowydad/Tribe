shader_type spatial;
render_mode blend_mix, depth_draw_always, cull_back;

uniform vec4 shallow_color : source_color = vec4(0.2, 0.75, 0.85, 0.6); // Цвет у берега
uniform vec4 deep_color : source_color = vec4(0.02, 0.15, 0.35, 0.95); // Цвет на глубине
uniform vec4 foam_color : source_color = vec4(1.0, 1.0, 1.0, 1.0);     // Цвет пены

uniform float foam_range : hint_range(0.1, 5.0) = 0.8;                  // Ширина пены
uniform vec2 wave_speed = vec2(0.03, 0.02);                             // Скорость волн

uniform sampler2D depth_texture : hint_depth_texture, filter_linear_mipmap;
uniform sampler2D noise_texture : hint_default_white, repeat_enable;

void fragment() {
	// 1. Считываем глубину из буфера Godot 4
	float depth = texture(depth_texture, SCREEN_UV).r;
	vec4 upos = INV_PROJECTION_MATRIX * vec4(SCREEN_UV * 2.0 - 1.0, depth, 1.0);
	float pixel_depth = upos.z / upos.w; // Глубина дна под водой
	
	// 2. Точная разница глубин в Godot 4 (VERTEX.z ближе, pixel_depth дальше)
	float depth_diff = VERTEX.z - pixel_depth;

	// 3. Текстура шума для неравномерности пены
	vec2 noise_uv = UV + TIME * wave_speed;
	float noise_val = texture(noise_texture, noise_uv).r;

	// 4. Пена появляется только там, где глубина меньше foam_range
	float foam = smoothstep(foam_range * noise_val, 0.0, depth_diff);

	// 5. Плавный переход цвета от мелководья к глубине
	float water_depth_factor = clamp(depth_diff * 0.3, 0.0, 1.0);
	vec3 water_color = mix(shallow_color.rgb, deep_color.rgb, water_depth_factor);
	
	ALBEDO = mix(water_color, foam_color.rgb, foam);
	ALPHA = mix(shallow_color.a, deep_color.a, water_depth_factor);
	ROUGHNESS = 0.05;
	SPECULAR = 0.8;
}