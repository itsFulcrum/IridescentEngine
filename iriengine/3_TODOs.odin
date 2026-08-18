package iri


/*

## Asteriods game


## Engine
 
 ### UI rendering system
  - World Space UI.
 -  Bug. when _Not_ rendering at native resolution the Mouse Pos for hovering is wrong.
	## Fonts
	- test google material icons font.
	- SDF fonts instead.


## Editor
 - Editor Overhaul function names such that all function that require the editor to be initialized have some prefix
 - Make Mesh importer take a CreateInfo structure instead.

	   

### Graphics
- BUG. validation error when not having any lights/Shadowmaps in the scene..
- reversed Z buffer
- test if using linearized depth is better for GTOA and Radiance Cascades.
- try min and max GTAO in half res with min/max aware upsampling.
- frustum culling using bvh tree.
- raytraced shadows. -> maybe simplify light system by only allowing one Directional Main light.

### Bugs
- bugfix: entity name not cleaned up somewhere when runtime destroying entities..
- bugfix: materials are not always loaded or stored correctly. not sure where this happens.
	 but i think material files themselves are fine but maybe something gets messed up when loading or storing in the universe file?

### Asset Management
	- dont unload asset directly if their refrence count goes to 0 because we might be switching universe
		and would like to keep assets loaded that are used again. Also makes sync easier probably.


### High level todo
 - make a child of component
 - sound system
 - ui rendering system
 - presets system
 - cluster tiled light culling
 - custom materials/shaders
 - incorporate box3D 


## Editor
 - more editor tooltips
 - material editor

*/