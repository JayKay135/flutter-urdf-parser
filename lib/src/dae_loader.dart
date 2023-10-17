import 'dart:async';
import 'dart:io';
import 'collada_loader.dart';

import 'package:three_dart/three_dart.dart';

/// A class for loading Collada (.dae) files.
///
/// This class provides functionality for parsing and loading Collada files.
/// It is used to extract information about the 3D models stored in the files.
class DAELoader {
  /// Loads all meshes associated with the dae file
  ///
  /// [data] : Should be the string contents of the dae file
  /// [textures] : A collection of the names of the textures associated with the meshes
  static List<Mesh> load(String data, {List<String>? textures}) {
    ColladaLite cLite = ColladaLite(data);
    List<Mesh> meshes = cLite.meshes!;

    if (textures != null && textures.isNotEmpty) {
      textures = cLite.textureNames!;
    }
    return meshes;
  }

  /// Loads all meshes associated with the dae file
  ///
  /// [path] : Should be the path to the dae file
  /// [textures] : A collection of the names of the textures associated with the meshes
  static Future<List<Mesh>> loadFromPath(String path, {List<String>? textures}) async {
    ColladaLite? cLite;

    File file = File(path);
    if (await file.exists()) {
      cLite = ColladaLite(await file.readAsString());
    } else {
      throw Exception("File not found at $path");
    }

    List<Mesh> meshes = cLite.meshes!;
    if (textures != null && textures.isNotEmpty) {
      textures = cLite.textureNames!;
    }

    return meshes;
  }
}
