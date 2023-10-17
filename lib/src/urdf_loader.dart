/*
Reference coordinate frames for Unity and ROS.
The Unity coordinate frame is left handed and ROS is right handed, so
the axes are transformed to line up appropriately. See the "URDFToUnityPos"
and "URDFToUnityRot" functions.

Unity
   Y
   |   Z
   | ／
   .-----X


ROS URDf
       Z
       |   X
       | ／
 Y-----.

*/

import 'dart:io';
import 'dart:async';

import 'package:urdf_parser/src/xml_functions.dart';

import 'dae_loader.dart';
import 'stl_loader.dart';
import 'urdf_robot.dart';
import 'hierarchy nodes/hierarchy_node.dart';
import 'hierarchy nodes/mesh_hierarchy_component.dart';

import 'package:three_dart/three_dart.dart';
import 'package:urdf_parser/src/extensions.dart';
import 'package:xml/xml.dart';
import 'package:collection/collection.dart'; // for firstWhereOrNull implementation

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
  static Future<URDFRobot?> parseWithPackages(String urdfPath, Map<String, String> packages, {URDFLoaderOptions? options}) async {
    File file = File(urdfPath);
    String content = await file.readAsString();

    options ??= URDFLoaderOptions();

    if (options.workingPath == null) {
      Uri uri = Uri.parse(urdfPath);
      options.workingPath = '${uri.host}/${uri.pathSegments.take(uri.pathSegments.length - 1).join('/')}';
    }

    return parseInternal(content, packages, options);
  }

  /// Parse the URDF file and return a URDFRobot instance with all associated links and joints
  static Future<URDFRobot?> parse(String urdfPath, String package, {URDFLoaderOptions? options}) {
    Map<String, String> packages = {};
    packages[singlePackageKey] = package;

    return parseWithPackages(urdfPath, packages, options: options);
  }

  /// Parses the URDF content and returns a [URDFRobot] object.
  ///
  /// The [urdfContent] parameter is the URDF content to be parsed.
  /// The [packages] parameter is a map of package names and their corresponding paths.
  /// The [options] parameter is an optional [URDFLoaderOptions] object that can be used to customize the parsing process.
  ///
  /// Returns a [URDFRobot] object if the parsing is successful, otherwise returns null.
  static Future<URDFRobot?> parseInternal(String urdfContent, Map<String, String> packages, URDFLoaderOptions? options) async {
    options ??= URDFLoaderOptions();

    options.loadMeshCb ??= loadMesh;

    // Parse the XML doc
    XmlDocument doc = XmlDocument.parse(urdfContent);

    // Store the information about the link and the objects indexed by link name
    Map<String, XmlElement> xmlLinks = {};
    Map<String, XmlElement> xmlJoints = {};

    // Indexed by joint name
    Map<String, URDFJoint> urdfJoints = {};
    Map<String, URDFLink> urdfLinks = {};
    Map<String, Material> urdfMaterials = {};

    // Indexed by joint name
    Map<String, String> parentNames = {};

    // First node is the <robot> node
    XmlElement? robotNode = doc.childElements.firstWhereOrNull((element) => element.localName == "robot");

    if (robotNode == null) {
      throw Exception("Robot Node missing");
    }

    String robotName = robotNode.getAttribute("name")!;

    List<XmlElement> xmlLinksArray = XMLFunctions.getXmlElementChildrenByName(robotNode, "link");
    List<XmlElement> xmlJointsArray = XMLFunctions.getXmlElementChildrenByName(robotNode, "joint");
    List<XmlElement> xmlMaterialsArray = XMLFunctions.getXmlElementChildrenByName(robotNode, "material", recursive: true);

    for (XmlElement materialNode in xmlMaterialsArray) {
      if (materialNode.getAttribute("name") != null) {
        String materialName = materialNode.getAttribute("name")!;
        if (!urdfMaterials.containsKey(materialName)) {
          Color color = Color(1.0, 1.0, 1.0); // white
          XmlElement? colorNode = XMLFunctions.getXmlElementChildByName(materialNode, "color");

          if (colorNode != null) {
            color = tupleToColor(colorNode.getAttribute("rgba")!);
          }

          Material material = MeshPhongMaterial({"color": color.getHex(), "flatShading": false, "side": DoubleSide});
          urdfMaterials[materialName] = material;
        }
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

      // create the link node
      URDFLink urdfLink = URDFLink.identity(linkName);
      urdfLinks[linkName] = urdfLink;

      // get the geometry node and skip it if there isn't one
      List<XmlElement> visualNodesArray = XMLFunctions.getXmlElementChildrenByName(linkNode, "visual");
      List<HierarchyNode> renderers = [];
      urdfLink.geometry = renderers;

      // iterate over all the visual nodes
      for (XmlElement xmlVisual in visualNodesArray) {
        XmlElement? geomNode = XMLFunctions.getXmlElementChildByName(xmlVisual, "geometry");
        if (geomNode == null) {
          continue;
        }

        Material? material;
        XmlElement? materialNode = XMLFunctions.getXmlElementChildByName(xmlVisual, "material");
        if (materialNode != null) {
          if (materialNode.getAttribute("name") != null) {
            String materialName = materialNode.getAttribute("name")!;
            material = urdfMaterials[materialName]!;
          } else {
            Color color = Color(1.0, 1.0, 1.0); // white
            XmlElement? colorNode = XMLFunctions.getXmlElementChildByName(materialNode, "color");
            if (colorNode != null) {
              color = tupleToColor(colorNode.getAttribute("rgba")!);
            }

            material = MeshPhongMaterial({"color": color.getHex(), "flatShading": false, "side": DoubleSide});

            // TODO: Load the textures
            // XmlElement? texNode = XMLFunctions.getXmlElementChildByName(materialNode, "texture");
            // if (texNode != null) {

            // }
          }
        }

        // get the mesh and the origin nodes
        XmlElement? originNode = XMLFunctions.getXmlElementChildByName(xmlVisual, "origin");

        // extract the position and rotation of the mesh
        Vector3 position = Vector3()..zero();
        if (originNode != null && originNode.getAttribute("xyz") != null) {
          position = tupleToVector3(originNode.getAttribute("xyz")!);
        }
        position = urdfToUnityPos(position);

        Vector3 rotation = Vector3()..zero();
        if (originNode != null && originNode.getAttribute("rpy") != null) {
          rotation = tupleToVector3(originNode.getAttribute("rpy")!);
        }
        rotation = urdfToUnityRot(rotation);

        XmlElement meshNode = XMLFunctions.getXmlElementChildByName(geomNode, "mesh") ??
            XMLFunctions.getXmlElementChildByName(geomNode, "box") ??
            XMLFunctions.getXmlElementChildByName(geomNode, "sphere") ??
            XMLFunctions.getXmlElementChildByName(geomNode, "cylinder")!;

        try {
          if (meshNode.localName == "mesh") {
            // extract the mesh path
            String fileName = resolveMeshPath(meshNode.getAttribute("filename")!, packages, options.workingPath!);

            // extract the scale from the mesh node
            Vector3 scale = Vector3()..one();
            if (meshNode.getAttribute("scale") != null) {
              scale = tupleToVector3(meshNode.getAttribute("scale")!);
            }
            scale = urdfToUnityScale(scale);

            // load all meshes
            // extracts the file extension from the given fileName
            String extension = fileName.split('.').last.toLowerCase();
            await options.loadMeshCb!(fileName, extension, (List<HierarchyNode> models) {
              // print("models: ${models.length}: $fileName");
              // create the rest of the meshes and child them to the click target
              for (int i = 0; i < models.length; i++) {
                HierarchyNode modelGameObject = models[i];
                HierarchyNode meshTransform = modelGameObject;

                // Capture the original local transforms before parenting in case the loader or model came in
                // with existing pose information and then apply our transform on top of it.
                Vector3 originalLocalPosition = meshTransform.localPosition;
                Quaternion originalLocalRotation = meshTransform.localRotation;
                Vector3 originalLocalScale = meshTransform.scale;
                Vector3 transformedScale = originalLocalScale;
                transformedScale.x *= scale.x;
                transformedScale.y *= scale.y;
                transformedScale.z *= scale.z;

                urdfLink.addChild(meshTransform);
                meshTransform.localPosition = originalLocalPosition + position;
                meshTransform.localRotation = originalLocalRotation * Quaternion()
                  ..setFromEuler(Euler()..setFromVector3(rotation));
                meshTransform.scale = transformedScale;

                modelGameObject.name = "${urdfLink.name} geometry $i";
                renderers.add(modelGameObject);

                // set the material
                if (material != null) {
                  MeshHierarchyComponent meshHierarchyComponent = modelGameObject.getComponent('mesh') as MeshHierarchyComponent;
                  meshHierarchyComponent.mesh.material = material;
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

                  Vector3 boxScale = tupleToVector3(primitiveNode.getAttribute("size")!);
                  boxScale = urdfToUnityPos(boxScale);
                  bufferGeometry = BoxGeometry(boxScale.x, boxScale.y, boxScale.z);
                  break;
                }

              case "sphere":
                {
                  primitiveObject = HierarchyNode.identity("sphere");

                  double sphereRadius = double.parse(primitiveNode.getAttribute("radius")!);

                  bufferGeometry = SphereGeometry(sphereRadius);
                  break;
                }

              case "cylinder":
                {
                  primitiveObject = HierarchyNode.identity("cylinder");

                  double length = double.parse(primitiveNode.getAttribute("length")!);
                  double radius = double.parse(primitiveNode.getAttribute("radius")!);

                  // determine amount of radial segments from radius
                  int radialSegments = Math.max(12, Math.ceil(radius * 6));

                  bufferGeometry = CylinderGeometry(radius, radius, length, radialSegments);
                  break;
                }
            }

            if (primitiveObject != null) {
              // add the material if available
              if (material != null) {
                primitiveObject.addComponent(MeshHierarchyComponent(Mesh(bufferGeometry, material), "mesh"));
              }

              // position the transform
              urdfLink.addChild(primitiveObject);
              primitiveObject.localPosition = position;
              primitiveObject.localRotation = Quaternion()..setFromEuler(Euler()..setFromVector3(rotation));
              primitiveObject.name = "${urdfLink.name} geometry ${primitiveNode.localName}";

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
      XmlElement? parentNode = XMLFunctions.getXmlElementChildByName(jointNode, "parent");
      XmlElement? childNode = XMLFunctions.getXmlElementChildByName(jointNode, "child");
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
      XmlElement? transformNode = XMLFunctions.getXmlElementChildByName(jointNode, "origin");
      Vector3 position = Vector3()..zero();
      if (transformNode != null && transformNode.getAttribute("xyz") != null) {
        position = tupleToVector3(transformNode.getAttribute("xyz")!);
      }
      position = urdfToUnityPos(position);

      Vector3 rotation = Vector3()..zero();
      if (transformNode != null && transformNode.getAttribute("rpy") != null) {
        rotation = tupleToVector3(transformNode.getAttribute("rpy")!);
      }
      rotation = urdfToUnityRot(rotation);

      // parent the joint and name it
      urdfJoint.localPosition = position;
      urdfJoint.localRotation = Quaternion()..setFromEuler(Euler()..setFromVector3(rotation));
      // TODO: Check if clone is actually necessary
      urdfJoint.originalPosition = position.clone();
      urdfJoint.originalRotation = Quaternion()..setFromEuler(Euler()..setFromVector3(rotation));

      // get and set axis information
      XmlElement? axisNode = XMLFunctions.getXmlElementChildByName(jointNode, "axis");
      if (axisNode != null) {
        Vector3 axis = tupleToVector3(axisNode.getAttribute("xyz")!) * -1;
        axis = urdfToUnityPos(axis);
        axis.normalize();

        urdfJoint.axis = axis;
      }

      // get and set limit information
      XmlElement? limitNode = XMLFunctions.getXmlElementChildByName(jointNode, "limit");
      if (limitNode != null) {
        if (limitNode.getAttribute("lower") != null) {
          urdfJoint.lower = double.parse(limitNode.getAttribute("lower")!);
        }

        if (limitNode.getAttribute("upper") != null) {
          urdfJoint.upper = double.parse(limitNode.getAttribute("upper")!);
        }
      }

      // save the URDF joint
      urdfJoints[urdfJoint.name] = urdfJoint;
    }

    // loop through all the transforms until we find the one that has no parent
    URDFRobot? robot = options.target;
    for (MapEntry<String, URDFLink> kv in urdfLinks.entries) {
      if (kv.value.parent == null) {
        // find the top most node and add a joint list to it
        if (robot == null) {
          robot = kv.value.addComponent(URDFRobot(name: "robot", transform: kv.value)) as URDFRobot;
        } else {
          robot.transform.addChild(kv.value);

          kv.value.localPosition = Vector3()..zero();
          kv.value.localRotation = Quaternion()..identity();
        }

        robot.links = urdfLinks;
        robot.joints = urdfJoints;

        robot.isConsistent();
        return robot;
      }
    }
    robot!.name = robotName;

    return null;
  }

  /// Default mesh loading function that can load STL's and DAE's from file
  static Future<void> loadMesh(String path, String ext, Function(List<HierarchyNode>) done) async {
    List<Mesh> meshes = [];
    if (ext == "stl" || ext == "STL") {
      Mesh mesh = await STLLoader(null).loadAsync(path);
      meshes.add(mesh);
    } else if (ext == "dae") {
      List<Mesh> daeMeshes = await DAELoader.loadFromPath(path);
      meshes.addAll(daeMeshes);
    } else {
      throw Exception("Filetype '$ext' not supported");
    }

    List<HierarchyNode> result = [];
    for (int i = 0; i < meshes.length; i++) {
      HierarchyNode gameObject = HierarchyNode.identity("cube");
      Mesh mesh = meshes[i];

      gameObject.addComponent(MeshHierarchyComponent(mesh, "mesh"));

      result.add(gameObject);
    }

    done(result);
  }

  /// Resolves the given mesh path with the package options and working paths to return a full path to the mesh file.
  static String resolveMeshPath(String path, Map<String, String> packages, String workingPath) {
    if (path.indexOf("package://") != 0) {
      return workingPath.combinePath(path);
    }

    // extract the package name
    String str = path.replaceFirst('package://', '');
    int index = str.indexOf(RegExp(r'[\/\\]'));

    String targetPackage = str.substring(0, index);
    String remaining = str.substring(index + 1);

    if (packages.containsKey(targetPackage)) {
      return (packages[targetPackage] as String).combinePath(remaining);
    } else if (packages.containsKey(singlePackageKey)) {
      String packagePath = packages[singlePackageKey]!;
      if (packagePath.endsWith(targetPackage)) {
        return packagePath.combinePath(remaining);
      } else {
        return packagePath.combinePath(targetPackage).combinePath(remaining);
      }
    }

    throw Exception("URDFLoader: $targetPackage not found in provided package list!");
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
  /// The string tuple should be in the format "r g b a", where r, g, b, and a are integers between 0 and 255.
  /// Returns a Color object.
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
  static Vector3 urdfToUnityPos(Vector3 v) {
    return Vector3(-v.y, v.z, v.x);
  }

  /// Converts a [Vector3] from URDF scale to Unity scale.
  ///
  /// The [v] parameter is the [Vector3] to be converted.
  /// Returns a new [Vector3] with the converted scale.
  static Vector3 urdfToUnityScale(Vector3 v) {
    return Vector3(v.y, v.z, v.x);
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
  static Vector3 urdfToUnityRot(Vector3 v) {
    // Negate X and Z because we're going from Right to Left handed rotations. Y is handled because the axis itself is flipped
    v.x *= -1;
    v.z *= -1;

    // swap the angle values
    v = Vector3(v.y, v.z, v.x);

    return v;
  }
}
