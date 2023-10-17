import 'dart:math';

import 'extensions.dart';
import 'xml_functions.dart';

import 'package:collection/collection.dart';
import 'package:xml/xml.dart';
import 'package:flutter_gl/flutter_gl.dart';
import 'package:three_dart/three_dart.dart';

/// **********************************************************************************************************************************************************************
/// in order to get materials working you will need to duplicate verts until they match the number of normals/uvs, since collada allows multiple normals and uvs per vert
/// **********************************************************************************************************************************************************************

/// Represents a geometry element in a Collada file.
///
/// This class is used to parse and store information about a geometry element in a Collada file.
/// It is used by the ColladaLoader class to load Collada files.
class DaeGeometry {
  DaeInput? vertex;
  DaeInput? normal;
  DaeInput? uv;

  DaeGeometry({this.vertex, this.normal, this.uv});
}

/// A class representing an input element in a COLLADA document.
class DaeInput {
  String semantic;
  String source;
  int offset;

  List<int> indices;
  List<int>? vcounts;

  DaeInput(this.semantic, this.source, this.offset, this.indices, {this.vcounts});
}

/// A class representing a simplified version of the Collada format.
class ColladaLite {
  List<Mesh>? meshes;
  List<String>? textureNames;

  /// Removes all xml comments and line breaks from the given String.
  String _removeCommentsAndLineBreaks(String val) {
    return val.replaceAll(RegExp(r'\s*<!--.*?-->\s*|\s*\n\s*'), ' ');
  }

  /// Creates a list of triangles from a list of vertices.
  ///
  /// The resulting list of triangles forms the same mesh as the input list of vertices.
  ///
  /// The input list of vertices must contain at least three items.
  ///
  /// Example usage:
  /// ```dart
  /// List<Vector3> vertices = [
  ///   Vector3(0, 0, 0),
  ///   Vector3(0, 1, 0),
  ///   Vector3(1, 0, 0),
  ///   Vector3(1, 1, 0),
  /// ];
  ///
  /// List<Vector3> triangles = createTriangles(vertices);
  /// ```
  List<Vector3> createTriangles(List<Vector3> vertices) {
    List<Vector3> triangles = [];

    // Create triangles from the vertices
    for (int i = 2; i < vertices.length; i++) {
      triangles.add(vertices[0]);
      triangles.add(vertices[i - 1]);
      triangles.add(vertices[i]);
    }

    return triangles;
  }

  ColladaLite(String content) {
    XmlDocument document = XmlDocument.parse(content);

    XmlElement? colladaNode = document.childElements.firstWhereOrNull((element) => element.localName == "COLLADA");

    if (colladaNode == null) {
      throw Exception("COLLADA Node missing");
    }

    double scalingFactor = 0.001;

    // XmlElement? asset = XMLFunctions.getXmlElementChildByName(colladaNode, "asset");
    // if (asset != null) {
    //   XmlElement? unit = XMLFunctions.getXmlElementChildByName(asset, "unit");

    //   if (unit != null) {
    //     scalingFactor = 1 / double.parse(unit.getAttribute("meter")!);
    //   }
    // }

    for (XmlElement childNode in colladaNode.childElements) {
      if (childNode.localName == "library_images") {
        for (XmlElement imageNode in childNode.childElements) {
          if (imageNode.localName == "image" && imageNode.childElements.isNotEmpty) {
            if (imageNode.firstElementChild!.localName == "init_from") {
              textureNames ??= [];
              textureNames!.add(imageNode.firstElementChild!.innerText);
            }
          }
        }
      } else if (childNode.localName == "library_geometries") {
        if (childNode.childElements.isNotEmpty) {
          List<XmlElement> geometries = XMLFunctions.getXmlElementChildrenByName(childNode, "geometry");
          // Iterate over all geometries
          for (XmlElement geometry in geometries) {
            // Iterate over all meshes
            for (XmlElement mesh in geometry.childElements) {
              if (mesh.localName != "mesh") {
                continue;
              }

              Map<String, List<double>> sources = {};

              // Geometry nodes can have multiple vertices nodes
              Map<String, String> vertsSources = {};

              List<List<DaeInput>> geometries = [];

              for (XmlElement node in mesh.childElements) {
                if (node.localName == "source") {
                  var fa = XMLFunctions.getXmlElementChildByName(node, "float_array");
                  if (fa != null) {
                    sources[node.getAttribute("id")!] =
                        _removeCommentsAndLineBreaks(fa.innerText).split(' ').where((s) => s.isNotEmpty).map((s) => double.parse(s)).toList();
                  }
                } else if (node.localName == "vertices") {
                  var vs = XMLFunctions.getXmlElementChildByName(node, "input");
                  if (vs != null) {
                    vertsSources[node.getAttribute("id")!] = vs.getAttribute("source")!.replaceAll("#", "");
                  }
                } else if (node.localName == "triangles") {
                  List<int> pList = _removeCommentsAndLineBreaks(XMLFunctions.getXmlElementChildByName(node, "p")!.innerText)
                      .split(' ')
                      .where((s) => s.isNotEmpty)
                      .map((s) => int.parse(s))
                      .toList();

                  geometries.add(XMLFunctions.getXmlElementChildrenByName(node, "input")
                      .map((XmlElement inputNode) => DaeInput(
                            inputNode.getAttribute("semantic")!,
                            inputNode.getAttribute("source")!,
                            int.parse(inputNode.getAttribute("offset")!),
                            pList,
                          ))
                      .toList());
                } else if (node.localName == "polylist") {
                  List<int> pList = _removeCommentsAndLineBreaks(XMLFunctions.getXmlElementChildByName(node, "p")!.innerText)
                      .split(' ')
                      .where((s) => s.isNotEmpty)
                      .map((s) => int.parse(s))
                      .toList();

                  List<int> vcounts = (XMLFunctions.getXmlElementChildByName(node, "vcount")!.innerText)
                      .split(' ')
                      .where((s) => s.isNotEmpty)
                      .map((s) => int.parse(s))
                      .toList();

                  geometries.add(XMLFunctions.getXmlElementChildrenByName(node, "input")
                      .map((XmlElement inputNode) => DaeInput(
                            inputNode.getAttribute("semantic")!,
                            inputNode.getAttribute("source")!,
                            int.parse(inputNode.getAttribute("offset")!),
                            pList,
                            vcounts: vcounts,
                          ))
                      .toList());
                }
              }

              for (List<DaeInput> inputs in geometries) {
                List<Vector3>? triangles;
                List<Vector3>? normals;
                List<Vector2>? uvs;

                for (DaeInput input in inputs) {
                  String source = input.source.replaceAll("#", "");

                  if (sources.containsKey(source)) {
                    if (input.semantic == "TEXCOORD") {
                      List<Vector2> temp = [];
                      for (int i = input.offset; i < input.indices.length; i += inputs.length) {
                        int index = input.indices[i] * 2;
                        temp.add(Vector2(sources[source]![index], sources[source]![index + 1]));
                      }
                      uvs ??= [];
                      uvs.addAll(temp);
                    } else if (input.semantic == "NORMAL") {
                      List<Vector3> temp = [];

                      if (input.vcounts == null) {
                        // triangles
                        for (int i = input.offset; i < input.indices.length; i += inputs.length) {
                          int index = input.indices[i] * 3;
                          Vector3 vec = Vector3(sources[source]![index], sources[source]![index + 1], sources[source]![index + 2]);
                          vec *= scalingFactor;
                          temp.add(vec);
                          // temp.add(XMLFunctions.urdfToUnityPos(vec));
                        }
                      } else {
                        // polygons => format polygons to triangles
                        int vIndex = 0;
                        List<Vector3> polygon = [];
                        int index = input.indices[inputs.length];

                        for (int i = input.offset; i < input.indices.length; i += inputs.length) {
                          index = input.indices[i] * 3;

                          Vector3 vec = Vector3(
                            sources[source]![index],
                            sources[source]![index + 1],
                            sources[source]![index + 2],
                          );
                          vec *= scalingFactor;
                          polygon.add(vec);

                          if (polygon.length == input.vcounts![vIndex]) {
                            // format polygon list to list of triangles
                            List<Vector3> extractedTriangles = createTriangles(polygon);
                            temp.addAll(extractedTriangles);

                            polygon = [];
                            vIndex++;
                          }
                        }

                        // Check if there are any remaining vertices in the polygon
                        if (polygon.isNotEmpty) {
                          List<Vector3> extractedTriangles = createTriangles(polygon);
                          temp.addAll(extractedTriangles);
                        }
                      }

                      normals ??= [];
                      normals.addAll(temp);
                    }
                  } else if (input.semantic == "VERTEX") {
                    List<Vector3> temp = [];

                    String vertsSource = vertsSources[source]!.replaceAll("#", "");

                    if (input.vcounts == null) {
                      // triangles
                      for (int i = input.offset; i < input.indices.length; i += inputs.length) {
                        int index = input.indices[i] * 3;
                        Vector3 vec = Vector3(sources[vertsSource]![index], sources[vertsSource]![index + 1], sources[vertsSource]![index + 2]);
                        vec *= scalingFactor;
                        temp.add(vec);
                        // temp.add(XMLFunctions.urdfToUnityPos(vec));
                      }
                    } else {
                      // polygons => format polygons to triangles
                      int vIndex = 0;
                      List<Vector3> polygon = [];
                      int index = input.indices[inputs.length];

                      for (int i = input.offset; i < input.indices.length; i += inputs.length) {
                        index = input.indices[i] * 3;

                        Vector3 vec = Vector3(
                          sources[vertsSource]![index],
                          sources[vertsSource]![index + 1],
                          sources[vertsSource]![index + 2],
                        );
                        vec *= scalingFactor;
                        polygon.add(vec);

                        if (polygon.length == input.vcounts![vIndex]) {
                          // format polygon list to list of triangles
                          List<Vector3> extractedTriangles = createTriangles(polygon);
                          temp.addAll(extractedTriangles);

                          polygon = [];
                          vIndex++;
                        }
                      }

                      // Check if there are any remaining vertices in the polygon
                      if (polygon.isNotEmpty) {
                        List<Vector3> extractedTriangles = createTriangles(polygon);
                        temp.addAll(extractedTriangles);
                      }
                    }

                    triangles ??= [];
                    triangles.addAll(temp);
                  }
                }

                BufferGeometry geometry = BufferGeometry();

                if (triangles != null) {
                  geometry.setAttribute('position', Float32BufferAttribute(Float32Array.fromList(triangles.expand((e) => [e.x, e.y, e.z]).toList()), 3));
                }

                if (normals != null) {
                  geometry.setAttribute('normal', Float32BufferAttribute(Float32Array.fromList(normals.expand((e) => [e.x, e.y, e.z]).toList()), 3));
                } else {
                  // for smooth shading
                  geometry.computeVertexNormals();

                  // for flat shading
                  // geometry.computeFaceNormals();
                }

                if (uvs != null) {
                  geometry.setAttribute('uv', Float32BufferAttribute(Float32Array.fromList(uvs.expand((e) => [e.x, e.y]).toList()), 2));
                }

                // NOTE: tbh I'm not really use why this is necessary
                geometry.rotateY(-pi / 2);

                Material material = MeshPhongMaterial({"color": 0xff0000, "flatShading": false, "side": DoubleSide});
                Mesh temp = Mesh(geometry, material);

                meshes ??= [];
                meshes!.add(temp);
              }
            }
          }
        }
      }
    }
  }
}
