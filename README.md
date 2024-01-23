# Flutter URDF-Parser
[![pub package](https://img.shields.io/pub/v/urdf_parser.svg)](https://pub.dev/packages/urdf_parser)
[![pub points](https://img.shields.io/pub/points/urdf_parser.svg)](https://pub.dev/packages/urdf_parser)
[![package publisher](https://img.shields.io/pub/publisher/urdf_parser.svg)](https://pub.dev/packages/urdf_parser/publisher)

![example animation](data/animation.gif)

This library is majorly an extended dart port of [https://github.com/gkjohnson/urdf-loaders](https://github.com/gkjohnson/urdf-loaders) for the dart three_js port of [https://github.com/wasabia/three_dart](https://github.com/wasabia/three_dart).

It includes a STL + DAE loader, URDF parser and quaternion + vector3 extension class.

Works with all plattforms that [three_dart](https://github.com/wasabia/three_dart) currently supports. Which are at the time iOS, Android, macOS and Windows.

## Basic Usage
Requires working [three_dart](https://github.com/wasabia/three_dart) project.

Inside of your `initPage()` function load your dae/stl files or urdf model.

```dart
void initPage() async {
    scene = three.Scene();
    // ...

    // --- STL ---
    three.Object3D stlObject = await STLLoader(null).loadAsync("path to stl file");
    scene.add(stlObject);

    // --- DAE ---
    List<three.Object3D> daeObjects = await DAELoader.loadFromPath('path to dae file', []);
    for (three.Object3D object in daeObjects) {
        scene.add(object);
    }

    // --- URDF ---
    // parse the urdf file to a URDFRobot object
    URDFRobot? robot = await URDFLoader.parse(
        "path to urdf file",
        "path to urdf content folder where stl/dae files are located",
    );

    // create a three_dart recursive object and add it to the scene
    scene.add(robot.getObject());
}
```

## Move joints
In the urdf file defined joints can then be moved via `trySetAngle()`.
```dart
robot.trySetAngle("angleName", amount);
```

### Basic example to animate all available joints sequentially
```dart
void render() {
    // ...

    double time = DateTime.now().millisecondsSinceEpoch / 6e4;

    List<MapEntry<String, URDFJoint>> joints = (robot!.joints.entries.where(
        (entry) => entry.value.type != "fixed")).toList();

    // robot joint test animation
    double periodicValueSmall = sin((time * joints.length) % 1 * 2 * pi) / 2 + 0.5;
    int s = (time * joints.length).floor() % joints.length;

    // set last angle rotation to 0.5
    int lastS = (s - 1 + joints.length) % joints.length;
    robot!.trySetAngle(
        joints[lastS].key, 
        lerpDouble(joints[lastS].value.lower, joints[lastS].value.upper, 0.5)!,
    );

    robot!.trySetAngle(
        joints[s].key, 
        lerpDouble(joints[s].value.lower, joints[s].value.upper, periodicValueSmall)!,
        );

    // ...
}
```

## Supported Joint Types
 - fixed
 - continuous
 - revolute
 - prismatic
 - mimic

## Supported 3D File Types
 - .stl/ .STL (both binary and ascii variants)
 - .dae

## Additional Features
 - Supports color extraction of binary/ ascii stl files, dae files and basic urdf color nodes
 - Supports parsing of lines data of dae files

## Colors Formats
Besides the obvious defined material definition of dae files, also stl files can containt color information. But there is unfortunately no official standard.

This library supports the following stl color formats:

### Ascii STL Color Format
```
solid object1
  facet normal 0.0 0.0 0.0
    outer loop
      vertex 1.0 0.0 0.0
      vertex 0.0 1.0 0.0
      vertex 0.0 0.0 1.0
    endloop
  endfacet
endsolid object1=RGB(0,0,255)

solid object2
  facet normal 0.0 0.0 0.0
    outer loop
      vertex -1.0 0.0 0.0
      vertex 0.0 -1.0 0.0
      vertex 0.0 0.0 -1.0
    endloop
  endfacet
endsolid object2=RGB(255,0,0)
```

If color information is provided then each solid must contain it. Otherwise a default white materials is used for each solid.

### Binary STL Color Format
Supports the "Magics" color format from [https://en.wikipedia.org/wiki/STL_(file_format)#Binary](https://en.wikipedia.org/wiki/STL_(file_format)#Binary).

<!-- Each triangle is represented by 50 bytes:
 - **Normal vector:** The first 12 bytes (three 32-bit floating point numbers) represent the normal vector of the triangle.
 - **Vertices:** The next 36 bytes (three sets of three 32-bit floating point numbers) represent the vertices of the triangle.
 - **Attribute byte count:** The last 2 bytes (an unsigned short integer) represent the attribute byte count. In standard binary STL files, this should be set to zero and ignored. However, for binary STL files with color, these 2 bytes can be used to store color information. -->

## Note
As this library is a C# port of [https://github.com/gkjohnson/urdf-loaders](https://github.com/gkjohnson/urdf-loaders) which was written for Unity.
The library contains its own implementation of a hierarchy system using the `HierarchyNode` class with local/ global transformations.
The `getObject()` function on the `URDFRobot` class then formats the custom hierarchy implementation to a [three_dart](https://github.com/wasabia/three_dart) group with set children.

And as [three_dart](https://github.com/wasabia/three_dart) uses a coordinate system where the y-axis is facing up, a transformation is performed from the z-axis upwards facing stl/dae formats.