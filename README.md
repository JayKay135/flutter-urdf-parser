# Flutter URDF-Parser

![example animation](data/animation.gif)


This library is majorly an extended dart port of [https://github.com/gkjohnson/urdf-loaders](https://github.com/gkjohnson/urdf-loaders) for the dart three_js port of [https://github.com/wasabia/three_dart](https://github.com/wasabia/three_dart).

It includes a STL + DAE loader, URDF parser and quaternion + vector3 extension class.

Works with all plattforms that [three_dart](https://github.com/wasabia/three_dart) currently supports. Which are currently Web, iOS, Android, macOS and Windows.

## Basic Usage
Requires working [three_dart](https://github.com/wasabia/three_dart) project.

Inside of your `initPage()` function load your urdf model.

```dart
void initPage() async {
    scene = three.Scene();
    // ...

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
 - Supports color extraction of binary stl files, dae files and basic urdf color nodes

## NOTE
As this library is a C# port of [https://github.com/gkjohnson/urdf-loaders](https://github.com/gkjohnson/urdf-loaders) which was written for Unity.
The library contains its own implementation of a hierarchy system using the `HierarchyNode` class with local/ global transformations.
The `getObject()` function on the `URDFRobot` class then formats the custom hierarchy implementation to a [three_dart](https://github.com/wasabia/three_dart) group with set children.

And as [three_dart](https://github.com/wasabia/three_dart) uses a coordinate system where the y-axis is typically up, a transformation is performed for each stl/dae mesh where the z-axis is facing upwards.