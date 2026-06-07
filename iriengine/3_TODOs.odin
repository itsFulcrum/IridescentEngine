package iri


/*

## Asteriods game


## engine


- frustum culling using bvh tree.

- removing entities should not happen imidiatly but at least one BOTH a frame and physics update later.

- test if using linearized depth is better for GTOA and Radiance Cascades.
- try min and max GTAO in half res with min/max aware upsampling.


- bugfix: entity name not cleaned up somewhere when runtime destroying entities..
- bugfix: materials are not always loaded or stored correctly. not sure where this happens.
	 but i think material files themselves are fine but maybe something gets messed up when loading or storing in the universe file?

### High level todo
 - make a child of component
 - sound system
 - better action/slot based input system.
 - ui rendering system
 - presets system
 - cluster tiled light culling
 - custom materials/shaders


## Editor
 - more editor tooltips	
 - editor color sceme
 - material editor

*/