package iri


/*

## Asteriods game


## engine


- implment that all assets can optionally store an asset alias string which can than be used to load and lookup assets through the asset_manager
	-> related to this we can think about caching the asset registry entries also to a file so that loading times are much faster
	   we will have to manage and keep this file up to date with filepaths that may change aswell as what happens when we delete / move files outside the editor/engien api.
	   
- frustum culling using bvh tree.

### Graphics
- test if using linearized depth is better for GTOA and Radiance Cascades.
- try min and max GTAO in half res with min/max aware upsampling.


### Bugs
- bugfix: entity name not cleaned up somewhere when runtime destroying entities..
- bugfix: materials are not always loaded or stored correctly. not sure where this happens.
	 but i think material files themselves are fine but maybe something gets messed up when loading or storing in the universe file?


### High level todo
 - make a child of component
 - sound system
 - ui rendering system
 - presets system
 - cluster tiled light culling
 - custom materials/shaders


## Editor
 - more editor tooltips
 - material editor

*/