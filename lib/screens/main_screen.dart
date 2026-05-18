import 'package:flutter/material.dart';

import 'camera_detection_screen.dart';

class MainScreen extends StatelessWidget {
  const MainScreen({super.key});

  static const routeName = '/main';

  @override
  Widget build(BuildContext context) {
    return const CameraDetectionScreen();
  }
}
