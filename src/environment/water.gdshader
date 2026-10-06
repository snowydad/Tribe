shader_type spatial;
render_mode blend_mix, depth_draw_always, cull_back;

// Цвета
uniform vec4 shallow_color : source_color = vec4(0.2, 0.75, 0.85, 0.6);
uniform vec4 deep_color : source_color = vec4(0.02, 0.15, 0.35, 0.95);
uniform vec4 foam_color : source_color = vec4(1.0, 1.0, 1.0, 1.0);

// Пена и скорость
uniform float foam_range : hint_range(0.1, 5.0) = 0.8;
uniform vec2 wave_speed1 = vec2(0.03, 0.01);  // Направление 1-й волны
uniform vec2 wave_speed2 = vec2(-0.02, 0.02); // Направление 2-й волны
uniform float normal_strength : hint_range(0.0, 5.0) = 1.2; // Выраженность ряби

// Текстуры
uniform sampler2D depth_texture : hint_depth_texture, filter_linear_mipmap;
uniform sampler2D noise_texture : hint_default_white, repeat_enable;
uniform sampler2D normal_map1 : hint_normal, repeat_enable;
uniform sampler2D normal_map2 : hint_normal, repeat_enable;

void fragment() {
	// 1. Движение двух карт нормалей навстречу друг другу
	vec2 uv1 = UV + TIME * wave_speed1;
	vec2 uv2 = UV + TIME * wave_speed2;
	
	vec3 n1 = texture(normal_map1, uv1).rgb;
	vec3 n2 = texture(normal_map2, uv2).rgb;
	
	// Смешиваем две нормали для создания рисунка ряби
	NORMAL_MAP = mix(n1, n2, 0.5);
	NORMAL_MAP_DEPTH = normal_strength;

	// 2. Расчет пены у берега острова
	float depth = texture(depth_texture, SCREEN_UV).r;
	vec4 upos = INV_PROJECTION_MATRIX * vec4(SCREEN_UV * 2.0 - 1.0, depth, 1.0);
	float pixel_depth = upos.z / upos.w;
	float depth_diff = VERTEX.z - pixel_depth;

	float noise_val = texture(noise_texture, UV + TIME * wave_speed1).r;
	float foam = smoothstep(foam_range * noise_val, 0.0, depth_diff);

	// 3. Цвет воды и блики
	float water_depth_factor = clamp(depth_diff * 0.3, 0.0, 1.0);
	vec3 water_color = mix(shallow_color.rgb, deep_color.rgb, water_depth_factor);
	
	ALBEDO = mix(water_color, foam_color.rgb, foam);
	ALPHA = mix(shallow_color.a, deep_color.a, water_depth_factor);
	
	// Маленький Roughness даёт мокрые солнечные блики на волнах
	ROUGHNESS = 0.08;
	SPECULAR = 0.6;
}