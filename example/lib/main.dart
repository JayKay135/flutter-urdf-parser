import 'dart:async';
import 'dart:math';
import 'dart:ui';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import 'package:flutter_gl/flutter_gl.dart';
import 'package:three_dart/three_dart.dart' as three;
import 'package:three_dart_jsm/three_dart_jsm.dart' as three_jsm;

import 'package:urdf_parser/urdf_parser.dart';

void main(List<String> args) {
  runApp(
    const MaterialApp(
      debugShowCheckedModeBanner: false,
      home: ExamplePage(),
    ),
  );
}

class ExamplePage extends StatefulWidget {
  const ExamplePage({Key? key}) : super(key: key);

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
    height = screenSize!.height;

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
      floatingActionButton: FloatingActionButton(
        onPressed: () {
          setState(() {
            screenSize = MediaQuery.of(context).size;

            width = screenSize!.width;
            height = screenSize!.height;
            renderer!.setPixelRatio(MediaQuery.of(context).devicePixelRatio);
            renderer!.setSize(width, height, true);
          });

          initScene();
        },
        child: Icon(Icons.repeat),
      ),
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

    double time = t1 / 3e2;

    // robot animation
    for (int i = 1; i <= 6; i++) {
      double offset = i * pi / 3;
      double ratio = max(0, sin(time + offset));

      robot!.trySetAngle("HP$i", lerpDouble(30, 0, ratio)! * three.MathUtils.deg2rad);
      robot!.trySetAngle("KP$i", lerpDouble(90, 150, ratio)! * three.MathUtils.deg2rad);
      robot!.trySetAngle("AP$i", lerpDouble(-30, -60, ratio)! * three.MathUtils.deg2rad);

      robot!.trySetAngle("TC${i}A", lerpDouble(0, 0.065, ratio)!);
      robot!.trySetAngle("TC${i}B", lerpDouble(0, 0.065, ratio)!);

      robot!.trySetAngle("W$i", t1 * 0.000001);
    }

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
      "assets/T12/urdf/T12.URDF",
      "assets/T12",
      URDFLoaderOptions(),
    );

    robot!.transform.scale = three.Vector3(10, 10, 10);

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
