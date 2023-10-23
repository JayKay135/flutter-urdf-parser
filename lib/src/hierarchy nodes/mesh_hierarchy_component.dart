import 'hierarchy_component.dart';

import 'package:three_dart/three_dart.dart';

/// A component of a mesh hierarchy node in a URDF file.
class MeshHierarchyComponent extends HierarchyComponent {
  MeshHierarchyComponent(this.mesh, super.name);

  Object3D mesh;
}
