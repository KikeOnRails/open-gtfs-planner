import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../models/project_model.dart';
import '../../models/gtfs_models.dart';
import '../database/gtfs_repository.dart';

// ---------------------------------------------------------------------------
// Projects
// ---------------------------------------------------------------------------

final projectsProvider =
    AsyncNotifierProvider<ProjectsNotifier, List<ProjectModel>>(
        ProjectsNotifier.new);

class ProjectsNotifier extends AsyncNotifier<List<ProjectModel>> {
  @override
  Future<List<ProjectModel>> build() => GtfsRepository.getProjects();

  Future<ProjectModel> createProject(String name) async {
    final project = await GtfsRepository.createProject(name);
    ref.invalidateSelf();
    return project;
  }

  Future<void> deleteProject(int id) async {
    await GtfsRepository.deleteProject(id);
    ref.invalidateSelf();
  }
}

// ---------------------------------------------------------------------------
// Current project
// ---------------------------------------------------------------------------

final currentProjectProvider = StateProvider<ProjectModel?>((ref) => null);

// ---------------------------------------------------------------------------
// GTFS Files for current project
// ---------------------------------------------------------------------------

final gtfsFilesProvider =
    AsyncNotifierProvider<GtfsFilesNotifier, List<GtfsFileModel>>(
        GtfsFilesNotifier.new);

class GtfsFilesNotifier extends AsyncNotifier<List<GtfsFileModel>> {
  @override
  Future<List<GtfsFileModel>> build() async {
    final project = ref.watch(currentProjectProvider);
    if (project == null) return [];
    return GtfsRepository.getGtfsFiles(project.id);
  }

  Future<void> reload() async {
    ref.invalidateSelf();
  }

  Future<void> deleteGtfsFile(int id) async {
    await GtfsRepository.deleteGtfsFile(id);
    ref.invalidateSelf();
  }
}

// ---------------------------------------------------------------------------
// Loaded GTFS data (agencies + routes, visible state)
// ---------------------------------------------------------------------------

/// Holds loaded agencies per gtfs_file_id
final agenciesProvider = AsyncNotifierProvider.family<AgenciesNotifier,
    List<AgencyModel>, int>(AgenciesNotifier.new);

class AgenciesNotifier extends FamilyAsyncNotifier<List<AgencyModel>, int> {
  @override
  Future<List<AgencyModel>> build(int gtfsFileId) =>
      GtfsRepository.getAgencies(gtfsFileId);
}

final routesProvider = AsyncNotifierProvider.family<RoutesNotifier,
    List<RouteModel>, int>(RoutesNotifier.new);

class RoutesNotifier extends FamilyAsyncNotifier<List<RouteModel>, int> {
  @override
  Future<List<RouteModel>> build(int gtfsFileId) =>
      GtfsRepository.getRoutes(gtfsFileId);
}

// ---------------------------------------------------------------------------
// Layer visibility state
// ---------------------------------------------------------------------------

/// Per-GTFS-file visibility map: gtfsFileId -> bool (visible)
final gtfsFileVisibilityProvider =
    StateNotifierProvider<MapNotifier<int, bool>, Map<int, bool>>(
  (_) => MapNotifier({}),
);

/// Per-route visibility: routeId -> bool
final routeShapeVisibilityProvider =
    StateNotifierProvider<MapNotifier<int, bool>, Map<int, bool>>(
  (_) => MapNotifier({}),
);

/// Per-file stops visible: gtfsFileId -> bool
final gtfsStopsVisibilityProvider =
    StateNotifierProvider<MapNotifier<int, bool>, Map<int, bool>>(
  (_) => MapNotifier({}),
);

/// Per-route simulation enabled: routeDbId -> bool
final routeSimulationVisibilityProvider =
    StateNotifierProvider<MapNotifier<int, bool>, Map<int, bool>>(
  (_) => MapNotifier({}),
);

class MapNotifier<K, V> extends StateNotifier<Map<K, V>> {
  MapNotifier(super.initial);

  void set(K key, V value) {
    state = {...state, key: value};
  }

  void toggle(K key, V trueVal, V falseVal) {
    final cur = state[key] ?? falseVal;
    set(key, cur == trueVal ? falseVal : trueVal);
  }

  void remove(K key) {
    final copy = Map<K, V>.from(state);
    copy.remove(key);
    state = copy;
  }
}
