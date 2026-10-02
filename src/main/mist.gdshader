shader_type spatial;
render_mode unshaded, blend_mix;

// Настройки в инспекторе
uniform float blur_amount : hint_range(0.0, 5.0) = 2.0;      // Сила размытия
uniform float distortion : hint_range(0.0, 0.1) = 0.02;     // Сила искажения (стекло)
uniform sampler2D screen_texture : hint_screen_texture, filter_linear_mipmap;

void fragment() {
	// Добавляем легкое искажение на основе нормалей объекта (чтобы края преломляли свет)
	vec2 distortion_offset = NORMAL.xy * distortion;
	
	// Получаем координаты экрана с учетом искажения
	vec2 screen_uv = SCREEN_UV + distortion_offset;
	
	// Читаем пиксели экрана за объектом. blur_amount отвечает за уровень размытия (LOD)
	vec3 screen_color = textureLod(screen_texture, screen_uv, blur_amount).rgb;
	
	// Выводим финальный результат
	ALBEDO = screen_color;
}
