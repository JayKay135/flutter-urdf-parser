import 'dart:async';
import 'dart:typed_data';

import 'package:flutter_gl/flutter_gl.dart';
import 'package:three_dart/three_dart.dart';
import 'package:three_dart/three_dart.dart' as three;

/// Description: A three loader for STL ASCII files, as created by Solidworks and other CAD programs.
///
/// Supports both binary and ASCII encoded files, with automatic detection of type.
///
/// The loader returns a non-indexed buffer geometry.
///
/// Limitations:
///  Binary decoding supports "Magics" color format (http://en.wikipedia.org/wiki/STL_(file_format)#Color_in_binary_STL).
///  There is perhaps some question as to how valid it is to always assume little-endian-ness.
///  ASCII decoding assumes file is UTF-8.
///
/// Usage:
///  const loader = new STLLoader();
///  loader.load('assets/models/stl/slotted_disk.stl', (geometry) {
///    scene.add(three.Mesh(geometry));
///  });
///
/// For binary STLs geometry might contain colors for vertices. To use it:
///  // use the same code to load STL as above
///  if (geometry.hasColors) {
///    material = new three.MeshPhongMaterial({"opacity": geometry.alpha, "vertexColors": true });
///  } else { .... }
///  const mesh = new three.Mesh(geometry, material);
///
/// For ASCII STLs containing multiple solids, each solid is assigned to a different group.
/// Groups can be used to assign a different color by defining an array of materials with the same length of
/// geometry.groups and passing it to the Mesh constructor:
///
/// const mesh = new three.Mesh(geometry, material);
///
/// For example:
///
///  const materials = [];
///  const nGeometryGroups = geometry.groups.length;
///
///  const colorMap = ...; // Some logic to index colors.
///
///  for (let i = 0; i < nGeometryGroups; i++) {
///
///		const material = new three.MeshPhongMaterial({
///			color: colorMap[i],
///			wireframe: false
///		});
///
///  }
///
///  materials.push(material);
///  const mesh = new three.Mesh(geometry, materials);
class STLLoader extends Loader {
  STLLoader(LoadingManager? manager) : super(manager);

  @override
  Future<Mesh> loadAsync(url) async {
    var completer = Completer<Mesh>();

    load(url, (buffer) {
      completer.complete(buffer);
    });

    return completer.future;
  }

  @override
  void load(url, onLoad, [onProgress, onError]) {
    var loader = FileLoader(manager);
    loader.setPath(path);
    loader.setResponseType('arraybuffer');
    loader.setRequestHeader(requestHeader);
    loader.setWithCredentials(withCredentials);

    loader.load(url, (text) async {
      // try {

      onLoad(parse(text));

      // } catch ( e ) {

      // 	if ( onError ) {

      // 		onError( e );

      // 	} else {

      // 		console.error( e );

      // 	}

      // 	scope.manager.itemError( url );

      // }
    }, onProgress, onError);
  }

  @override
  Mesh parse(json, [String? path, Function? onLoad, Function? onError]) {
    bool matchDataViewAt(query, Uint8List reader, offset) {
      // Check if each byte in query matches the corresponding byte from the current offset

      for (int i = 0, il = query.length; i < il; i++) {
        if (query[i] != reader.buffer.asByteData().getUint8(offset + i))
          return false;
      }

      return true;
    }

    bool isBinary(Uint8List data) {
      // var reader = DataView(data);
      ByteData byteData = data.buffer.asByteData();
      const faceSize = (32 / 8 * 3) + ((32 / 8 * 3) * 3) + (16 / 8);
      final int nFaces = byteData.getUint32(80, Endian.little);
      final double expect = 80 + (32 / 8) + (nFaces * faceSize);

      if (expect == data.lengthInBytes) {
        return true;
      }

      // An ASCII STL data must begin with 'solid ' as the first six bytes.
      // However, ASCII STLs lacking the SPACE after the 'd' are known to be
      // plentiful.  So, check the first 5 bytes for 'solid'.

      // Several encodings, such as UTF-8, precede the text with up to 5 bytes:
      // https://en.wikipedia.org/wiki/Byte_order_mark#Byte_order_marks_by_encoding
      // Search for "solid" to start anywhere after those prefixes.

      // US-ASCII ordinal values for 's', 'o', 'l', 'i', 'd'

      const solid = [115, 111, 108, 105, 100];

      for (int off = 0; off < 5; off++) {
        // If "solid" text is matched to the current offset, declare it to be an ASCII STL.

        if (matchDataViewAt(solid, data, off)) return false;
      }

      // Couldn't find "solid" text at the beginning; it is binary STL.

      return true;
    }

    Mesh parseBinary(Uint8List data) {
      // const reader = DataView(data);
      ByteData byteData = data.buffer.asByteData();
      final int faces = byteData.getUint32(80, Endian.little);

      bool hasColors = false;
      late Float32Array colors;

      late double r, g, b;
      late double defaultR, defaultG, defaultB; //, alpha;

      // process STL header
      // check for default color in header ("COLOR=rgba" sequence).

      for (int index = 0; index < 80 - 10; index++) {
        if ((byteData.getUint32(index, Endian.big) == 0x434F4C4F /*COLO*/) &&
            (byteData.getUint8(index + 4) == 0x52 /*'R'*/) &&
            (byteData.getUint8(index + 5) == 0x3D /*'='*/)) {
          hasColors = true;
          colors = Float32Array(faces * 3 * 3);

          defaultR = byteData.getUint8(index + 6) / 255;
          defaultG = byteData.getUint8(index + 7) / 255;
          defaultB = byteData.getUint8(index + 8) / 255;
          //alpha = byteData.getUint8(index + 9) / 255;
        }
      }

      const int dataOffset = 84;
      const int faceLength = 12 * 4 + 2;

      final BufferGeometry geometry = BufferGeometry();

      final Float32Array vertices = Float32Array(faces * 3 * 3);
      final Float32Array normals = Float32Array(faces * 3 * 3);

      final Color color = Color();

      for (int face = 0; face < faces; face++) {
        final int start = dataOffset + face * faceLength;
        final double normalX = byteData.getFloat32(start, Endian.little);
        final double normalY = byteData.getFloat32(start + 4, Endian.little);
        final double normalZ = byteData.getFloat32(start + 8, Endian.little);

        if (hasColors) {
          final int packedColor = byteData.getUint16(start + 48, Endian.little);

          if ((packedColor & 0x8000) == 0) {
            // facet has its own unique color

            r = (packedColor & 0x1F) / 31;
            g = ((packedColor >> 5) & 0x1F) / 31;
            b = ((packedColor >> 10) & 0x1F) / 31;
          } else {
            r = defaultR;
            g = defaultG;
            b = defaultB;
          }
        }

        for (int i = 1; i <= 3; i++) {
          final int vertexstart = start + i * 12;
          final int componentIdx = (face * 3 * 3) + ((i - 1) * 3);

          vertices[componentIdx + 0] =
              byteData.getFloat32(vertexstart + 0, Endian.little);
          vertices[componentIdx + 1] =
              byteData.getFloat32(vertexstart + 4, Endian.little);
          vertices[componentIdx + 2] =
              byteData.getFloat32(vertexstart + 8, Endian.little);

          normals[componentIdx + 0] = -normalY;
          normals[componentIdx + 1] = normalZ;
          normals[componentIdx + 2] = normalX;

          if (hasColors) {
            color.setRGB(r, g, b).convertSRGBToLinear();

            colors[componentIdx] = color.r;
            colors[componentIdx + 1] = color.g;
            colors[componentIdx + 2] = color.b;
          }
        }
      }

      geometry.setAttribute('position', Float32BufferAttribute(vertices, 3));
      geometry.setAttribute('normal', Float32BufferAttribute(normals, 3));

      if (hasColors) {
        geometry.setAttribute('color', Float32BufferAttribute(colors, 3));
        // geometry.hasColors = true;
        // geometry.alpha = alpha;
      }

      geometry.verticesNeedUpdate = true;
      geometry.normalsNeedUpdate = true;

      three.Matrix4 dae2threeMatrix = three.Matrix4();
      dae2threeMatrix.set(1, 0, 0, 0, 0, 0, 1, 0, 0, -1, 0, 0, 0, 0, 0, 1);
      geometry.applyMatrix4(dae2threeMatrix);

      return Mesh(
          geometry,
          MeshPhongMaterial({
            "color": color.getHex(),
            "flatShading": false,
            "side": DoubleSide
          }));
    }

    Mesh parseASCII(String data) {
      final BufferGeometry geometry = BufferGeometry();
      final patternSolid = RegExp(r"solid([\s\S]*?)endsolid", multiLine: true);
      final patternFace = RegExp(r"facet([\s\S]*?)endfacet", multiLine: true);
      final patternName = RegExp(r"solid\s(.+)");
      int faceCounter = 0;

      const patternFloat = r"[\s]+([+-]?(?:\d*)(?:\.\d*)?(?:[eE][+-]?\d+)?)";
      final RegExp patternVertex = RegExp(
          'vertex$patternFloat$patternFloat$patternFloat',
          multiLine: true);
      final RegExp patternNormal = RegExp(
          'normal$patternFloat$patternFloat$patternFloat',
          multiLine: true);

      final RegExp patternColor =
          RegExp(r'endsolid\s+\w+=RGB\((\d+),(\d+),(\d+)\)');

      List<double> vertices = [];
      List<double> normals = [];
      List<String> groupNames = [];

      List<Color> colors = patternColor
          .allMatches(data)
          .map(
            (e) => Color(
              double.parse(e.group(1)!) / 255,
              double.parse(e.group(2)!) / 255,
              double.parse(e.group(3)!) / 255,
            ),
          )
          .toList();

      var normal = Vector3();

      int groupCount = 0;
      int startVertex = 0;
      int endVertex = 0;

      for (RegExpMatch? match1 in patternSolid.allMatches(data)) {
        startVertex = endVertex;

        final solid = match1!.group(0);
        final name = (match1 = patternName.firstMatch(solid!)) != null
            ? match1!.group(1)
            : '';

        groupNames.add(name!);

        for (RegExpMatch match2 in patternFace.allMatches(solid)) {
          int vertexCountPerFace = 0;
          int normalCountPerFace = 0;

          var text = match2.group(0)!;

          for (Match match in patternNormal.allMatches(text)) {
            normal.x = parseFloat(match.group(1)!);
            normal.y = parseFloat(match.group(2)!);
            normal.z = parseFloat(match.group(3)!);
            normalCountPerFace++;
          }

          for (Match match in patternVertex.allMatches(text)) {
            vertices.addAll([
              parseFloat(match.group(1)!),
              parseFloat(match.group(2)!),
              parseFloat(match.group(3)!)
            ]);
            normals.addAll([normal.x, normal.y, normal.z]);
            vertexCountPerFace++;
            endVertex++;
          }

          // every face has to own ONE valid normal
          if (normalCountPerFace != 1) {
            throw Exception(
                'three.STLLoader: Something isn\'t right with the normal of face number $faceCounter');
          }

          // each face have to own three valid vertices
          if (vertexCountPerFace != 3) {
            throw Exception(
                'three.STLLoader: Something isn\'t right with the vertices of face number $faceCounter');
          }

          faceCounter++;
        }

        final int start = startVertex;
        final int count = endVertex - startVertex;

        geometry.userData['groupNames'] = groupNames;

        geometry.addGroup(start, count, groupCount);
        groupCount++;
      }

      geometry.setAttribute('position',
          Float32BufferAttribute(Float32Array.fromList(vertices), 3));
      geometry.setAttribute(
          'normal', Float32BufferAttribute(Float32Array.fromList(normals), 3));

      three.Matrix4 dae2threeMatrix = three.Matrix4();
      dae2threeMatrix.set(1, 0, 0, 0, 0, 0, 1, 0, 0, -1, 0, 0, 0, 0, 0, 1);
      geometry.applyMatrix4(dae2threeMatrix);

      List<Material> materials;

      if (colors.length != groupCount) {
        // apply default material to each group
        materials = List.generate(
            groupCount,
            (index) => MeshBasicMaterial(
                {"color": 0xffffff, "flatShading": true, "side": DoubleSide}));
      } else {
        // use extracted colors
        materials = colors
            .map((e) => MeshBasicMaterial(
                {"color": e.getHex(), "flatShading": true, "side": DoubleSide}))
            .toList();
      }

      return Mesh(geometry, materials);
    }

    String ensureString(buffer) {
      if (buffer is! String) {
        return String.fromCharCodes(buffer);
      }

      return buffer;
    }

    Uint8List ensureBinary(buffer) {
      if (buffer is String) {
        final Uint8List uint8list = Uint8List(buffer.length);
        for (int i = 0; i < buffer.length; i++) {
          uint8list[i] =
              buffer.codeUnitAt(i) & 0xff; // implicitly assumes little-endian
        }

        // return array_buffer.buffer || array_buffer;
        return uint8list;
      } else {
        return buffer;
      }
    }

    final Uint8List binData = ensureBinary(json);
    return isBinary(binData)
        ? parseBinary(binData)
        : parseASCII(ensureString(json));
  }
}
