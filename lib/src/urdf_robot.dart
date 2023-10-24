import 'extensions.dart';
import 'hierarchy nodes/group_hierarchy_component.dart';
import 'hierarchy nodes/hierarchy_component.dart';
import 'hierarchy nodes/hierarchy_node.dart';

import 'package:three_dart/three_dart.dart';

import 'hierarchy nodes/mesh_hierarchy_component.dart';

/// Object describing a URDF joint with joint transform, associated geometry, etc
class URDFJoint extends HierarchyNode {
  URDFJoint({
    required Vector3 localPosition,
    required Quaternion localRotation,
    required Vector3 scale,
    required this.originalPosition,
    required this.originalRotation,
    this.parentLink,
    this.childLink,
    this.type = "fixed",
    String name = "joint",
  }) : super(
          localPosition: localPosition,
          localRotation: localRotation,
          scale: scale,
          name: name,
        );

  static URDFJoint identity(String name) {
    return URDFJoint(
      localPosition: Vector3()..zero(),
      localRotation: Quaternion()..identity(),
      scale: Vector3()..one(),
      originalPosition: Vector3()..zero(),
      originalRotation: Quaternion()..identity(),
      name: name,
    );
  }

  URDFLink? parentLink;
  URDFLink? childLink;

  String type;
  Vector3 axis = Vector3(0, 0, 0);
  double lower = 0;
  double upper = 0;

  // for mimic joints
  double multiplier = 1;
  double offset = 0;

  /// List of joints that mimic this joint instance
  List<URDFJoint> mimicJoints = [];

  Vector3 originalPosition;
  Quaternion originalRotation;

  List<HierarchyNode> get geometry =>
      childLink != null ? childLink!.geometry : [];

  double _angle = 0;
  double get angle => _angle;
  void set(double angle) => setAngle(angle);

  double setAngle(double val) {
    switch (type) {
      // This is not really a joint because it cannot move.
      // All degrees of freedom are locked.
      // This type of joint does not require the <axis>, <calibration>, <dynamics>, <limits> or <safety_controller>
      case "fixed":
        {
          break;
        }

      // A continuous hinge joint that rotates around the axis and has no upper and lower limits.
      case "continuous":
      // A hinge joint that rotates along the axis and has a limited range specified by the upper and lower limits.
      case "revolute":
        {
          if (type == "revolute") {
            val = val.clamp(lower, upper);
          }

          // apply multiplier and offset
          val = multiplier * val + offset;

          // Negate to accommodate Right -> Left handed coordinate system
          // NOTE: It is assumed that the axis vector is normalized

          Vector3 mult = originalRotation.clone().multiplied(axis);
          Quaternion q = Quaternion().setFromAxisAngle(mult, angle * -1);
          localRotation = q * originalRotation;
          _angle = val;

          GroupHierarchyComponent? group =
              getComponent('group') as GroupHierarchyComponent?;
          if (group != null) {
            group.group.setRotationFromQuaternion(localRotation);
          }

          break;
        }

      // A sliding joint that slides along the axis, and has a limited range specified by the upper and lower limits.
      case "prismatic":
        {
          val = val.clamp(lower, upper);

          // apply multiplier and offset
          val = multiplier * val + offset;

          Vector3 pos = originalPosition + axis * val;

          GroupHierarchyComponent? group =
              getComponent('group') as GroupHierarchyComponent?;
          if (group != null) {
            group.group.position = pos;
          }

          break;
        }

      // This joint allows motion for all 6 degrees of freedom.
      case "floating":
      // This joint allows motion in a plane perpendicular to the axis.
      case "planar":
        {
          throw Exception("URDFLoader: '$type' joint not yet supported");
        }
    }

    // set the angle too for all mimicing joints
    for (URDFJoint mimicJoint in mimicJoints) {
      mimicJoint.setAngle(val);
    }

    return _angle;
  }
}

/// Object discribing a URDF Link
class URDFLink extends HierarchyNode {
  URDFLink({
    required Vector3 localPosition,
    required Quaternion localRotation,
    required Vector3 scale,
    String name = "link",
  }) : super(
          localPosition: localPosition,
          localRotation: localRotation,
          scale: scale,
          name: name,
        );

  static URDFLink identity(String name) {
    Vector3 localPosition = Vector3()..zero();
    Quaternion localRotation = Quaternion()..identity();
    Vector3 scale = Vector3()..one();

    return URDFLink(
      localPosition: localPosition,
      localRotation: localRotation,
      scale: scale,
      name: name,
    );
  }

  List<HierarchyNode> geometry = [];
}

/// Component representing the URDF Robot
class URDFRobot extends HierarchyComponent {
  URDFRobot({required String name, required this.transform}) : super(name);

  HierarchyNode transform;

  /// Dictionary containing all the URDF joints
  Map<String, URDFJoint> joints = {};
  Map<String, URDFLink> links = {};

  /// Amount of adjustable joints
  int get availableJointCount =>
      joints.entries.where((entry) => entry.value.type != "fixed").length;

  /// Returns the mesh of the robot as an Object3D.
  Object3D getObject() {
    Group group = Group();

    _addHierarchyNode(transform, group);

    return group;
  }

  /// Adds a [HierarchyNode] to the scene graph with an optional [parent].
  void _addHierarchyNode(HierarchyNode node, Object3D? parent) {
    MeshHierarchyComponent? mesh =
        node.getComponent('mesh') as MeshHierarchyComponent?;
    Group? group;

    if (mesh != null) {
      // get the global position and rotation
      mesh.mesh.position = node.localPosition;
      mesh.mesh.setRotationFromQuaternion(node.localRotation);
      mesh.mesh.scale = node.scale;

      if (parent != null) {
        parent.add(mesh.mesh);
      }
    } else {
      // No mesh component found
      // => create a group
      group = Group();
      group.position = node.localPosition;
      group.setRotationFromQuaternion(node.localRotation);
      group.scale = node.scale;

      // add the group as component to the HierarchyNode
      node.addComponent(GroupHierarchyComponent(group, "group"));

      if (parent != null) {
        parent.add(group);
      }
    }

    // continue with children recursively
    for (HierarchyNode child in node.children) {
      _addHierarchyNode(
        child,
        mesh != null ? mesh.mesh : group,
      );
    }
  }

  /// Prints all available and adjustable joints to the console
  void printAvailableJoints() {
    for (MapEntry<String, URDFJoint> entry in joints.entries) {
      if (entry.value.type != "fixed") {
        print(entry.key);
      }
    }
  }

  /// Adds a joint via URDFJoint
  bool addJoint(URDFJoint joint) {
    if (!joints.containsKey(joint.name)) {
      joints[joint.name] = joint;
      return true;
    }
    return false;
  }

  /// Adds the URDFLink to the list
  bool addLink(URDFLink link) {
    if (!links.containsKey(link.name)) {
      links[link.name] = link;
      return true;
    }
    return false;
  }

  /// Set the angle of a joint
  void setAngle(String name, double angle) {
    URDFJoint? joint = joints[name];
    joint!.setAngle(angle);
  }

  /// Sets the angle if it can, returns false otherwise
  bool trySetAngle(String name, double angle) {
    if (!joints.containsKey(name)) {
      return false;
    }

    setAngle(name, angle);
    return true;
  }

  /// Get and set the joint angles as dictionaries
  Map<String, double> getAnglesAsDictionary() {
    return joints.map((key, value) => MapEntry(key, value.angle));
  }

  /// Sets the joints via a dictionary
  void setAnglesFromDictionary(Map<String, double> dict) {
    for (MapEntry<String, double> kv in dict.entries) {
      if (joints.containsKey(kv.key)) {
        joints[kv.key]!.setAngle(kv.value);
      }
    }
  }

  /// Validates the structure of the links and joints to verify that everything is consistant.
  /// Does not validate the transform hierarchy or verify that there are no cycles.
  bool isConsistent() {
    (bool success, String error) res = _iConsistent();
    if (!res.$1) {
      throw Exception("URDFLoader: Inconsistent URDF Structure\n${res.$2}");
    }
    return res.$1;
  }

  /// Validates the consistency of the URDF structure
  (bool success, String error) _iConsistent() {
    // verify that
    // * every joint's name matches its key
    // * every joint specifies a joint type
    // * both parent and child match
    for (MapEntry<String, URDFJoint> kv in joints.entries) {
      URDFJoint j = kv.value;

      if (j.name != kv.key) {
        return (false, "Joint ${j.name}'s name does not match key ${kv.key}");
      }

      if (j.type == "") {
        return (false, "Joint ${j.name}'s type is not set");
      }

      if (j.parentLink == null) {
        return (false, "Joint ${j.name} does not have a parent link");
      }

      if (!j.parentLink!.children.contains(j)) {
        return (
          false,
          "Joint ${j.name}'s parent link ${j.parentLink!.name} does not contain it as a child"
        );
      }

      if (j.childLink == null) {
        return (false, "Joint ${j.name} does not have a child link");
      }

      if (j.childLink!.parent != j) {
        return (
          false,
          "Joint ${j.name}'s child link ${j.childLink!.name} does not have it as a parent"
        );
      }
    }

    // verify that
    // * every link's name matches it key
    // * every parent and child matches
    for (MapEntry<String, URDFLink> kv in links.entries) {
      URDFLink l = kv.value;

      if (l.name != kv.key) {
        return (false, "Link ${l.name}'s name does not match key ${kv.key}");
      }

      if (l.parent != null && (l.parent! as URDFJoint).childLink != l) {
        return (
          false,
          "Link ${l.name}'s parent joint ${l.parent!.name} does not have it as a child"
        );
      }

      // for (URDFJoint j in l.children as List<URDFJoint>) {
      // FIXME
      // for (URDFJoint j in l.children.map((e) => e as URDFJoint)) {
      //   if (j.parentLink != l) {
      //     return (false, "Link ${l.name}'s child joint ${j.name} does not have it as a parent");
      //   }
      // }
    }

    return (true, "");
  }
}
