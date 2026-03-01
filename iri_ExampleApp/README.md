



Iriengine depends libsODINary which is a collection of Odin packages that I develop alongside this engine.
You can clone the repo here: https://github.com/itsFulcrum/libsODINary.git


To build an app its required to add libsODINary as a collection to the build command '-collection:odinary=<path_to_libs_odinary/libsODINary>'

For this example app we will also add the engine itself as a collection to the build command but you could choose to simply include it as a sub folder of your project.


To run the example app, run the following command inside this folder and modify it to point the 'odinary' collection to the path on your machine. 


"odin run example_app.odin -file -out:IriExampleApp.exe -o:speed -collection:odinary=<REPLACE_THIS_WITH_PATH_TO_LIBS_ODINARY/libsODINary> -collection:iriengine=../../IridescentEngine"


IriEngien requires currently assimp dll and SDL3.dll which are found in this folder.


// nocheckin
"odin run example_app.odin -file -out:IriExampleApp.exe -debug -o:speed -collection:odinary=../../libsODINary -collection:iriengine=../../IridescentEngine"