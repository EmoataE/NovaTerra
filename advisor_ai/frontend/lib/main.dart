import 'package:flutter/material.dart';

import 'screens/dashboard_screen.dart';
import 'screens/client_screen.dart';
import 'screens/meeting_update_screen.dart';
import 'screens/prospects_screen.dart';

void main() {
  runApp(const AdvisorAIApp());
}

class AdvisorAIApp extends StatelessWidget {
  const AdvisorAIApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Advisor AI',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        scaffoldBackgroundColor: const Color(0xFFF5F6FA),
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF4F46E5),
        ),
      ),
      home: const MainNavigation(),
    );
  }
}

class MainNavigation extends StatefulWidget {
  const MainNavigation({super.key});

  @override
  State<MainNavigation> createState() => _MainNavigationState();
}

class _MainNavigationState extends State<MainNavigation> {
  int selectedIndex = 0;

  final List<Widget> screens = const [
    DashboardScreen(),
    ClientsScreen(),
    ProspectsScreen(),
    MeetingUpdateScreen(),
  ];
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: AnimatedSwitcher(
        duration: const Duration(milliseconds: 250),
        child: screens[selectedIndex],
      ),
      bottomNavigationBar: Container(
        margin: const EdgeInsets.fromLTRB(18, 0, 18, 18),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(26),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.10),
              blurRadius: 24,
              offset: const Offset(0, 10),
            ),
          ],
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(26),
          child: NavigationBar(
            height: 72,
            elevation: 0,
            backgroundColor: Colors.white,
            indicatorColor: const Color(0xFFEEF2FF),
            selectedIndex: selectedIndex,
            labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
            onDestinationSelected: (index) {
              setState(() {
                selectedIndex = index;
              });
            },
            destinations: const [
              NavigationDestination(
                icon: Icon(Icons.dashboard_outlined),
                selectedIcon: Icon(
                  Icons.dashboard_rounded,
                  color: Color(0xFF4F46E5),
                ),
                label: 'Home',
              ),
              NavigationDestination(
                icon: Icon(Icons.people_outline),
                selectedIcon: Icon(
                  Icons.people_alt_rounded,
                  color: Color(0xFF4F46E5),
                ),
                label: 'Clients',
              ),
              NavigationDestination(
                icon: Icon(Icons.track_changes_outlined),
                selectedIcon: Icon(
                  Icons.track_changes,
                  color: Color(0xFF4F46E5),
                ),
                label: 'Prospects',
              ),
              NavigationDestination(
                icon: Icon(Icons.edit_note_outlined),
                selectedIcon: Icon(
                  Icons.edit_note_rounded,
                  color: Color(0xFF4F46E5),
                ),
                label: 'Meeting',
              ),
            ],
          ),
        ),
      ),
    );
  }
}