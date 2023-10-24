import 'dart:async';
import 'dart:io';
import 'collada_loader.dart';

import 'package:three_dart/three_dart.dart';

class DAELoader {
  /// Loads all meshes associated with the dae file
  ///
  /// [data] : should be the string contents of the dae file
  /// [textures] : a collection of the names of the textures associated with the meshes, if there are no texture or you do not care about them pass string[0]
  ///
  static List<Object3D> load(String data, List<String> textures) {
    ColladaLite cLite = ColladaLite(data);
    List<Object3D> meshes = cLite.meshes!;

    if (textures.isNotEmpty) {
      textures = cLite.textureNames!;
    }
    return meshes;
  }

  /// Loads all meshes associated with the dae file
  ///
  /// [path] : should be the path to the dae file
  /// [textures] : a collection of the names of the textures associated with the meshes, if there are no texture or you do not care about them pass string[0]
  ///
  static Future<List<Object3D>> loadFromPath(
      String path, List<String> textures) async {
    ColladaLite? cLite;

    File file = File(path);
    if (await file.exists()) {
      cLite = ColladaLite(await file.readAsString());
    } else {
      throw Exception("File not found at $path");
    }

    List<Object3D> meshes = cLite.meshes!;
    if (textures.isNotEmpty) {
      textures = cLite.textureNames!;
    }

    return meshes;
  }
}
