
struct PbrMaterial {
	vec4 albedo;
	vec4 emissive; // .w contains emissive strength
	
	float roughness;
	float metallic;
	float alpha_value;
	uint alpha_mode;
};