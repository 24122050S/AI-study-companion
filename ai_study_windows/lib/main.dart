import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:google_fonts/google_fonts.dart';

import 'auth_screen.dart';
import 'workspace_screen.dart'; // 👈 BẮT BUỘC IMPORT MÀN HÌNH SẢNH CHỜ

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final prefs = await SharedPreferences.getInstance();
  final String? loggedInUser = prefs.getString('username');

  runApp(MyApp(
    // 👈 NÂNG CẤP: Nếu đã đăng nhập thì vào Sảnh chờ (Workspace) thay vì HomeScreen
    startScreen: loggedInUser != null 
        ? WorkspaceScreen(username: loggedInUser) 
        : const AuthScreen()
  ));
}

class MyApp extends StatelessWidget {
  final Widget startScreen;
  const MyApp({super.key, required this.startScreen});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Gia sư AI',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFFC8E6C9)),
        textTheme: GoogleFonts.nunitoTextTheme(),
        useMaterial3: true,
      ),
      home: startScreen, 
    );
  }
}