import 'hierarchy_component.dart';

import 'package:three_dart/three_dart.dart';

/// A component representing a group in the URDF hierarchy.
class GroupHierarchyComponent extends HierarchyComponent {
  GroupHierarchyComponent(this.group, super.name);

  Group group;
}
