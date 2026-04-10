package iri


/*

## Asteriods game
 -  asteroids update in physics update
 - bullet updates in physics update


## engine
 - implement disabled entities for all components
	- [x] drawables / meshrenderers
	- [x] lights
	- [ ] skybox
	- [ ] camera
	- [x] collider

 - mesh optimizer
 - sort blend drawables per frame by distance to camera.

 - make ecs entity infos an SOA array

 - fixme active cam/skybox not propperly serialized!

#### Collision Physics system
 - collider component store in universe file
 - collider comp editor
 - renderer should interpolate between prev physics update pos
 	and current pos. 
 - continous collision detection ? maybe not need now
 - incorporate static flag of collider component

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