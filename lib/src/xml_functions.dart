import 'package:xml/xml.dart';
import 'package:collection/collection.dart'; // for firstWhereOrNull implementation

class XMLFunctions {
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
}
