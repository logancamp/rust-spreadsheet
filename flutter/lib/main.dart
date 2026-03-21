import 'package:flutter/material.dart';
import 'services/bridge_service.dart';
import 'app.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await BridgeService.init();
  runApp(const MyApp());
}
