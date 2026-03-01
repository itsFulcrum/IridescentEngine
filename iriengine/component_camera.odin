package iri

import "core:math/linalg"
import "odinary:mathy"

CameraComponent :: struct{
	using common : ComponentCommon,

	fov_deg:   f32,
	near_clip: f32,
	far_clip:  f32,

	exposure_correction : f32,

	// physical camera
	// TODO: maybe implment focal lenght and sensor size ?
	iso : f32,
	shutter_speed : f32,
	aperture : f32,
}

@(private="package")
comp_camera_init :: proc (comp: ^CameraComponent){
	if(comp == nil){
		return;
	}

	#force_inline comp_camera_set_defaults(comp);
}

@(private="package")
comp_camera_deinit :: proc(comp: ^CameraComponent){
	// if(comp == nil){
	// 	return;
	// }
}

comp_camera_set_defaults :: proc(comp: ^CameraComponent) {
	
	if(comp == nil){
		return;
	}

	comp.fov_deg = 65.0;
	comp.near_clip = 0.01;
	comp.far_clip = 1000.0;

	comp.aperture = 1.4;
	comp.shutter_speed = 1.0/500.0;
	comp.iso = 100.0;
	comp.exposure_correction = 0.0;
}

// =====================================================================
// Component procedures
// =====================================================================

comp_camera_get_projection_matrix :: proc(comp: ^CameraComponent, aspect_ratio : f32) -> matrix[4,4]f32 {
	//return linalg.matrix4_perspective_f32(linalg.to_radians(comp.fov_deg), aspect_ratio, comp.near_clip, comp.far_clip, flip_z_axis = true);
	return linalg.matrix4_perspective_f32(linalg.to_radians(comp.fov_deg), aspect_ratio, comp.near_clip, comp.far_clip, flip_z_axis = true);
}
// not in use atm
comp_camera_get_frustum_planes :: proc(comp: ^CameraComponent, aspect_ratio : f32, transform : Transform) -> FrustumPlanes {

	// from: https://learnopengl.com/Guest-Articles/2021/Scene/Frustum-Culling

	forward, right, up := get_forward_right_up(transform);
	
	// we can also think of this as the (relative to camera pos) center position of the far plane rectangle 
	forward_mul_far := forward * comp.far_clip; 
	
	fovy :f32 = linalg.to_radians(comp.fov_deg);

	// these are the vertical and horzontal half lenghts of the far plane rectangle.
	half_v_side : f32 = comp.far_clip * linalg.tan(fovy * 0.5);
	half_h_side : f32 = half_v_side * aspect_ratio;

	frust : FrustumPlanes = ---;
	// near
	frust.planes[0] = {normal = forward , position = transform.position + forward * comp.near_clip}
	// far
	frust.planes[1]  = {normal = -forward, position = transform.position + forward_mul_far}

	// effectivly we are first computing the a vector from the camera origin to one of the corners of the far rectangle plane
	// and then get the normal by doing a cross product between the vector and right or up of the camera.
	// note that we could probably just calculate the distance to closest point on plane position instead of storing full position per plane

	// left
	frust.planes[2]  = {normal = linalg.cross(up, forward_mul_far + right * half_h_side), position = transform.position }
	// right
	frust.planes[3] = {normal = linalg.cross(forward_mul_far - right * half_h_side, up), position = transform.position }
	// top
	frust.planes[4]   = {normal = linalg.cross(right, forward_mul_far - up* half_v_side) , position = transform.position }
	// bot
	frust.planes[5]   = {normal = linalg.cross(forward_mul_far + up * half_v_side, right), position = transform.position }
	
	return frust;
}


comp_camera_get_culling_frustum :: proc(comp: ^CameraComponent, aspect_ratio : f32) -> CullingFrustum {

	return create_culling_frustum(aspect_ratio, linalg.to_radians(comp.fov_deg), comp.near_clip, comp.far_clip);
}

comp_camera_calc_EV100 :: proc "contextless" (aperture, shutter_speed, iso : f32) -> f32 {
	// Source : https://media.contentapi.ea.com/content/dam/eacom/frostbite/files/course-notes-moving-frostbite-to-pbr-v32.pdf
	// EV number is defined as:
	// 2^ EV_s = N^2 / t and EV_s = EV_100 + log2 (S /100)
	// This gives
	// EV_s = log2 (N^2 / t)
	// EV_100 + log2 (S /100) = log2 (N^2 / t)
	// EV_100 = log2 (N^2 / t) - log2 (S /10

	return linalg.log2(linalg.sqrt(aperture) / shutter_speed * 100.0 / iso);
}


comp_camera_get_EV100 :: proc(comp: ^CameraComponent) -> f32 {
	return comp_camera_calc_EV100(comp.aperture, comp.shutter_speed, comp.iso);
}


comp_camera_get_exposure :: proc(comp: ^CameraComponent) -> f32 {
	
	comp_camera_convert_EV100_to_exposure :: proc(EV100 : f32) -> f32 {
		// Source : https://media.contentapi.ea.com/content/dam/eacom/frostbite/files/course-notes-moving-frostbite-to-pbr-v32.pdf
		// Compute the maximum luminance possible with H_sbs sensitivity
		// maxLum = 78 / ( S * q ) * N^2 / t
		// = 78 / ( S * q ) * 2^ EV_100
		// = 78 / (100 * 0.65) * 2^ EV_100
		// = 1.2 * 2^ EV
		// Reference : http :// en. wikipedia . org / wiki / Film_speed
		max_luminance : f32 = 1.2 * linalg.pow(f32(2.0), EV100);
		return 1.0 / max_luminance;

	}

	ev100 : f32 = comp_camera_get_EV100(comp);

	exposure : f32 = comp_camera_convert_EV100_to_exposure(ev100) * linalg.pow(f32(2.0), comp.exposure_correction);

	return exposure;
}