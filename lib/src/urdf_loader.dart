import 'dart:io';
import 'dart:async';

import 'dae_loader.dart';
import 'stl_loader.dart';
import 'urdf_robot.dart';
import 'hierarchy nodes/hierarchy_node.dart';
import 'hierarchy nodes/mesh_hierarchy_component.dart';

import 'package:three_dart/three_dart.dart';
import 'package:urdf_parser/src/extensions.dart';
import 'package:xml/xml.dart';
import 'package:collection/collection.dart'; // for firstWhereOrNull implementation

import 'package:path/path.dart' as p;

class URDFLoaderOptions {
  Function(String, String, Function(List<HierarchyNode>))? loadMeshCb;
  String? workingPath;
  URDFRobot? target;

  URDFLoaderOptions({this.loadMeshCb, this.workingPath, this.target});
}

class URDFLoader {
  static const String singlePackageKey = "<DEFAULT>";

  /// Parses a URDF file located at [urdfPath] with package dependencies specified in [packages].
  ///
  /// Returns a [URDFRobot] object representing the parsed robot, or `null` if parsing failed.
  ///
  /// If [options] are provided, they will be used to configure the parser.
  static Future<URDFRobot?> parseWithPackages(String urdfPath,
      Map<String, String> packages, URDFLoaderOptions? options) async {
    File file = File(urdfPath);
    String content;
    if (await file.exists()) {
      content = await file.readAsString();
    } else {
      throw Exception("File not found at $urdfPath");
    }

    options ??= URDFLoaderOptions();

    if (options.workingPath == null) {
      // Uri uri = Uri(path: urdfPath);
      // options.workingPath = uri.host + Path.getDirectoryName(uri.PathAndQuery);

      Uri uri = Uri.parse(urdfPath);
      options.workingPath =
          '${uri.host}/${uri.pathSegments.take(uri.pathSegments.length - 1).join('/')}';
    }

    return parseInternal(content, packages, options);
  }

  /// Parse the URDF file and return a URDFRobot instance with all associated links and joints
  static Future<URDFRobot?> parse(
      String urdfPath, String package, URDFLoaderOptions? options) {
    Map<String, String> packages = {};
    packages[singlePackageKey] = package;

    return parseWithPackages(urdfPath, packages, options);
  }

  static Future<URDFRobot?> parseInternal(String urdfContent,
      Map<String, String> packages, URDFLoaderOptions? options) async {
    options ??= URDFLoaderOptions();

    options.loadMeshCb ??= loadMesh;

    // Parse the XML doc
    XmlDocument doc = XmlDocument.parse(urdfContent);

    // Store the information about the link and the objects indexed by link name
    Map<String, XmlElement> xmlLinks = {};
    Map<String, XmlElement> xmlJoints = {};

    /// Indexed by joint name
    Map<String, URDFJoint> urdfJoints = {};

    /// Indexed by link name
    Map<String, URDFLink> urdfLinks = {};

    /// Indexed by material name
    Map<String, Material> urdfMaterials = {};

    /// Map of all mimic joints
    /// Key: Name of mimiced joint
    /// Value: Actual mimicing joint
    Map<String, URDFJoint> mimicJoints = {};

    // First node is the <robot> node
    XmlElement? robotNode = doc.childElements
        .firstWhereOrNull((element) => element.localName == "robot");

    if (robotNode == null) {
      throw Exception("Robot Node missing");
    }

    String robotName = robotNode.getAttribute("name")!;

    List<XmlElement> xmlLinksArray =
        getXmlElementChildrenByName(robotNode, "link");
    List<XmlElement> xmlJointsArray =
        getXmlElementChildrenByName(robotNode, "joint");

    // load global materials
    List<XmlElement> xmlMaterialsArray =
        getXmlElementChildrenByName(robotNode, "material", recursive: true);

    for (XmlElement materialNode in xmlMaterialsArray) {
      // if (materialNode.getAttribute("name") != null) {
      //   String materialName = materialNode.getAttribute("name")!;
      //   if (!urdfMaterials.containsKey(materialName)) {
      //     Color color = Color(1.0, 1.0, 1.0); // white
      //     XmlElement? colorNode = getXmlElementChildByName(materialNode, "color");

      //     if (colorNode != null) {
      //       color = tupleToColor(colorNode.getAttribute("rgba")!);
      //     }

      //     Material material = MeshPhongMaterial({"color": color.getHex(), "flatShading": false, "side": DoubleSide});
      //     urdfMaterials[materialName] = material;
      //   }
      // }

      XmlElement? colorNode = getXmlElementChildByName(materialNode, "color");
      String? materialName = materialNode.getAttribute("name");

      if (colorNode != null && materialName != null) {
        Color color = tupleToColor(colorNode.getAttribute("rgba")!);
        Material material = MeshPhongMaterial({
          "color": color.getHex(),
          "flatShading": false,
          "side": DoubleSide
        });

        urdfMaterials[materialName] = material;
      } else {
        // no color found
        //material = MeshPhongMaterial({"color": 0xff0000, "flatShading": false, "side": DoubleSide});
      }
    }

    // cycle through the links and instantiate the geometry
    for (XmlElement linkNode in xmlLinksArray) {
      // store the XML node for the link
      String? linkName = linkNode.getAttribute("name");

      if (linkName == null) {
        throw Exception("Link name missing");
      }

      xmlLinks[linkName] = linkNode;

      // create the link gameobject
      URDFLink urdfLink = URDFLink.identity(linkName);
      urdfLinks[linkName] = urdfLink;

      // get the geometry node and skip it if there isn't one
      List<XmlElement> visualNodesArray =
          getXmlElementChildrenByName(linkNode, "visual");
      List<HierarchyNode> renderers = [];
      urdfLink.geometry = renderers;

      // iterate over all the visual nodes
      for (XmlElement xmlVisual in visualNodesArray) {
        XmlElement? geomNode = getXmlElementChildByName(xmlVisual, "geometry");
        if (geomNode == null) {
          continue;
        }

        // parse material data if available
        Material? material;
        XmlElement? materialNode =
            getXmlElementChildByName(xmlVisual, "material");
        if (materialNode != null) {
          XmlElement? colorNode =
              getXmlElementChildByName(materialNode, "color");

          String? materialName = materialNode.getAttribute("name");

          if (colorNode != null) {
            Color color = tupleToColor(colorNode.getAttribute("rgba")!);
            material = MeshPhongMaterial({
              "color": color.getHex(),
              "flatShading": false,
              "side": DoubleSide
            });
          } else if (materialName != null &&
              urdfMaterials.containsKey(materialName)) {
            material = urdfMaterials[materialName]!;
          } else {
            // no color found
            //material = MeshPhongMaterial({"color": 0xff0000, "flatShading": false, "side": DoubleSide});
          }
        }

        // get the mesh and the origin nodes
        XmlElement? originNode = getXmlElementChildByName(xmlVisual, "origin");

        // extract the position and rotation of the mesh
        Vector3 position = Vector3()..zero();
        if (originNode != null && originNode.getAttribute("xyz") != null) {
          position = tupleToVector3(originNode.getAttribute("xyz")!);
        }
        position = urdfToThreePos(position);

        Vector3 rotation = Vector3()..zero();
        if (originNode != null && originNode.getAttribute("rpy") != null) {
          rotation = tupleToVector3(originNode.getAttribute("rpy")!);
        }
        rotation = urdfToThreeRot(rotation);

        XmlElement meshNode = getXmlElementChildByName(geomNode, "mesh") ??
            getXmlElementChildByName(geomNode, "box") ??
            getXmlElementChildByName(geomNode, "sphere") ??
            getXmlElementChildByName(geomNode, "cylinder")!;

        try {
          if (meshNode.localName == "mesh") {
            // extract the mesh path
            String fileName = resolveMeshPath(
                meshNode.getAttribute("filename")!,
                packages,
                options.workingPath!);

            // extract the scale from the mesh node
            Vector3 scale = Vector3()..one();
            if (meshNode.getAttribute("scale") != null) {
              scale = tupleToVector3(meshNode.getAttribute("scale")!);
            }
            scale = urdfToThreeScale(scale);

            // load all meshes
            // String extension = Path.GetExtension(fileName).ToLower().Replace(".", "");
            // extracts the file extension from the given fileName
            String extension = fileName.split('.').last.toLowerCase();
            await options.loadMeshCb!(fileName, extension,
                (List<HierarchyNode> models) {
              // print("models: ${models.length}: $fileName");
              // create the rest of the meshes and child them to the click target
              for (int i = 0; i < models.length; i++) {
                HierarchyNode meshTransform = models[i];

                // Capture the original local transforms before parenting in case the loader or model came in
                // with existing pose information and then apply our transform on top of it.
                Vector3 originalLocalPosition = meshTransform.localPosition;
                Quaternion originalLocalRotation = meshTransform.localRotation;
                Vector3 originalLocalScale = meshTransform.scale;
                Vector3 transformedScale = originalLocalScale * scale;
                // transformedScale.x *= scale.x;
                // transformedScale.y *= scale.y;
                // transformedScale.z *= scale.z;

                urdfLink.addChild(meshTransform);

                meshTransform.localPosition = originalLocalPosition + position;
                meshTransform.localRotation =
                    originalLocalRotation * Quaternion()
                      ..setFromEuler(Euler()..setFromVector3(rotation, "YZX"));
                meshTransform.scale = transformedScale;

                meshTransform.name = "${urdfLink.name} geometry $i";
                renderers.add(meshTransform);

                // set the material
                if (material != null) {
                  MeshHierarchyComponent meshHierarchyComponent = meshTransform
                      .getComponent('mesh') as MeshHierarchyComponent;

                  // prioritise the dae/ stl color information over urdf data
                  // if (meshHierarchyComponent.mesh.material == null) {
                  //   meshHierarchyComponent.mesh.material = material;
                  // }

                  // meshHierarchyComponent.mesh.material ??= material;

                  meshHierarchyComponent.mesh.material ??= material;
                }
              }
            });
          } else {
            // create the primitive geometry
            XmlElement primitiveNode = meshNode;
            HierarchyNode? primitiveObject;

            BufferGeometry? bufferGeometry;
            switch (primitiveNode.localName) {
              case "box":
                {
                  primitiveObject = HierarchyNode.identity("cube");

                  Vector3 boxScale =
                      tupleToVector3(primitiveNode.getAttribute("size")!);
                  boxScale = urdfToThreePos(boxScale);
                  bufferGeometry =
                      BoxGeometry(boxScale.x, boxScale.y, boxScale.z);
                  break;
                }

              case "sphere":
                {
                  primitiveObject = HierarchyNode.identity("sphere");

                  double sphereRadius =
                      double.parse(primitiveNode.getAttribute("radius")!);

                  bufferGeometry = SphereGeometry(sphereRadius);
                  break;
                }

              case "cylinder":
                {
                  primitiveObject = HierarchyNode.identity("cylinder");

                  double length =
                      double.parse(primitiveNode.getAttribute("length")!);
                  double radius =
                      double.parse(primitiveNode.getAttribute("radius")!);

                  // determine amount of radial segments from radius
                  int radialSegments = Math.max(12, Math.ceil(radius * 6));

                  bufferGeometry =
                      CylinderGeometry(radius, radius, length, radialSegments);
                  break;
                }
            }

            if (primitiveObject != null) {
              // add the material if available
              if (material != null) {
                primitiveObject.addComponent(MeshHierarchyComponent(
                    Mesh(bufferGeometry, material), "mesh"));
              }

              // position the transform
              urdfLink.addChild(primitiveObject);
              primitiveObject.localPosition = position;
              primitiveObject.localRotation = Quaternion()
                ..setFromEuler(Euler()..setFromVector3(rotation, "YZX"));
              primitiveObject.name =
                  "${urdfLink.name} geometry ${primitiveNode.localName}";

              renderers.add(primitiveObject);
            }
          }
        } on Exception catch (_, e) {
          throw Exception("Error loading model for ${urdfLink.name} : $e");
        }
      }
    }

    // cycle through the joint nodes
    for (XmlElement jointNode in xmlJointsArray) {
      String jointName = jointNode.getAttribute("name")!;

      // store the joints indexed by child name so we can find it later
      // to properly indicate the parents in the joint list
      xmlJoints[jointName] = jointNode;

      // get the links by name
      XmlElement? parentNode = getXmlElementChildByName(jointNode, "parent");
      XmlElement? childNode = getXmlElementChildByName(jointNode, "child");
      String parentName = parentNode!.getAttribute("link")!;
      String childName = childNode!.getAttribute("link")!;
      URDFLink parentLink = urdfLinks[parentName]!;
      URDFLink childLink = urdfLinks[childName]!;

      // create the joint
      URDFJoint urdfJoint = URDFJoint(
        localPosition: Vector3()..zero(),
        localRotation: Quaternion()..identity(),
        scale: Vector3()..one(),
        name: jointName,
        originalPosition: Vector3()..zero(),
        originalRotation: Quaternion()..identity(),
        parentLink: parentLink,
        type: jointNode.getAttribute("type")!,
      );

      // set the tree hierarchy
      // parent the joint to its parent link
      urdfJoint.parentLink = parentLink;
      parentLink.addChild(urdfJoint);

      // parent the child link to this joint
      urdfJoint.childLink = childLink;
      urdfJoint.addChild(childLink);

      childLink.localPosition = Vector3()..zero();
      childLink.localRotation = Quaternion()..identity();

      // position the origin if it's specified
      XmlElement? transformNode = getXmlElementChildByName(jointNode, "origin");
      Vector3 position = Vector3()..zero();
      if (transformNode != null && transformNode.getAttribute("xyz") != null) {
        position = tupleToVector3(transformNode.getAttribute("xyz")!);
      }
      position = urdfToThreePos(position);

      Vector3 rotation = Vector3()..zero();
      if (transformNode != null && transformNode.getAttribute("rpy") != null) {
        rotation = tupleToVector3(transformNode.getAttribute("rpy")!);
      }
      rotation = urdfToThreeRot(rotation);

      // parent the joint and name it
      urdfJoint.localPosition = position.clone();
      urdfJoint.localRotation = Quaternion()
        ..setFromEuler(Euler()..setFromVector3(rotation, "YZX"));
      // TODO: Check if clone is actually necessary
      urdfJoint.originalPosition = position.clone();
      urdfJoint.originalRotation = Quaternion()
        ..setFromEuler(Euler()..setFromVector3(rotation, "YZX"));

      // get and set axis information
      XmlElement? axisNode = getXmlElementChildByName(jointNode, "axis");
      if (axisNode != null) {
        Vector3 axis = tupleToVector3(axisNode.getAttribute("xyz")!) * -1;
        axis = urdfToThreePos(axis);
        axis.normalize();

        urdfJoint.axis = axis;
      }

      // get and set limit information
      XmlElement? limitNode = getXmlElementChildByName(jointNode, "limit");
      if (limitNode != null) {
        if (limitNode.getAttribute("lower") != null) {
          urdfJoint.lower = double.parse(limitNode.getAttribute("lower")!);
        }

        if (limitNode.getAttribute("upper") != null) {
          urdfJoint.upper = double.parse(limitNode.getAttribute("upper")!);
        }
      }

      // handle mimic joints
      XmlElement? mimicNode = getXmlElementChildByName(jointNode, "mimic");
      if (mimicNode != null) {
        String jointName = mimicNode.getAttribute("joint")!;

        if (mimicNode.getAttribute("multiplier") != null) {
          urdfJoint.multiplier =
              double.parse(mimicNode.getAttribute("multiplier")!);
        }

        if (mimicNode.getAttribute("offset") != null) {
          urdfJoint.offset = double.parse(mimicNode.getAttribute("offset")!);
        }

        // add the mimicing joint
        mimicJoints[jointName] = urdfJoint;
      }

      // save the URDF joint
      urdfJoints[urdfJoint.name] = urdfJoint;
    }

    // loop through all mimic joints and add them to the joints they are mimicing
    for (MapEntry<String, URDFJoint> entry in mimicJoints.entries) {
      urdfJoints[entry.key]!.mimicJoints.add(entry.value);
    }

    // loop through all the transforms until we find the one that has no parent
    URDFRobot? robot = options.target;
    for (MapEntry<String, URDFLink> kv in urdfLinks.entries) {
      if (kv.value.parent == null) {
        // find the top most node and add a joint list to it
        if (robot == null) {
          robot = kv.value
                  .addComponent(URDFRobot(name: "robot", transform: kv.value))
              as URDFRobot;
        } else {
          robot.transform.addChild(kv.value);

          kv.value.localPosition = Vector3()..zero();
          kv.value.localRotation = Quaternion()..identity();
        }

        robot.links = urdfLinks;
        robot.joints = urdfJoints;

        // validate robot for consistency
        robot.isConsistent();
        return robot;
      }
    }
    robot!.name = robotName;

    return null;
  }

  /// Loads a mesh from a file with the given path and extension.
  /// Can load .stl, .STL, .dae files
  ///
  /// The [done] callback function is called with a list of [HierarchyNode] objects
  /// representing the loaded mesh when the loading is complete.
  static Future<void> loadMesh(
      String path, String ext, Function(List<HierarchyNode>) done) async {
    List<Object3D> meshes = [];
    if (ext == "stl" || ext == "STL") {
      Mesh mesh = await STLLoader(null).loadAsync(path);
      meshes.add(mesh);
    } else if (ext == "dae") {
      List<Object3D> daeMeshes = await DAELoader.loadFromPath(path, []);
      meshes.addAll(daeMeshes);
    } else {
      throw Exception("Filetype '$ext' not supported");
    }

    List<HierarchyNode> result = [];
    for (int i = 0; i < meshes.length; i++) {
      HierarchyNode gameObject =
          HierarchyNode.identity(""); //.CreatePrimitive(PrimitiveType.Cube);
      Object3D mesh = meshes[i];

      gameObject.addComponent(MeshHierarchyComponent(mesh, "mesh"));

      result.add(gameObject);
    }

    done(result);
  }

  /// Removes the leading slash from the given [path] string.
  ///
  /// Returns the modified string.
  static String removeLeadingSlash(String path) {
    if (path.startsWith('/') || path.startsWith('\\')) {
      path = path.substring(1);
    }

    return path.replaceAll("\\", "/");
  }

  /// Resolves the given mesh path with the package options and working paths to return a full path to the mesh file.
  static String resolveMeshPath(
      String path, Map<String, String> packages, String workingPath) {
    if (path.indexOf("package://") != 0) {
      return removeLeadingSlash(p.normalize(p.join(workingPath, path)));
      // workingPath.combinePath(path);
    }

    // extract the package name
    String str = path.replaceFirst('package://', '');
    int index = str.indexOf(RegExp(r'[\/\\]'));

    String targetPackage = str.substring(0, index);
    String remaining = str.substring(index + 1);

    if (packages.containsKey(targetPackage)) {
      return removeLeadingSlash(
          p.normalize(p.join((packages[targetPackage] as String), remaining)));
      // (packages[targetPackage] as String).combinePath(remaining);
    } else if (packages.containsKey(singlePackageKey)) {
      String packagePath = packages[singlePackageKey]!;
      if (packagePath.endsWith(targetPackage)) {
        return removeLeadingSlash(p.normalize(p.join(packagePath, remaining)));
        // packagePath.combinePath(remaining);
      } else {
        return removeLeadingSlash(
            p.normalize(p.join(packagePath, targetPackage, remaining)));
        //packagePath.combinePath(targetPackage).combinePath(remaining);
      }
    }

    throw Exception(
        "URDFLoader: $targetPackage not found in provided package list!");
  }

  /// Returns all instances of found child nodes with the name [name], empty list if none could be found
  static List<XmlElement> getXmlElementChildrenByName(
      XmlElement parent, String name,
      {bool recursive = false}) {
    if (!recursive)
      return parent.childElements
          .where((element) => element.localName == name)
          .toList();

    List<XmlElement> nodes = [];
    for (XmlElement n in parent.childElements) {
      if (n.localName == name) {
        nodes.add(n);
      }

      if (recursive) {
        List<XmlElement> recursiveChildren =
            getXmlElementChildrenByName(n, name, recursive: true);
        for (XmlElement x in recursiveChildren) {
          nodes.add(x);
        }
      }
    }

    return nodes;
  }

  /// Returns the first instance of a child node with the name [name], null if it couldn't be found
  static XmlElement? getXmlElementChildByName(XmlElement parent, String name) {
    return parent.childElements
        .firstWhereOrNull((element) => element.localName == name);
  }

  /// Converts a String of the form "x y z" into a [Vector3]
  static Vector3 tupleToVector3(String str) {
    str = str.trim();
    str = str.replaceAll("\\s+", " ");

    List<String> numbers = str.split(' ');

    Vector3 result = Vector3(0, 0, 0);
    if (numbers.length == 3) {
      try {
        result.x = double.parse(numbers[0]);
        result.y = double.parse(numbers[1]);
        result.z = double.parse(numbers[2]);
      } on Exception catch (_, e) {
        print(str);
        print(e);
      }
    }

    return result;
  }

  /// Converts a string tuple to a Color object.
  ///
  /// The [str] parameter is a string representation of a tuple in the format "(r, g, b, a)".
  /// Returns a [Color] object with the corresponding RGBA values.
  static Color tupleToColor(String str) {
    str = str.trim();
    str = str.replaceAll("\\s+", " ");

    List<String> numbers = str.split(' ');
    Color result = Color();

    if (numbers.length == 4) {
      try {
        result.r = double.parse(numbers[0]);
        result.g = double.parse(numbers[1]);
        result.b = double.parse(numbers[2]);

        // NOTE: Alpha channel not used by three_js
        // double a = (double.parse(numbers[3]));
      } on Exception catch (_, e) {
        print(str);
        print(e);
      }
    }

    return result;
  }

  /// Converts a [Vector3] from URDF coordinate system to Unity coordinate system.
  ///
  /// URDF
  /// Y left
  /// Z up
  /// X forward
  ///
  /// Unity
  /// X right
  /// Y up
  /// Z forward
  // static Vector3 urdfToUnityPos(Vector3 v) {
  //   return Vector3(-v.y, v.z, v.x);
  // }

  /// Converts a Vector3 object from URDF format to Three.js format.
  static Vector3 urdfToThreePos(Vector3 v) {
    return Vector3(v.x, v.z, -v.y);
  }

  /// Converts a [Vector3] from URDF scale to Unity scale.
  ///
  /// The [v] parameter is the [Vector3] to be converted.
  /// Returns a new [Vector3] with the converted scale.
  // static Vector3 urdfToUnityScale(Vector3 v) {
  //   return Vector3(v.y, v.z, v.x);
  // }

  /// Converts a [Vector3] from URDF scale to Three.js scale.
  ///
  /// The [v] parameter is the [Vector3] to be converted.
  /// Returns a new [Vector3] with the converted scale.
  static Vector3 urdfToThreeScale(Vector3 v) {
    return Vector3(v.x, v.z, v.y);
  }

  /// Converts a [Vector3] from URDF format to Unity rotation format.
  ///
  /// The [v] parameter is the [Vector3] to be converted.
  /// Returns a new [Vector3] in Unity rotation format.
  ///
  /// URDF
  /// Fixed Axis rotation, XYZ
  /// roll on X
  /// pitch on Y
  /// yaw on Z
  /// radians
  ///
  /// Unity
  /// roll on Z
  /// yaw on Y
  /// pitch on X
  /// degrees
  // static Vector3 urdfToUnityRot(Vector3 v) {
  //   // Negate X and Z because we're going from Right to Left handed rotations. Y is handled because the axis itself is flipped
  //   v.x *= -1;
  //   v.z *= -1;
  //
  //   // swap the angle values
  //   v = Vector3(v.y, v.z, v.x);
  //
  //   return v;
  // }

  static Vector3 urdfToThreeRot(Vector3 v) {
    // Negate X and Z because we're going from Right to Left handed rotations. Y is handled because the axis itself is flipped
    // v.x *= -1;
    // v.z *= -1;
    // v.y *= -1;

    // swap the angle values
    v = Vector3(v.x, v.z, -v.y);
    // v = Vector3(v.x, -v.z, v.y);

    return v;
  }
}
