import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'core/theme/app_theme.dart';
import 'screens/main/main_screen.dart';
import 'screens/projects/projects_screen.dart';

final _router = GoRouter(
  initialLocation: '/',
  routes: [
    GoRoute(
      path: '/',
      builder: (context, state) => const ProjectsScreen(),
    ),
    GoRoute(
      path: '/project/:id',
      builder: (context, state) {
        final id = int.tryParse(state.pathParameters['id'] ?? '0') ?? 0;
        return MainScreen(projectId: id);
      },
    ),
  ],
);

class App extends ConsumerWidget {
  const App({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return MaterialApp.router(
      title: 'Open GTFS Planner',
      theme: AppTheme.darkTheme,
      routerConfig: _router,
      debugShowCheckedModeBanner: false,
    );
  }
}
