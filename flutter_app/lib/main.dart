import 'package:flutter/material.dart';
import 'screens/auth_screens.dart';
import 'screens/home_shell.dart';
import 'services/api.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await session.init();
  runApp(const JeevandanApp());
}

class JeevandanApp extends StatelessWidget {
  const JeevandanApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'JEEVANDAN',
      navigatorKey: navigatorKey,
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFFC62828)),
        inputDecorationTheme: const InputDecorationTheme(border: OutlineInputBorder()),
      ),
      home: ListenableBuilder(
        listenable: session,
        builder: (context, _) => session.user == null ? const LoginScreen() : const HomeShell(),
      ),
    );
  }
}
