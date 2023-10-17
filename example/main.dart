import 'dart:async';
import 'dart:math';
import 'dart:ui';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import 'package:urdf_parser/src/urdf_loader.dart';
import 'package:urdf_parser/src/urdf_robot.dart';

import 'package:flutter_gl/flutter_gl.dart';

import 'package:three_dart/three_dart.dart' as three;
import 'package:three_dart_jsm/three_dart_jsm.dart' as three_jsm;

class ExamplePage extends StatefulWidget {
  final String fileName;

  const ExamplePage({Key? key, required this.fileName}) : super(key: key);

  @override
  State<ExamplePage> createState() => _ExamplePageState();
}

class _ExamplePageState extends State<ExamplePage> with WidgetsBindingObserver {
  late FlutterGlPlugin three3dRender;
  three.WebGLRenderer? renderer;

  int? fboId;
  late double width;
  late double height;

  Size? screenSize;

  late three.Scene scene;
  late three.Camera camera;

  double dpr = 1.0;

  bool verbose = false;
  bool disposed = false;

  late three.WebGLRenderTarget renderTarget;

  dynamic sourceTexture;

  late GlobalKey<three_jsm.DomLikeListenableState> _globalKey;

  late three_jsm.OrbitControls controls;

  URDFRobot? robot;

  @override
  void initState() {
    _globalKey = GlobalKey<three_jsm.DomLikeListenableState>();

    super.initState();

    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    disposed = true;

    WidgetsBinding.instance.removeObserver(this);

    super.dispose();
  }

  // Platform messages are asynchronous, so we initialize in an async method.
  Future<void> initPlatformState() async {
    width = screenSize!.width;
    height = screenSize!.height - 30;

    three3dRender = FlutterGlPlugin();

    Map<String, dynamic> options = {"antialias": true, "alpha": false, "width": width.toInt(), "height": height.toInt(), "dpr": dpr};

    await three3dRender.initialize(options: options);

    setState(() {});

    Future.delayed(const Duration(milliseconds: 100), () async {
      await three3dRender.prepareContext();

      await initScene();
    });
  }

  void initSize(BuildContext context) {
    if (screenSize != null) {
      return;
    }

    final mqd = MediaQuery.of(context);

    screenSize = mqd.size;
    dpr = mqd.devicePixelRatio;

    initPlatformState();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Builder(
        builder: (BuildContext context) {
          initSize(context);
          return SingleChildScrollView(child: _build(context));
        },
      ),
    );
  }

  Widget _build(BuildContext context) {
    return Column(
      children: [
        three_jsm.DomLikeListenable(
            key: _globalKey,
            builder: (BuildContext context) {
              return Container(
                  width: width,
                  height: height,
                  color: Colors.red,
                  child: Builder(builder: (BuildContext context) {
                    if (kIsWeb) {
                      return three3dRender.isInitialized ? HtmlElementView(viewType: three3dRender.textureId!.toString()) : Container();
                    } else {
                      return three3dRender.isInitialized ? Texture(textureId: three3dRender.textureId!) : Container();
                    }
                  }));
            }),
      ],
    );
  }

  void render() {
    int t = DateTime.now().millisecondsSinceEpoch;
    final gl = three3dRender.gl;

    renderer!.render(scene, camera);

    int t1 = DateTime.now().millisecondsSinceEpoch;

    // NOTE: Uncomment section below for test animation that loops through all available joints
    // double time = t1 / 6e4; //3e2

    // List<MapEntry<String, URDFJoint>> joints = (robot!.joints.entries.where((entry) => entry.value.type != "fixed")).toList();

    // // robot joint test animation
    // double periodicValueSmall = sin((time * joints.length) % 1 * 2 * pi) / 2 + 0.5;
    // int s = (time * joints.length).floor() % joints.length;

    // // set last angle rotation to 0.5
    // int lastS = (s - 1 + joints.length) % joints.length;
    // robot!.trySetAngle(joints[lastS].key, lerpDouble(joints[lastS].value.lower, joints[lastS].value.upper, 0.5)!);

    // robot!.trySetAngle(joints[s].key, lerpDouble(joints[s].value.lower, joints[s].value.upper, periodicValueSmall)!);

    if (verbose) {
      print("render cost: ${t1 - t} ");
      print(renderer!.info.memory);
      print(renderer!.info.render);
    }

    gl.flush();

    if (verbose) print(" render: sourceTexture: $sourceTexture ");

    if (!kIsWeb) {
      three3dRender.updateTexture(sourceTexture);
    }
  }

  void initRenderer() {
    Map<String, dynamic> options = {"width": width, "height": height, "gl": three3dRender.gl, "antialias": true, "canvas": three3dRender.element};
    renderer = three.WebGLRenderer(options);
    renderer!.setPixelRatio(dpr);
    renderer!.setSize(width, height, false);
    renderer!.shadowMap.enabled = false;

    if (!kIsWeb) {
      var pars = three.WebGLRenderTargetOptions({"minFilter": three.LinearFilter, "magFilter": three.LinearFilter, "format": three.RGBAFormat});
      renderTarget = three.WebGLRenderTarget((width * dpr).toInt(), (height * dpr).toInt(), pars);
      renderTarget.samples = 4;
      renderer!.setRenderTarget(renderTarget);
      sourceTexture = renderer!.getRenderTargetGLTexture(renderTarget);
    }
  }

  Future<void> initRenderer2() async {
    Map<String, dynamic> options = {"width": width, "height": height, "antialias": true, "dpr": dpr};

    FlutterGlPlugin glPlugin = FlutterGlPlugin();

    await glPlugin.initialize(options: options);
    Future.delayed(const Duration(milliseconds: 100), () async {
      await glPlugin.prepareContext();
    });

    renderer = three.WebGLRenderer({
      'gl': glPlugin.gl,
      'canvas': glPlugin.element,
      'width': width,
      'height': height,
      // 'alpha': alpha,
      "antialias": true,
    });
    renderer!.setPixelRatio(dpr);
    renderer!.setSize(width, height, false);
    renderer!.shadowMap.enabled = false;

    if (!kIsWeb) {
      final three.WebGLRenderTargetOptions options = three.WebGLRenderTargetOptions({'format': three.RGBAFormat});
      final three.RenderTarget renderTarget = three.WebGLMultisampleRenderTarget(
        (width * dpr).toInt(),
        (width * dpr).toInt(),
        options,
      );
      renderTarget.samples = 4;
      renderer!.setRenderTarget(renderTarget);
      sourceTexture = renderer!.getRenderTargetGLTexture(renderTarget);
    }
  }

  Future<void> initScene() async {
    initRenderer();
    await initPage();
  }

  Future<void> initPage() async {
    scene = three.Scene();
    scene.background = three.Color(0xcccccc);

    camera = three.PerspectiveCamera(60, width / height, 1, 2000);
    camera.position.set(400, 200, 0);
    scene.add(camera);

    // --- Controls ---
    controls = three_jsm.OrbitControls(camera, _globalKey);

    controls.enableDamping = true; // an animation loop is required when either damping or auto-rotation are enabled
    controls.dampingFactor = 0.05;

    controls.screenSpacePanning = false;

    controls.minDistance = 10;
    controls.maxDistance = 1000;

    controls.maxPolarAngle = three.Math.pi / 2;

    // --- World ---

    // grid helper
    three.GridHelper gridHelper = three.GridHelper(1000, 20, 0xff8400, 0x0095ff);
    gridHelper.position = three.Vector3(0, 0, 0);
    gridHelper.frustumCulled = false;
    scene.add(gridHelper);

    // axis
    three.Mesh xMesh = three.Mesh(three.CylinderGeometry(0.5, 0.5, 100), three.MeshPhongMaterial({"color": 0xff0000, "flatShading": false}));
    xMesh.position = three.Vector3(60, 0, 0);
    xMesh.setRotationFromEuler(three.Euler(0, 0, pi / 2));
    scene.add(xMesh);

    three.Mesh yMesh = three.Mesh(three.CylinderGeometry(0.5, 0.5, 100), three.MeshPhongMaterial({"color": 0x00ff00, "flatShading": false}));
    yMesh.position = three.Vector3(0, 60, 0);
    scene.add(yMesh);

    three.Mesh zMesh = three.Mesh(three.CylinderGeometry(0.5, 0.5, 100), three.MeshPhongMaterial({"color": 0x0000ff, "flatShading": false}));
    zMesh.position = three.Vector3(0, 0, 60);
    zMesh.setRotationFromEuler(three.Euler(pi / 2, 0, 0));
    scene.add(zMesh);

    // URDF
    robot = await URDFLoader.parse(
      "path to urdf file",
      "path to urdf content folder where stl/dae files are located",
    );

    robot!.transform.scale = three.Vector3(100, 100, 100);

    // robot!.transform.localRotation = three.Quaternion()..setFromEuler(three.Euler(pi, 0, 0));
    // robot!.transform.localPosition = three.Vector3(0, 26, 0);
    // robot!.transform.printHierarchy();

    scene.add(robot!.getObject());

    // --- Lights ---
    var dirLight1 = three.DirectionalLight(0xffffff);
    dirLight1.position.set(10, 10, 10);
    scene.add(dirLight1);

    var dirLight2 = three.DirectionalLight(0x002288);
    dirLight2.position.set(-10, -10, -10);
    scene.add(dirLight2);

    var ambientLight = three.AmbientLight(0x222222);
    scene.add(ambientLight);

    animate();
  }

  void animate() {
    if (!mounted || disposed) {
      return;
    }

    render();

    Future.delayed(const Duration(milliseconds: 60), () {
      animate();
    });
  }
}
