import 'dart:math';
import 'package:flutter_gl/flutter_gl.dart';
import 'package:three_dart/three_dart.dart';
import 'package:xml/xml.dart';
import 'package:collection/collection.dart';

import 'extensions.dart';
import 'xml_functions.dart';

/// **********************************************************************************************************************************************************************
/// in order to get materials working you will need to duplicate verts until they match the number of normals/uvs, since collada allows multiple normals and uvs per vert
/// **********************************************************************************************************************************************************************

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

class MeshData {
  List<DaeInput> inputs;
  String? materialName;
  bool line;

  MeshData(this.inputs, this.materialName, {this.line = false});
}

/// A class representing a simplified version of the Collada format.
class ColladaLite {
  List<Object3D>? meshes;
  List<String>? textureNames;

  /// Removes all xml comments and line breaks from the given String.
  String removeCommentsAndLineBreaks(String val) {
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

  /// Recursively traverses the visual scene graph starting from the given [node],
  /// applying the [transforms] to each node, and passing the [parentTransform] down the hierarchy.
  ///
  /// If [parentTransform] is null, the identity matrix is used.
  void visualSceneNodeRecursion(XmlElement node, Map<String, Matrix4> transforms, Map<String, Map<String, String>> materialReferences,
      {Matrix4? parentTransform}) {
    Matrix4 transform = parentTransform ?? Matrix4();

    for (XmlElement childNode in node.childElements) {
      switch (childNode.localName) {
        case "matrix":
          Matrix4 matrix = Matrix4()
              .fromArray(removeCommentsAndLineBreaks(childNode.innerText).split(' ').where((s) => s.isNotEmpty).map((s) => double.parse(s)).toList())
              .transpose();
          transform.multiply(matrix);

        case "rotate":
          List<double> values = removeCommentsAndLineBreaks(childNode.innerText).split(' ').where((s) => s.isNotEmpty).map((s) => double.parse(s)).toList();
          Vector3 axis = Vector3().fromArray(values.sublist(0, 3));
          double angle = values[3] * MathUtils.deg2rad;
          Matrix4 matrix = Matrix4().makeRotationAxis(axis, angle);
          transform.multiply(matrix);

        case "scale":
          Vector3 scale =
              Vector3().fromArray(removeCommentsAndLineBreaks(childNode.innerText).split(' ').where((s) => s.isNotEmpty).map((s) => double.parse(s)).toList());
          Matrix4 matrix = Matrix4().scale(scale);
          transform.multiply(matrix);

        case "transform":
          Vector3 position =
              Vector3().fromArray(removeCommentsAndLineBreaks(childNode.innerText).split(' ').where((s) => s.isNotEmpty).map((s) => double.parse(s)).toList());
          Matrix4 matrix = Matrix4().setPositionFromVector3(position);
          transform.multiply(matrix);

        case "skew":
          // rotation around axis + translation
          List<double> values = removeCommentsAndLineBreaks(childNode.innerText).split(' ').where((s) => s.isNotEmpty).map((s) => double.parse(s)).toList();
          double angle = values[0] * MathUtils.deg2rad;
          Vector3 axis = Vector3().fromArray(values.sublist(1, 4));
          Vector3 position = Vector3().fromArray(values.sublist(4, 7));

          Matrix4 matrix = Matrix4().makeRotationAxis(axis, angle).setPositionFromVector3(position);
          transform.multiply(matrix);

        case "lookat":
          // TODO: Implement
          print("lookat transformation is not yet implemented");
      }
    }

    // only add current node to transforms map if it has instance geometries
    for (XmlElement instanceGeometry in XMLFunctions.getXmlElementChildrenByName(node, "instance_geometry")) {
      String url = instanceGeometry.getAttribute("url")!.replaceAll('#', '');
      transforms[url] = transform;

      // load potential material references
      XmlElement? bindMaterialNode = XMLFunctions.getXmlElementChildByName(instanceGeometry, "bind_material");
      if (bindMaterialNode != null) {
        XmlElement techniqueCommonNode = XMLFunctions.getXmlElementChildByName(bindMaterialNode, "technique_common")!;

        for (XmlElement instanceMaterialNode in techniqueCommonNode.childElements) {
          String symbol = instanceMaterialNode.getAttribute("symbol")!;
          String target = instanceMaterialNode.getAttribute("target")!.replaceAll("#", "");

          materialReferences[url] ??= {};
          materialReferences[url]![symbol] = target;
        }
      }
    }

    // continue recursively
    for (XmlElement childNode in XMLFunctions.getXmlElementChildrenByName(node, "node")) {
      visualSceneNodeRecursion(childNode, transforms, materialReferences, parentTransform: transform.clone());
    }
  }

  ColladaLite(String content) {
    XmlDocument document = XmlDocument.parse(content);

    XmlElement? colladaNode = document.childElements.firstWhereOrNull((element) => element.localName == "COLLADA");

    if (colladaNode == null) {
      throw Exception("COLLADA Node missing");
    }

    // handle scaling
    double scalingFactor = 1;
    //0.001;
    // XmlElement? asset = XMLFunctions.getXmlElementChildByName(colladaNode, "asset");
    // if (asset != null) {
    //   XmlElement? unit = XMLFunctions.getXmlElementChildByName(asset, "unit");

    //   if (unit != null) {
    //     scalingFactor = 1 / double.parse(unit.getAttribute("meter")!);
    //   }
    // }

    // --- handle transforms ---
    Map<String, Matrix4> transforms = {};

    /// key1: mesh name
    /// key2: material symbol name
    /// value: material target name
    Map<String, Map<String, String>> materialReferences = {};

    XmlElement? sceneNode = XMLFunctions.getXmlElementChildByName(colladaNode, "scene");
    if (sceneNode != null) {
      // NOTE: According to the collada specifications, a scene node most contain exactly one instance_viusal_scene
      // Using additional check to be on the save side and prevent parsing errors
      XmlElement? instanceVisualSceneNode = XMLFunctions.getXmlElementChildByName(sceneNode, "instance_visual_scene");
      if (instanceVisualSceneNode != null) {
        String sceneName = instanceVisualSceneNode.getAttribute("url")!.replaceAll('#', '');

        // load scene data
        XmlElement libraryVisualScenesNode = XMLFunctions.getXmlElementChildByName(colladaNode, "library_visual_scenes")!;
        XmlElement visualSceneNode =
            libraryVisualScenesNode.childElements.firstWhere((element) => element.localName == "visual_scene" && element.getAttribute("id")! == sceneName);

        // start recursion to get transform information
        visualSceneNodeRecursion(visualSceneNode, transforms, materialReferences);
      }
    }

    // --- handle materials ---
    Map<String, Material> materials = {};

    XmlElement? libraryMaterials = XMLFunctions.getXmlElementChildByName(colladaNode, "library_materials");
    if (libraryMaterials != null) {
      XmlElement libraryEffects = XMLFunctions.getXmlElementChildByName(colladaNode, "library_effects")!;

      for (XmlElement materialNode in libraryMaterials.childElements) {
        String materialId = materialNode.getAttribute("id")!;

        // get the materials corresponding effects data
        String effectUrl = XMLFunctions.getXmlElementChildByName(materialNode, "instance_effect")!.getAttribute("url")!.replaceAll("#", "");
        XmlElement effectNode = libraryEffects.childElements.firstWhere((element) => element.localName == "effect" && element.getAttribute("id")! == effectUrl);

        // parse the effect information to a three_dart material
        // NOTE: For now only the profile_COMMON effect is supported

        // pick the first found profile_COMMON element
        XmlElement? profileCommonNode = XMLFunctions.getXmlElementChildByName(effectNode, "profile_COMMON");

        if (profileCommonNode != null) {
          // load parameters
          Map<String, dynamic> parameters = {};

          for (XmlElement newParamNode in XMLFunctions.getXmlElementChildrenByName(profileCommonNode, "newparam")) {
            String paramName = newParamNode.getAttribute("sid")!;
            var data; // double or List<double>

            // load the param value
            for (XmlElement dataTypeNode in newParamNode.childElements) {
              switch (dataTypeNode.localName) {
                case "float":
                  data = double.parse(removeCommentsAndLineBreaks(dataTypeNode.innerText));
                  break;

                case "float2":
                  data = removeCommentsAndLineBreaks(dataTypeNode.innerText).split(' ').where((s) => s.isNotEmpty).map((s) => double.parse(s));
                  break;

                case "float3":
                  data = removeCommentsAndLineBreaks(dataTypeNode.innerText).split(' ').where((s) => s.isNotEmpty).map((s) => double.parse(s));
                  break;

                case "float4":
                  data = removeCommentsAndLineBreaks(dataTypeNode.innerText).split(' ').where((s) => s.isNotEmpty).map((s) => double.parse(s));
                  break;

                case "surface":
                  break;

                case "samples2D":
                  break;
              }
            }

            // add parameter to map
            parameters[paramName] = data;
          }

          XmlElement techniqueNode = XMLFunctions.getXmlElementChildByName(profileCommonNode, "technique")!;

          for (XmlElement shader in techniqueNode.childElements) {
            if (shader.localName == "lambert") {
              // parse lambert material data
              Material material = MeshLambertMaterial();

              for (XmlElement lambertData in shader.childElements) {
                XmlElement dataNode = lambertData.childElements.first;
                var data; // double or List<double>

                switch (dataNode.localName) {
                  case "param":
                    // parameter
                    String ref = dataNode.getAttribute("ref")!;
                    data = parameters[ref];
                    break;

                  case "color":
                    data = removeCommentsAndLineBreaks(dataNode.innerText).split(' ').where((s) => s.isNotEmpty).map((s) => double.parse(s)).toList();
                    break;

                  case "float":
                    data = double.parse(removeCommentsAndLineBreaks(dataNode.innerText));
                    break;
                }

                // apply the parsed data to the material
                switch (lambertData.localName) {
                  case "emission":
                    material.emissive = Color(data[0], data[1], data[2]);
                    break;

                  case "diffuse":
                    material.color = Color(data[0], data[1], data[2]);
                    break;

                  case "reflectivity":
                    material.reflectivity = data;
                    // material.specularIntensity = data;
                    // material.specularColor = Color(0xffffff);
                    // material.specular = Color(0xffffff);
                    break;

                  case "index_of_refraction":
                    material.ior = data;

                  // case "transparency":
                  //   material.transparent = true;
                  //   material.opacity = data;
                  //   break;
                }
              }

              materials[materialId] = material;
              break;
            } else if (shader.localName == "phong") {
              // parse phong material data
              Material material = MeshPhongMaterial();

              for (XmlElement phongData in shader.childElements) {
                XmlElement dataNode = phongData.childElements.first;
                var data; // double or List<double>

                switch (dataNode.localName) {
                  case "param":
                    // parameter
                    String ref = dataNode.getAttribute("ref")!;
                    data = parameters[ref];
                    break;

                  case "color":
                    data = removeCommentsAndLineBreaks(dataNode.innerText).split(' ').where((s) => s.isNotEmpty).map((s) => double.parse(s)).toList();
                    break;

                  case "float":
                    data = double.parse(removeCommentsAndLineBreaks(dataNode.innerText));
                    break;
                }

                // apply the parsed data to the material
                switch (phongData.localName) {
                  case "emission":
                    material.emissive = Color(data[0], data[1], data[2]);
                    break;

                  case "diffuse":
                    material.color = Color(data[0], data[1], data[2]);
                    break;

                  case "reflectivity":
                    material.reflectivity = data;
                    // material.specularIntensity = data;
                    // material.specularColor = Color(0xffffff);
                    // material.specular = Color(0xffffff);
                    break;

                  case "index_of_refraction":
                    material.ior = data;

                  case "transparent":
                    // Color color = Color(data[0], data[1], data[2]);
                    break;

                  // case "transparency":
                  //   material.transparent = true;
                  //   material.opacity = data;
                  //   break;

                  case "specular":
                    material.specularColor = Color(data[0], data[1], data[2]);
                    break;

                  case "shininess":
                    material.shininess = data;
                    break;
                }
              }

              materials[materialId] = material;
              break;
            }
          }
        }
      }
    }

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
            String geometryId = geometry.getAttribute('id')!;

            // Iterate over all meshes
            for (XmlElement mesh in geometry.childElements) {
              if (mesh.localName != "mesh") {
                continue;
              }

              Map<String, List<double>> sources = {};

              // Geometry nodes can have multiple vertices nodes
              Map<String, String> vertsSources = {};

              // List<int>? indices;
              // List<int>? vcounts;

              // List<DaeInput> inputs = [];
              // List<DaeGeometry> geometries = [];
              List<MeshData> geometries = [];

              for (XmlElement node in mesh.childElements) {
                if (node.localName == "source") {
                  var fa = XMLFunctions.getXmlElementChildByName(node, "float_array");
                  if (fa != null) {
                    sources[node.getAttribute("id")!] =
                        removeCommentsAndLineBreaks(fa.innerText).split(' ').where((s) => s.isNotEmpty).map((s) => double.parse(s)).toList();
                  }
                } else if (node.localName == "vertices") {
                  var vs = XMLFunctions.getXmlElementChildByName(node, "input");
                  if (vs != null) {
                    vertsSources[node.getAttribute("id")!] = vs.getAttribute("source")!.replaceAll("#", "");
                  }
                } else if (node.localName == "triangles") {
                  List<int> pList = removeCommentsAndLineBreaks(XMLFunctions.getXmlElementChildByName(node, "p")!.innerText)
                      .split(' ')
                      .where((s) => s.isNotEmpty)
                      .map((s) => int.parse(s))
                      .toList();

                  // inputs.addAll(XMLFunctions.getXmlElementChildrenByName(node, "input")
                  //     .map((XmlElement inputNode) => DaeInput(
                  //           inputNode.getAttribute("semantic")!,
                  //           inputNode.getAttribute("source")!,
                  //           int.parse(inputNode.getAttribute("offset")!),
                  //           pList,
                  //         ))
                  //     .toList());

                  String? materialName = node.getAttribute("material");

                  geometries.add(
                    MeshData(
                      XMLFunctions.getXmlElementChildrenByName(node, "input")
                          .map((XmlElement inputNode) => DaeInput(
                                inputNode.getAttribute("semantic")!,
                                inputNode.getAttribute("source")!,
                                int.parse(inputNode.getAttribute("offset")!),
                                pList,
                              ))
                          .toList(),
                      materialName,
                    ),
                  );

                  // geometries.add(DaeGeometry(
                  //   vertex: inputs.firstWhereOrNull((element) => element.semantic == "VERTEX"),
                  //   normal: inputs.firstWhereOrNull((element) => element.semantic == "NORMAL"),
                  //   uv: inputs.firstWhereOrNull((element) => element.semantic == "TEXCOORD"),
                  // ));

                  // indices ??= [];
                  // indices.addAll(pList);

                  // NOTE: Fill vcounts with 3's in order to share same code later
                  // This step is necessary since geometries can have a polylist and triangles node at the same time
                  // => If you find a nicer implementation feel free to make a pull request ;D
                  // vcounts ??= [];
                  // vcounts.addAll(List.filled((pList.length / 3).floor(), 3));
                } else if (node.localName == "polylist") {
                  List<int> pList = removeCommentsAndLineBreaks(XMLFunctions.getXmlElementChildByName(node, "p")!.innerText)
                      .split(' ')
                      .where((s) => s.isNotEmpty)
                      .map((s) => int.parse(s))
                      .toList();

                  List<int> vcounts = (XMLFunctions.getXmlElementChildByName(node, "vcount")!.innerText)
                      .split(' ')
                      .where((s) => s.isNotEmpty)
                      .map((s) => int.parse(s))
                      .toList();

                  // inputs.addAll(XMLFunctions.getXmlElementChildrenByName(node, "input")
                  //     .map((XmlElement inputNode) => DaeInput(
                  //           inputNode.getAttribute("semantic")!,
                  //           inputNode.getAttribute("source")!,
                  //           int.parse(
                  //             inputNode.getAttribute("offset")!,
                  //           ),
                  //           pList,
                  //           vcounts: vcounts,
                  //         ))
                  //     .toList());

                  String? materialName = node.getAttribute("material");

                  geometries.add(
                    MeshData(
                      XMLFunctions.getXmlElementChildrenByName(node, "input")
                          .map((XmlElement inputNode) => DaeInput(
                                inputNode.getAttribute("semantic")!,
                                inputNode.getAttribute("source")!,
                                int.parse(inputNode.getAttribute("offset")!),
                                pList,
                                vcounts: vcounts,
                              ))
                          .toList(),
                      materialName,
                    ),
                  );

                  // geometries.add(DaeGeometry(
                  //   vertex: inputs.firstWhereOrNull((element) => element.semantic == "VERTEX"),
                  //   normal: inputs.firstWhereOrNull((element) => element.semantic == "NORMAL"),
                  //   uv: inputs.firstWhereOrNull((element) => element.semantic == "TEXCOORD"),
                  // ));

                  // indices ??= [];
                  // indices = pList;
                } else if (node.localName == "lines") {
                  List<int> pList = removeCommentsAndLineBreaks(XMLFunctions.getXmlElementChildByName(node, "p")!.innerText)
                      .split(' ')
                      .where((s) => s.isNotEmpty)
                      .map((s) => int.parse(s))
                      .toList();

                  String? materialName = node.getAttribute("material");

                  geometries.add(
                    MeshData(
                      XMLFunctions.getXmlElementChildrenByName(node, "input")
                          .map((XmlElement inputNode) => DaeInput(
                                inputNode.getAttribute("semantic")!,
                                inputNode.getAttribute("source")!,
                                int.parse(inputNode.getAttribute("offset")!),
                                pList,
                              ))
                          .toList(),
                      materialName,
                      line: true,
                    ),
                  );
                }
              }

              for (MeshData meshData in geometries) {
                List<Vector3>? triangles;
                List<Vector3>? normals;
                List<Vector2>? uvs;

                for (DaeInput input in meshData.inputs) {
                  String source = input.source.replaceAll("#", "");

                  if (sources.containsKey(source)) {
                    if (input.semantic == "TEXCOORD") {
                      List<Vector2> temp = [];
                      for (int i = input.offset; i < input.indices.length; i += meshData.inputs.length) {
                        int index = input.indices[i] * 2;
                        temp.add(Vector2(sources[source]![index], sources[source]![index + 1]));
                      }
                      uvs ??= [];
                      uvs.addAll(temp);
                    } else if (input.semantic == "NORMAL") {
                      List<Vector3> temp = [];

                      if (input.vcounts == null) {
                        // triangles
                        for (int i = input.offset; i < input.indices.length; i += meshData.inputs.length) {
                          int index = input.indices[i] * 3;
                          Vector3 vec = Vector3(sources[source]![index], sources[source]![index + 1], sources[source]![index + 2]);
                          // vec *= 0.001;
                          vec *= scalingFactor;
                          temp.add(vec);
                          //temp.add(XMLFunctions.urdfToThreePos(vec));
                        }
                      } else {
                        // polygons => format polygons to triangles
                        int vIndex = 0;
                        List<Vector3> polygon = [];
                        int index = input.indices[meshData.inputs.length];

                        for (int i = input.offset; i < input.indices.length; i += meshData.inputs.length) {
                          index = input.indices[i] * 3;

                          Vector3 vec = Vector3(
                            sources[source]![index],
                            sources[source]![index + 1],
                            sources[source]![index + 2],
                          );
                          // vec *= 0.001;
                          vec *= scalingFactor;
                          polygon.add(vec);
                          // polygon.add(XMLFunctions.urdfToThreePos(vec));

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
                      for (int i = input.offset; i < input.indices.length; i += meshData.inputs.length) {
                        int index = input.indices[i] * 3;
                        Vector3 vec = Vector3(sources[vertsSource]![index], sources[vertsSource]![index + 1], sources[vertsSource]![index + 2]);
                        // vec *= 0.001;
                        vec *= scalingFactor;
                        temp.add(vec);
                        // temp.add(XMLFunctions.urdfToThreePos(vec));
                      }
                    } else {
                      // polygons => format polygons to triangles
                      int vIndex = 0;
                      List<Vector3> polygon = [];
                      int index = input.indices[meshData.inputs.length];

                      for (int i = input.offset; i < input.indices.length; i += meshData.inputs.length) {
                        index = input.indices[i] * 3;

                        Vector3 vec = Vector3(
                          sources[vertsSource]![index],
                          sources[vertsSource]![index + 1],
                          sources[vertsSource]![index + 2],
                        );
                        // vec *= 0.001;
                        vec *= scalingFactor;
                        polygon.add(vec);
                        // polygon.add(XMLFunctions.urdfToThreePos(vec));

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
                } else if (!meshData.line) {
                  // for smooth shading
                  geometry.computeVertexNormals();

                  // for flat shading
                  // geometry.computeFaceNormals();
                }

                if (uvs != null) {
                  geometry.setAttribute('uv', Float32BufferAttribute(Float32Array.fromList(uvs.expand((e) => [e.x, e.y]).toList()), 2));
                }

                // geometry.rotateY(-pi / 2);

                // geometry.rotateY(pi / 2);
                // geometry.rotateZ(pi / 2);
                // geometry.rotateY(-pi / 2);

                // geometry.rotateX(-pi / 2);

                // geometry.applyMatrix4(matrix4Global * matrix4Local)

                Matrix4 dae2threeMatrix = Matrix4();
                dae2threeMatrix.set(1, 0, 0, 0, 0, 0, -1, 0, 0, 1, 0, 0, 0, 0, 0, 1).invert();

                // apply matrix4 transforms
                if (transforms.containsKey(geometryId)) {
                  // Matrix4 adjustedTransform = transforms[geometryId]!.clone().multiply(dae2threeMatrix);
                  // Matrix4 adjustedTransform = dae2threeMatrix.clone().multiply(transforms[geometryId]!);
                  // Matrix4 matrix = adjustedTransform.clone();

                  // matrix.setPosition(matrix.elements[12], matrix.elements[14], -matrix.elements[13]);

                  dae2threeMatrix.multiply(transforms[geometryId]!);
                }

                geometry.applyMatrix4(dae2threeMatrix);

                Material? material;

                if (meshData.materialName != null &&
                    materialReferences.containsKey(geometryId) &&
                    materialReferences[geometryId]!.containsKey(meshData.materialName)) {
                  String materialId = materialReferences[geometryId]![meshData.materialName]!;

                  if (materials.containsKey(materialId)) {
                    material = materials[materialId];
                  }
                }

                material ??= MeshPhongMaterial({"color": 0x0000ff, "flatShading": false, "side": DoubleSide});

                Object3D object;

                if (meshData.line) {
                  object = LineSegments(geometry, material);
                } else {
                  object = Mesh(geometry, material);
                }

                meshes ??= [];
                meshes!.add(object);
              }
            }
          }
        }
      }
    }
  }
}
