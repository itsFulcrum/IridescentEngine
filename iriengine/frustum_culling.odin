package iri

import "core:log"

import "core:math"
import "core:math/linalg"

import "core:simd"
import "base:intrinsics"
import "odinary:mathy/simdy"


Plane :: struct {
	normal : [3]f32,
	position : [3]f32, // we can prob just store distance to closest point on plane
}

FrustumPlanes :: struct {
	planes : [6]Plane, // conventions is in this order: near, far, left, right, top, bottom
}



OBB :: struct {
	center  : [4]f32,
	extents : [4]f32,
	axis : [3][4]f32, // Orthonormal axis as normalized vectors.
}

CullingFrustum :: struct {
	near_plane_z : f32,
	far_plane_z  : f32,
	near_plane_half_width  : f32,
	near_plane_half_height : f32,
}

// transform a aabb in object space to an obb in world space given a to_world Transform
aabb_to_transformed_obb :: proc "contextless" (aabb : AABB, to_world : Transform) -> OBB {

    corner_0 : [3]f32 = to_world.position + linalg.quaternion128_mul_vector3(to_world.orientation, to_world.scale * [3]f32{aabb.min.x, aabb.min.y, aabb.min.z});
    corner_1 : [3]f32 = to_world.position + linalg.quaternion128_mul_vector3(to_world.orientation, to_world.scale * [3]f32{aabb.max.x, aabb.min.y, aabb.min.z});
    corner_2 : [3]f32 = to_world.position + linalg.quaternion128_mul_vector3(to_world.orientation, to_world.scale * [3]f32{aabb.min.x, aabb.max.y, aabb.min.z});
    corner_3 : [3]f32 = to_world.position + linalg.quaternion128_mul_vector3(to_world.orientation, to_world.scale * [3]f32{aabb.min.x, aabb.min.y, aabb.max.z});

    obb : OBB;

    obb.axis[0].xyz = corner_1 - corner_0;
    obb.axis[1].xyz = corner_2 - corner_0;
    obb.axis[2].xyz = corner_3 - corner_0;

    obb.center.xyz = corner_0 + [3]f32{0.5,0.5,0.5} * (obb.axis[0].xyz + obb.axis[1].xyz + obb.axis[2].xyz);
    obb.center.w = 1.0;

    obb.extents = [4]f32{linalg.length(obb.axis[0].xyz), linalg.length(obb.axis[1].xyz), linalg.length(obb.axis[2].xyz), 0.0};
    
    // normalize axis
    obb.axis[0] /= obb.extents.x
    obb.axis[1] /= obb.extents.y
    obb.axis[2] /= obb.extents.z
    // make .w = 0 since they are direction, so we can transform them with any other matrix
    obb.axis[0].w = 0.0;
    obb.axis[1].w = 0.0;
    obb.axis[2].w = 0.0;

    // extent should be half the lenght of each side
    obb.extents.xyz *= 0.5;

    return obb;
}

create_culling_frustum :: proc "contextless" (aspect_ratio : f32 , fov_radians: f32, near_clip_plane : f32 , far_clip_plane : f32 ) -> CullingFrustum {

    tan_fovy_near : f32 = linalg.tan(fov_radians * 0.5) * near_clip_plane;

    return CullingFrustum{
        // @Note - fulcrum
        // we do minus here because our forward axis is negative Z so 
        // store position along z
        near_plane_z = -near_clip_plane,
        far_plane_z  = -far_clip_plane,

        // These are the vertical and horzontal half lenghts of the near plane rectangle.
        near_plane_half_width  = tan_fovy_near * aspect_ratio,
        near_plane_half_height = tan_fovy_near,
    }
}

// @Note: cull objects in shadowmap draw that have samll pixel fill in the shadowmap or if they are outside the frustum.
// the frustum check is very approximate and useses effective a spherical radius but its very fast at least.
test_shadow_draw :: proc (view_proj_mat : matrix[4,4]f32, obb: OBB, resolution : u32) -> bool {


    corner0  : [4]f32 = obb.center - (obb.axis[0] * obb.extents[0]) - (obb.axis[1] * obb.extents[1]) - (obb.axis[2] * obb.extents[2])
    corner1  : [4]f32 = obb.center + (obb.axis[0] * obb.extents[0]) + (obb.axis[1] * obb.extents[1]) + (obb.axis[2] * obb.extents[2])

    corner0.w = 1.0;
    corner1.w = 1.0;

    corner0 = view_proj_mat * corner0;
    corner1 = view_proj_mat * corner1;

    corner0.xyz /= corner0.w;
    corner1.xyz /= corner1.w;

    diagonal := (corner1.xyz - corner0.xyz);


    radius : f32 = linalg.length(diagonal);

    PIXEL_THRESHOLD :: 8

    pixels_fill : f32 = radius * f32(resolution);

    if pixels_fill < PIXEL_THRESHOLD {
        return false;
    }

    radius *= 0.5;
    center : [3]f32 = corner0.xyz + (diagonal * 0.5);

    if center.z + radius < 0 {
        
        return false;
    }

    if center.x + radius < -1 || center.x - radius > 1{
        return false;
    }

    if center.y + radius < -1 || center.y - radius > 1 {
        return false;
    }

    return true;
}


frustum_test_obb_inside :: proc(culling_frustum : CullingFrustum, view_mat : matrix[4,4]f32, world_obb : OBB) -> bool{

    // using separating axis theorem
    // https://bruop.github.io/improved_frustum_culling/

    z_near : f32 = culling_frustum.near_plane_z;
    z_far  : f32 = culling_frustum.far_plane_z;
    x_near : f32 = culling_frustum.near_plane_half_width;
    y_near : f32 = culling_frustum.near_plane_half_height;
    zfar_over_znear : f32 = z_far / z_near;

    obb : OBB = world_obb;

    obb.center  = view_mat * obb.center;
    obb.axis[0] = view_mat * obb.axis[0];
    obb.axis[1] = view_mat * obb.axis[1];
    obb.axis[2] = view_mat * obb.axis[2];

    // First Test OBB Against frustums near and far plane
    when true {
        

        // This would be the normal of the near plane in view space
        // N : [3]f32 = { 0, 0, 1 };

        // we project the obb center onto a axis parralel to the normal
        // this is simple we just use its z position value.
        // we then compute the projected extents on the axis.

        // we can then simply test if its below or above the near or far plane on this axis.

        MoC : f32 = obb.center.z;

        radius: f32 = abs(obb.axis[0].z) * obb.extents.x;
        radius     += abs(obb.axis[1].z) * obb.extents.y;
        radius     += abs(obb.axis[2].z) * obb.extents.z;

        obb_min : f32 = MoC - radius;
        obb_max : f32 = MoC + radius;

        // including far test
        // if (obb_min > z_near || obb_max < z_far) {
        //     return false;
        // }

        // omitting far plane test
        if (obb_min > z_near) {
            return false;
        }
    }
    
    // Next we test the 4 other planes of the view frustum
    when true {

        // Frustum Normals
        M : [4][3]f32 = {
            [3]f32{ z_near, 0.0 , x_near}, // left plane
            [3]f32{-z_near, 0.0 , x_near}, // right plane
            [3]f32{ 0.0   ,-z_near, y_near}, // top
            [3]f32{ 0.0   , z_near, y_near}, // bot
        }


        #unroll for m in 0..<4 {

            MoX : f32 = abs(M[m].x);
            MoY : f32 = abs(M[m].y);
            MoZ : f32 = M[m].z;

            // project obb center onto frustum normal axis
            MoC : f32 = linalg.dot(M[m], obb.center.xyz);
            
            // calc projected min max of the obb on the projected axis
            obb_radius: f32 = abs(linalg.dot(M[m], obb.axis[0].xyz)) * obb.extents.x;
            obb_radius     += abs(linalg.dot(M[m], obb.axis[1].xyz)) * obb.extents.y;
            obb_radius     += abs(linalg.dot(M[m], obb.axis[2].xyz)) * obb.extents.z;

            obb_min : f32 = MoC - obb_radius;
            obb_max : f32 = MoC + obb_radius;

            // project frustum onto axis aswell
            p : f32 = x_near * MoX + y_near * MoY;

            tau_0 : f32 = z_near * MoZ - p;
            tau_1 : f32 = z_near * MoZ + p;

            if (tau_0 < 0.0) {
                tau_0 *= zfar_over_znear;
            }
            if (tau_1 > 0.0) {
                tau_1 *= zfar_over_znear;
            }

            if (obb_min > tau_1 || obb_max < tau_0) {
                return false;
            }
        }
    }


     // OBB Axes
    when true {
        for  m in 0..<3 {
            
            M := obb.axis[m].xyz;
            
            MoX : f32 = linalg.abs(M.x);
            MoY : f32 = linalg.abs(M.y);
            MoZ : f32 = M.z;
            MoC : f32 = linalg.dot(M, obb.center.xyz);

            obb_radius : f32 = obb.extents[m];
            obb_min : f32 = MoC - obb_radius;
            obb_max : f32 = MoC + obb_radius;

            // Frustum projection
            p     : f32= x_near * MoX + y_near * MoY;
            tau_0 : f32= z_near * MoZ - p;
            tau_1 : f32= z_near * MoZ + p;

            if tau_0 < 0.0 {
                tau_0 *= zfar_over_znear;
            }
            
            if tau_1 > 0.0 {
                tau_1 *= zfar_over_znear;
            }

            if (obb_min > tau_1 || obb_max < tau_0) {

                //log.debugf("culled by obb axis")
                return false;
            }
        }
    }

    // The rest off the tests are turned off right now as their culling contribution is very low but still cost performance 


    // perform each of the cross products between the edges
    // First R x A_i
    when false {
        for m in 0..<3 {
            M : [3]f32 = { 0.0, -obb.axis[m].z, obb.axis[m].y };
            MoX : f32 = 0.0;
            MoY : f32 = linalg.abs(M.y);
            MoZ : f32 = M.z;
            MoC : f32 = M.y * obb.center.y + M.z * obb.center.z;

            obb_radius : f32 = 0.0;
            for i in 0..<3 {
                obb_radius += linalg.abs(linalg.dot(M, obb.axis[i])) * obb.extents[i];
            }

            obb_min : f32 = MoC - obb_radius;
            obb_max : f32 = MoC + obb_radius;

            // Frustum projection
            p     : f32= x_near * MoX + y_near * MoY;
            tau_0 : f32= z_near * MoZ - p;
            tau_1 : f32= z_near * MoZ + p;
            
            if (tau_0 < 0.0) {
                tau_0 *= z_far / z_near;
            }
            if (tau_1 > 0.0) {
                tau_1 *= z_far / z_near;
            }

        

            if (obb_min > tau_1 || obb_max < tau_0) {
                return false;
            }
        }
    }

     // U x A_i
    when false {
        for m in 0..<3 {
            M : [3]f32 = {obb.axis[m].z, 0.0, -obb.axis[m].x };
            MoX : f32 = abs(M.x);
            MoY : f32 = 0.0;
            MoZ : f32 = M.z;
            MoC : f32 = M.x * obb.center.x + M.z * obb.center.z;

            obb_radius : f32 = 0.0;
            for i in 0..<3 {
                obb_radius += abs(linalg.dot(M, obb.axis[i])) * obb.extents[i];
            }

            obb_min := MoC - obb_radius;
            obb_max := MoC + obb_radius;

            // Frustum projection
            p     := x_near * MoX + y_near * MoY;
            tau_0 := z_near * MoZ - p;
            tau_1 := z_near * MoZ + p;
            if (tau_0 < 0.0) {
                tau_0 *= z_far / z_near;
            }
            if (tau_1 > 0.0) {
                tau_1 *= z_far / z_near;
            }

        

            if (obb_min > tau_1 || obb_max < tau_0) {
                return false;
            }
        }
    }

    // Frustum Edges X Ai
    when false{
        for obb_edge_idx  in 0..<3 {
            
            M : [4][3]f32 = {
                linalg.cross([3]f32{-x_near,  0.0   , z_near }, obb.axis[obb_edge_idx]),// Left Plane
                linalg.cross([3]f32{ x_near,  0.0   , z_near }, obb.axis[obb_edge_idx]),// Right plane
                linalg.cross([3]f32{ 0.0   ,  y_near, z_near }, obb.axis[obb_edge_idx]),// Top plane
                linalg.cross([3]f32{ 0.0   , -y_near, z_near }, obb.axis[obb_edge_idx]),// Bottom plane
            }

            for m in 0..<4 {
                MoX : f32 = abs(M[m].x);
                MoY : f32 = abs(M[m].y);
                MoZ : f32 = M[m].z;

                
                epsilon : f32 = 1e-4;

                // if(MoX < math.F32_EPSILON && MoY < math.F32_EPSILON && abs(MoZ) < math.F32_EPSILON){
                //  continue;
                // }

                if(MoX < epsilon && MoY < epsilon && abs(MoZ) < epsilon){
                    continue;
                }

                MoC : f32 = linalg.dot(M[m], obb.center);

                obb_radius : f32= 0.0;
                for i in 0..<3 {
                    obb_radius += abs(linalg.dot(M[m], obb.axis[i])) * obb.extents[i];
                }

                obb_min : f32= MoC - obb_radius;
                obb_max : f32= MoC + obb_radius;

                // Frustum projection
                p     := x_near * MoX + y_near * MoY;
                tau_0 := z_near * MoZ - p;
                tau_1 := z_near * MoZ + p;
                if (tau_0 < 0.0) {
                    tau_0 *= z_far / z_near;
                }
                if (tau_1 > 0.0) {
                    tau_1 *= z_far / z_near;
                }
        

                if (obb_min > tau_1 || obb_max < tau_0) {
                    return false;
                }
            }
        }
    }

    return true;
}

// 'aabb' should be in local/object space, 'to_world' Transform should bring aabb to world space
frustum_test_aabb_inside :: proc(culling_frustum : CullingFrustum, view_mat : matrix[4,4]f32, aabb : AABB, to_world : Transform) -> bool{

    // using separating axis theorem
    // https://bruop.github.io/improved_frustum_culling/

    z_near : f32 = culling_frustum.near_plane_z;
    z_far  : f32 = culling_frustum.far_plane_z;
    x_near : f32 = culling_frustum.near_plane_half_width;
    y_near : f32 = culling_frustum.near_plane_half_height;
    zfar_over_znear : f32 = z_far / z_near;

    obb : OBB = aabb_to_transformed_obb(aabb, to_world);

    // 4 corners of the aabb transform to world space using to_world Transform
    // @note - we could also combine the to_world Transform with the view_matrix but that would require to create a transform matrix for each 
    // mesh instance we want to test which will be a lot more math ops in total even if we would save some work in this procedure.

   //  corners : [4][4]f32 = ---;
   //  corners[0].xyz  = to_world.position + linalg.quaternion128_mul_vector3(to_world.orientation, to_world.scale * [3]f32{aabb.min.x, aabb.min.y, aabb.min.z})
   //  corners[1].xyz  = to_world.position + linalg.quaternion128_mul_vector3(to_world.orientation, to_world.scale * [3]f32{aabb.max.x, aabb.min.y, aabb.min.z})
   //  corners[2].xyz  = to_world.position + linalg.quaternion128_mul_vector3(to_world.orientation, to_world.scale * [3]f32{aabb.min.x, aabb.max.y, aabb.min.z})
   //  corners[3].xyz  = to_world.position + linalg.quaternion128_mul_vector3(to_world.orientation, to_world.scale * [3]f32{aabb.min.x, aabb.min.y, aabb.max.z})
   //  // corners[0].w  = 1.0;
   //  // corners[1].w  = 1.0;
   //  // corners[2].w  = 1.0;
   //  // corners[3].w  = 1.0;
    
   //  obb_axis : [3][4]f32 = ---;
   //  obb_axis[0] = corners[1] - corners[0];
   //  obb_axis[1] = corners[2] - corners[0];
   //  obb_axis[2] = corners[3] - corners[0];

   //  obb_center : [4]f32 = corners[0] + [4]f32{0.5,0.5,0.5,1.0} * (obb_axis[0] + obb_axis[1] + obb_axis[2]);
   //  obb_center.w = 1.0;


   //  obb_extents := [4]f32{linalg.length(obb_axis[0].xyz), linalg.length(obb_axis[1].xyz), linalg.length(obb_axis[2].xyz), 1.0};
    
   //  // normalize axis
   //  obb_axis[0] /= obb_extents.x
   //  obb_axis[1] /= obb_extents.y
   //  obb_axis[2] /= obb_extents.z

   //  // extent should be half the lenght of each side
   //  obb_extents *= 0.5;
   // // obb_extents.w = 1.0;

   //  obb_axis[0].w = 0.0;
   //  obb_axis[1].w = 0.0;
   //  obb_axis[2].w = 0.0;

    obb.center  = view_mat * obb.center;
    obb.axis[0] = view_mat * obb.axis[0];
    obb.axis[1] = view_mat * obb.axis[1];
    obb.axis[2] = view_mat * obb.axis[2];
   // obb_extents = view_mat * obb_extents;

    // Transform corners to view space using view matrix
    // corners[0] = view_mat * corners[0];
    // corners[1] = view_mat * corners[1];
    // corners[2] = view_mat * corners[2];
    // corners[3] = view_mat * corners[3];

    // create obb ortonormal axis from corners
    // obb_axis : [3][4]f32 = ---;
    // obb_axis[0] = corners[1] - corners[0];
    // obb_axis[1] = corners[2] - corners[0];
    // obb_axis[2] = corners[3] - corners[0];
    



    // First Test OBB Against frustums near and far plane
    when true {
        

        // This would be the normal of the near plane in view space
        // N : [3]f32 = { 0, 0, 1 };

        // we project the obb center onto a axis parralel to the normal
        // this is simple we just use its z position value.
        // we then compute the projected extents on the axis.

        // we can then simply test if its below or above the near or far plane on this axis.

        MoC : f32 = obb.center.z;

        radius: f32 = abs(obb.axis[0].z) * obb.extents.x;
        radius     += abs(obb.axis[1].z) * obb.extents.y;
        radius     += abs(obb.axis[2].z) * obb.extents.z;

        obb_min : f32 = MoC - radius;
        obb_max : f32 = MoC + radius;

        // including far test
        // if (obb_min > z_near || obb_max < z_far) {
        //     return false;
        // }

        // omitting far plane test
        if (obb_min > z_near) {
            return false;
        }
    }
    
    // Next we test the 4 other planes of the view frustum
    when true {

        // Frustum Normals
        M : [4][3]f32 = {
            [3]f32{ z_near, 0.0 , x_near}, // left plane
            [3]f32{-z_near, 0.0 , x_near}, // right plane
            [3]f32{ 0.0   ,-z_near, y_near}, // top
            [3]f32{ 0.0   , z_near, y_near}, // bot
        }


        #unroll for m in 0..<4 {

            MoX : f32 = abs(M[m].x);
            MoY : f32 = abs(M[m].y);
            MoZ : f32 = M[m].z;

            // project obb center onto frustum normal axis
            MoC : f32 = linalg.dot(M[m], obb.center.xyz);
            
            // calc projected min max of the obb on the projected axis
            obb_radius: f32 = abs(linalg.dot(M[m], obb.axis[0].xyz)) * obb.extents.x;
            obb_radius     += abs(linalg.dot(M[m], obb.axis[1].xyz)) * obb.extents.y;
            obb_radius     += abs(linalg.dot(M[m], obb.axis[2].xyz)) * obb.extents.z;

            obb_min : f32 = MoC - obb_radius;
            obb_max : f32 = MoC + obb_radius;

            // project frustum onto axis aswell
            p : f32 = x_near * MoX + y_near * MoY;

            tau_0 : f32 = z_near * MoZ - p;
            tau_1 : f32 = z_near * MoZ + p;

            if (tau_0 < 0.0) {
                tau_0 *= zfar_over_znear;
            }
            if (tau_1 > 0.0) {
                tau_1 *= zfar_over_znear;
            }

            if (obb_min > tau_1 || obb_max < tau_0) {
                return false;
            }
        }
    }


     // OBB Axes
    when true {
        for  m in 0..<3 {
            
            M := obb.axis[m].xyz;
            
            MoX : f32 = linalg.abs(M.x);
            MoY : f32 = linalg.abs(M.y);
            MoZ : f32 = M.z;
            MoC : f32 = linalg.dot(M, obb.center.xyz);

            obb_radius : f32 = obb.extents[m];
            obb_min : f32 = MoC - obb_radius;
            obb_max : f32 = MoC + obb_radius;

            // Frustum projection
            p     : f32= x_near * MoX + y_near * MoY;
            tau_0 : f32= z_near * MoZ - p;
            tau_1 : f32= z_near * MoZ + p;

            if tau_0 < 0.0 {
                tau_0 *= zfar_over_znear;
            }
            
            if tau_1 > 0.0 {
                tau_1 *= zfar_over_znear;
            }

            if (obb_min > tau_1 || obb_max < tau_0) {

                //log.debugf("culled by obb axis")
                return false;
            }
        }
    }

    // The rest off the tests are turned off right now as their culling contribution is very low but still cost performance 


    // perform each of the cross products between the edges
    // First R x A_i
    when false {
        for m in 0..<3 {
            M : [3]f32 = { 0.0, -obb.axis[m].z, obb.axis[m].y };
            MoX : f32 = 0.0;
            MoY : f32 = linalg.abs(M.y);
            MoZ : f32 = M.z;
            MoC : f32 = M.y * obb.center.y + M.z * obb.center.z;

            obb_radius : f32 = 0.0;
            for i in 0..<3 {
                obb_radius += linalg.abs(linalg.dot(M, obb.axis[i])) * obb.extents[i];
            }

            obb_min : f32 = MoC - obb_radius;
            obb_max : f32 = MoC + obb_radius;

            // Frustum projection
            p     : f32= x_near * MoX + y_near * MoY;
            tau_0 : f32= z_near * MoZ - p;
            tau_1 : f32= z_near * MoZ + p;
            
            if (tau_0 < 0.0) {
                tau_0 *= z_far / z_near;
            }
            if (tau_1 > 0.0) {
                tau_1 *= z_far / z_near;
            }

        

            if (obb_min > tau_1 || obb_max < tau_0) {
                return false;
            }
        }
    }

     // U x A_i
    when false {
        for m in 0..<3 {
            M : [3]f32 = {obb.axis[m].z, 0.0, -obb.axis[m].x };
            MoX : f32 = abs(M.x);
            MoY : f32 = 0.0;
            MoZ : f32 = M.z;
            MoC : f32 = M.x * obb.center.x + M.z * obb.center.z;

            obb_radius : f32 = 0.0;
            for i in 0..<3 {
                obb_radius += abs(linalg.dot(M, obb.axis[i])) * obb.extents[i];
            }

            obb_min := MoC - obb_radius;
            obb_max := MoC + obb_radius;

            // Frustum projection
            p     := x_near * MoX + y_near * MoY;
            tau_0 := z_near * MoZ - p;
            tau_1 := z_near * MoZ + p;
            if (tau_0 < 0.0) {
                tau_0 *= z_far / z_near;
            }
            if (tau_1 > 0.0) {
                tau_1 *= z_far / z_near;
            }

        

            if (obb_min > tau_1 || obb_max < tau_0) {
                return false;
            }
        }
    }

    // Frustum Edges X Ai
    when false{
        for obb_edge_idx  in 0..<3 {
            
            M : [4][3]f32 = {
                linalg.cross([3]f32{-x_near,  0.0   , z_near }, obb.axis[obb_edge_idx]),// Left Plane
                linalg.cross([3]f32{ x_near,  0.0   , z_near }, obb.axis[obb_edge_idx]),// Right plane
                linalg.cross([3]f32{ 0.0   ,  y_near, z_near }, obb.axis[obb_edge_idx]),// Top plane
                linalg.cross([3]f32{ 0.0   , -y_near, z_near }, obb.axis[obb_edge_idx]),// Bottom plane
            }

            for m in 0..<4 {
                MoX : f32 = abs(M[m].x);
                MoY : f32 = abs(M[m].y);
                MoZ : f32 = M[m].z;

                
                epsilon : f32 = 1e-4;

                // if(MoX < math.F32_EPSILON && MoY < math.F32_EPSILON && abs(MoZ) < math.F32_EPSILON){
                //  continue;
                // }

                if(MoX < epsilon && MoY < epsilon && abs(MoZ) < epsilon){
                    continue;
                }

                MoC : f32 = linalg.dot(M[m], obb.center);

                obb_radius : f32= 0.0;
                for i in 0..<3 {
                    obb_radius += abs(linalg.dot(M[m], obb.axis[i])) * obb.extents[i];
                }

                obb_min : f32= MoC - obb_radius;
                obb_max : f32= MoC + obb_radius;

                // Frustum projection
                p     := x_near * MoX + y_near * MoY;
                tau_0 := z_near * MoZ - p;
                tau_1 := z_near * MoZ + p;
                if (tau_0 < 0.0) {
                    tau_0 *= z_far / z_near;
                }
                if (tau_1 > 0.0) {
                    tau_1 *= z_far / z_near;
                }
        

                if (obb_min > tau_1 || obb_max < tau_0) {
                    return false;
                }
            }
        }
    }

    return true;
}




frustum_test_obb_inside_simd :: proc(culling_frustum : CullingFrustum, aabb : AABB, model_view_mat : matrix[4,4]f32) -> bool{

	// using separating axis theorem
	// https://bruop.github.io/improved_frustum_culling/

	z_near : f32 = culling_frustum.near_plane_z;
	z_far  : f32 = culling_frustum.far_plane_z;
	x_near : f32 = culling_frustum.near_plane_half_width;
	y_near : f32 = culling_frustum.near_plane_half_height;
	zfar_over_znear : f32 = z_far / z_near;

	// 4 adjecent corners of the aabb
	corners : [4][4]f32;
	corners[0] = model_view_mat * [4]f32{aabb.min.x, aabb.min.y, aabb.min.z, 1.0};
	corners[1] = model_view_mat * [4]f32{aabb.max.x, aabb.min.y, aabb.min.z, 1.0};
	corners[2] = model_view_mat * [4]f32{aabb.min.x, aabb.max.y, aabb.min.z, 1.0};
	corners[3] = model_view_mat * [4]f32{aabb.min.x, aabb.min.y, aabb.max.z, 1.0};


	_corners_0 : #simd[4]f32 = intrinsics.unaligned_load(cast(^#simd[4]f32)&corners[0]);
	_corners_1 : #simd[4]f32 = intrinsics.unaligned_load(cast(^#simd[4]f32)&corners[1]);
	_corners_2 : #simd[4]f32 = intrinsics.unaligned_load(cast(^#simd[4]f32)&corners[2]);
	_corners_3 : #simd[4]f32 = intrinsics.unaligned_load(cast(^#simd[4]f32)&corners[3]);

	// _corners_0 : #simd[4]f32 = simd.from_array(corners[0]);
	// _corners_1 : #simd[4]f32 = simd.from_array(corners[1]);
	// _corners_2 : #simd[4]f32 = simd.from_array(corners[2]);
	// _corners_3 : #simd[4]f32 = simd.from_array(corners[3]);


	_obb_axis_0 := simd.sub(_corners_1, _corners_0); // right 
	_obb_axis_1 := simd.sub(_corners_2, _corners_0); // up
	_obb_axis_2 := simd.sub(_corners_3, _corners_0); // forward


	// center = _corner_0 + 0.5 * (axis_0 + axis_1 + axis_2 )
	_tmp_0 : #simd[4]f32 = simd.add(simd.add(_obb_axis_0,_obb_axis_1), _obb_axis_2);
	_obb_center : #simd[4]f32 = simd.fused_mul_add(_tmp_0,#simd[4]f32{0.5,0.5,0.5,1.0},_corners_0);

	// we can do dot product with itself and then just take sqrt to get the length
	// obb.extents.x = linalg.length(obb.axis[0]); 
	
	obb_extents :[4]f32;
	obb_extents.x = math.sqrt_f32(simdy.dot_f32x4(_obb_axis_0, _obb_axis_0));
	obb_extents.y = math.sqrt_f32(simdy.dot_f32x4(_obb_axis_1, _obb_axis_1));
	obb_extents.z = math.sqrt_f32(simdy.dot_f32x4(_obb_axis_2, _obb_axis_2));

	_obb_axis_0 = simd.div(_obb_axis_0, #simd[4]f32{obb_extents.x,obb_extents.x,obb_extents.x, 1.0}); // right 
	_obb_axis_1 = simd.div(_obb_axis_1, #simd[4]f32{obb_extents.y,obb_extents.y,obb_extents.y, 1.0}); // up
	_obb_axis_2 = simd.div(_obb_axis_2, #simd[4]f32{obb_extents.z,obb_extents.z,obb_extents.z, 1.0}); // front


	obb_extents *= 0.5;

	//_obb_extents := simd.from_array(obb_extents)
	_obb_extents := intrinsics.unaligned_load(cast(^#simd[4]f32)&obb_extents);

	// First Test OBB Against frustums near and far plane
	when true {
	 	

	 	// This would be the normal of the near plane in view space
        // N : [3]f32 = { 0, 0, 1 };

        // we project the obb center onto a axis parralel to the normal
        // this is simple we just use its z position value.
        // we then compute the projected extents on the axis.

        // we can then simply test if its below or above the near or far plane on this axis.


        z_r : f32 =  simd.extract(_obb_axis_0, 2); // right
        z_u : f32 =  simd.extract(_obb_axis_1, 2); // up
        z_f : f32 =  simd.extract(_obb_axis_2, 2); // front

        projected :#simd[4]f32 = simd.abs(#simd[4]f32{z_r, z_u, z_f, 0.0});
        projected = simd.mul(projected, _obb_extents);

        // radius : f32 = abs(obb.axis[0].z) * obb.extents[0];
        // radius += abs(obb.axis[1].z) * obb.extents[1];
        // radius += abs(obb.axis[2].z) * obb.extents[2];

        radius := simd.reduce_add_ordered(projected);
        MoC : f32 = simd.extract(_obb_center, 2); // center.z

        obb_min : f32 = MoC - radius;
        obb_max : f32 = MoC + radius;

        if (obb_min > z_near || obb_max < z_far) {
            return false;
        }
    }
    
    // Next we test the 4 other planes of the view frustum
	when true {

		// Frustum Normals
		M : [4]#simd[4]f32 = {
			#simd[4]f32{ z_near, 0.0 , x_near, 0.0}, // left plane
			#simd[4]f32{-z_near, 0.0 , x_near, 0.0}, // right plane
			#simd[4]f32{ 0.0   ,-z_near, y_near, 0.0}, // top
			#simd[4]f32{ 0.0   , z_near, y_near, 0.0}, // bot
		}

		for m in 0..<4 {

            MoX : f32 = abs( simd.extract(M[m], 0));
            MoY : f32 = abs(simd.extract(M[m], 1));
            MoZ : f32 = simd.extract(M[m], 2);

            MoC : f32 = simdy.dot_last_is_0_f32x4(M[m],_obb_center);

            d0 := simdy.dot_last_is_0_f32x4(M[m], _obb_axis_0);
            d1 := simdy.dot_last_is_0_f32x4(M[m], _obb_axis_1);
            d2 := simdy.dot_last_is_0_f32x4(M[m], _obb_axis_2);

            _obb_radius := simd.mul(simd.abs(#simd[4]f32{d0 , d1 , d2, 0.0}), _obb_extents);
            obb_radius :f32 = simd.reduce_add_ordered(_obb_radius);

            obb_min : f32 = MoC - obb_radius;
            obb_max : f32 = MoC + obb_radius;

            p : f32 = x_near * MoX + y_near * MoY;

            tau_0 : f32 = z_near * MoZ - p;
            tau_1 : f32 = z_near * MoZ + p;

            if (tau_0 < 0.0) {
                tau_0 *= zfar_over_znear;
            }
            if (tau_1 > 0.0) {
                tau_1 *= zfar_over_znear;
            }

            if (obb_min > tau_1 || obb_max < tau_0) {
                return false;
            }
        }
	}


	 // OBB Axes
    when false {
        for  m in 0..<3 {
            
            M := obb.axis[m];
            
            MoX : f32 = linalg.abs(M.x);
            MoY : f32 = linalg.abs(M.y);
            MoZ : f32 = M.z;
            MoC : f32 = linalg.dot(M, obb.center);

            obb_radius : f32 = obb.extents[m];
            obb_min : f32 = MoC - obb_radius;
            obb_max : f32 = MoC + obb_radius;

            // Frustum projection
            p     : f32= x_near * MoX + y_near * MoY;
            tau_0 : f32= z_near * MoZ - p;
            tau_1 : f32= z_near * MoZ + p;

            if tau_0 < 0.0 {
                tau_0 *= z_far / z_near;
            }
            
            if tau_1 > 0.0 {
                tau_1 *= z_far / z_near;
            }

		

            if (obb_min > tau_1 || obb_max < tau_0) {

            	//log.debugf("culled by obb axis")
                return false;
            }
        }
    }


    // perform each of the cross products between the edges
    // First R x A_i
    when false {
        for m in 0..<3 {
            M : [3]f32 = { 0.0, -obb.axis[m].z, obb.axis[m].y };
            MoX : f32 = 0.0;
            MoY : f32 = linalg.abs(M.y);
            MoZ : f32 = M.z;
            MoC : f32 = M.y * obb.center.y + M.z * obb.center.z;

            obb_radius : f32 = 0.0;
            for i in 0..<3 {
                obb_radius += linalg.abs(linalg.dot(M, obb.axis[i])) * obb.extents[i];
            }

            obb_min : f32 = MoC - obb_radius;
            obb_max : f32 = MoC + obb_radius;

            // Frustum projection
            p     : f32= x_near * MoX + y_near * MoY;
            tau_0 : f32= z_near * MoZ - p;
            tau_1 : f32= z_near * MoZ + p;
            
            if (tau_0 < 0.0) {
                tau_0 *= z_far / z_near;
            }
            if (tau_1 > 0.0) {
                tau_1 *= z_far / z_near;
            }

		

            if (obb_min > tau_1 || obb_max < tau_0) {
                return false;
            }
        }
    }

     // U x A_i
    when false {
        for m in 0..<3 {
            M : [3]f32 = {obb.axis[m].z, 0.0, -obb.axis[m].x };
            MoX : f32 = abs(M.x);
            MoY : f32 = 0.0;
            MoZ : f32 = M.z;
            MoC : f32 = M.x * obb.center.x + M.z * obb.center.z;

            obb_radius : f32 = 0.0;
            for i in 0..<3 {
                obb_radius += abs(linalg.dot(M, obb.axis[i])) * obb.extents[i];
            }

            obb_min := MoC - obb_radius;
            obb_max := MoC + obb_radius;

            // Frustum projection
            p     := x_near * MoX + y_near * MoY;
            tau_0 := z_near * MoZ - p;
            tau_1 := z_near * MoZ + p;
            if (tau_0 < 0.0) {
                tau_0 *= z_far / z_near;
            }
            if (tau_1 > 0.0) {
                tau_1 *= z_far / z_near;
            }

		

            if (obb_min > tau_1 || obb_max < tau_0) {
                return false;
            }
        }
    }

    // Frustum Edges X Ai
    when false{
        for obb_edge_idx  in 0..<3 {
        	
        	M : [4][3]f32 = {
				linalg.cross([3]f32{-x_near,  0.0   , z_near }, obb.axis[obb_edge_idx]),// Left Plane
				linalg.cross([3]f32{ x_near,  0.0   , z_near }, obb.axis[obb_edge_idx]),// Right plane
				linalg.cross([3]f32{ 0.0   ,  y_near, z_near }, obb.axis[obb_edge_idx]),// Top plane
				linalg.cross([3]f32{ 0.0   , -y_near, z_near }, obb.axis[obb_edge_idx]),// Bottom plane
			}

            for m in 0..<4 {
                MoX : f32 = abs(M[m].x);
                MoY : f32 = abs(M[m].y);
                MoZ : f32 = M[m].z;

                
                epsilon : f32 = 1e-4;

                // if(MoX < math.F32_EPSILON && MoY < math.F32_EPSILON && abs(MoZ) < math.F32_EPSILON){
                // 	continue;
                // }

                if(MoX < epsilon && MoY < epsilon && abs(MoZ) < epsilon){
                	continue;
                }

                MoC : f32 = linalg.dot(M[m], obb.center);

                obb_radius : f32= 0.0;
                for i in 0..<3 {
                    obb_radius += abs(linalg.dot(M[m], obb.axis[i])) * obb.extents[i];
                }

                obb_min : f32= MoC - obb_radius;
                obb_max : f32= MoC + obb_radius;

                // Frustum projection
                p     := x_near * MoX + y_near * MoY;
                tau_0 := z_near * MoZ - p;
                tau_1 := z_near * MoZ + p;
                if (tau_0 < 0.0) {
                    tau_0 *= z_far / z_near;
                }
                if (tau_1 > 0.0) {
                    tau_1 *= z_far / z_near;
                }
		

                if (obb_min > tau_1 || obb_max < tau_0) {
                    return false;
                }
            }
        }
    }

	return true;
}
