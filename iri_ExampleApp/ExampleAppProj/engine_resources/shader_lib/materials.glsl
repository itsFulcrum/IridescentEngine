
struct PbrMaterial {
	vec4 albedo;
	vec4 emissive; // .w contains emissive strength
	
	float roughness;
	float metallic;
	float alpha_value;
	uint alpha_mode;
};

struct UnlitMaterial {
	vec3  albedo_color;
	float alpha_value;
	uint  alpha_mode;

	uint padding1;
	uint padding2;
	uint padding3;
};