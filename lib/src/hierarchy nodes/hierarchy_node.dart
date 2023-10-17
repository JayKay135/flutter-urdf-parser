import '../extensions.dart';
import 'hierarchy_component.dart';

import 'package:three_dart/three_dart.dart';

/// A node in the URDF hierarchy tree.
class HierarchyNode {
  String name;

  Vector3 localPosition;
  Quaternion localRotation;
  Vector3 scale;

  HierarchyNode? parent;
  List<HierarchyNode> children = [];

  Map<String, HierarchyComponent> _components = {};

  HierarchyComponent addComponent(HierarchyComponent component) => _components[component.name] = component;
  HierarchyComponent? getComponent(String name) => _components[name];

  HierarchyNode({
    required this.localPosition,
    required this.localRotation,
    required this.scale,
    this.parent,
    this.name = "",
  });

  /// Returns a new [HierarchyNode] instance with the given [name] and identity transform.
  static HierarchyNode identity(String name) {
    return HierarchyNode(
      localPosition: Vector3()..zero(),
      localRotation: Quaternion()..identity(),
      scale: Vector3()..one(),
      name: name,
    );
  }

  /// Returns the HierarchyNodes global position based on all parents local positions + rotations
  Vector3 get globalPosition {
    if (parent == null) {
      return localPosition * scale;
    } else {
      return parent!.globalPosition + parent!.globalRotation.rotate(localPosition * scale);
    }
  }

  set globalPosition(Vector3 position) {
    if (parent == null) {
      localPosition = position;
    } else {
      localPosition = parent!.globalRotation.inverse().rotate(position - parent!.globalPosition);
    }
  }

  /// Returns the HierarchyNodes global rotation based on all parents local positions + rotations
  Quaternion get globalRotation {
    if (parent == null) {
      return localRotation;
    } else {
      return parent!.globalRotation * localRotation;
    }
  }

  set globalRotation(Quaternion rotation) {
    if (parent == null) {
      localRotation = rotation;
    } else {
      localRotation = parent!.globalRotation.inverse() * rotation;
    }
  }

  /// Adds the given [child] node as a child of this node.
  void addChild(HierarchyNode child) {
    child.parent = this;

    // prevent duplicates
    if (!children.contains(child)) {
      children.add(child);
    }
  }

  /// Removes the given [child] from the list of children of this node.
  void removeChild(HierarchyNode child) {
    child.parent = null;
    children.remove(child);
  }

  /// Prints the hierarchy of the node.
  ///
  /// The [spacing] parameter specifies the number of spaces to use for indentation.
  /// By default, the spacing is set to 0.
  ///
  /// Example usage:
  /// ```dart
  /// HierarchyNode node = HierarchyNode();
  /// node.printHierarchy();
  /// ```
  void printHierarchy({int spacing = 0}) {
    String spaces = " " * spacing * 2;

    Euler rot = Euler()..setFromQuaternion(localRotation);
    rot.x *= MathUtils.rad2deg;
    rot.y *= MathUtils.rad2deg;
    rot.z *= MathUtils.rad2deg;

    print(
        "$spaces > $name pos:(${localPosition.x}, ${localPosition.y}, ${localPosition.z}), rot:(${rot.x.toStringAsFixed(4)}, ${rot.y.toStringAsFixed(4)}, ${rot.z.toStringAsFixed(4)}), scale:(${scale.x}, ${scale.y}, ${scale.z})");

    // continue recursively for all children
    for (HierarchyNode child in children) {
      child.printHierarchy(spacing: spacing + 1);
    }
  }
}
