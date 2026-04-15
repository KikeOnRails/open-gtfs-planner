import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../models/project_model.dart';
import '../../models/gtfs_models.dart';
import '../core/database/gtfs_repository.dart';
import '../core/utils/gtfs_importer.dart';

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
final agenciesProvider =
    AsyncNotifierProvider.family<AgenciesNotifier, List<AgencyModel>, int>(
        AgenciesNotifier.new);

class AgenciesNotifier extends FamilyAsyncNotifier<List<AgencyModel>, int> {
  @override
  Future<List<AgencyModel>> build(int gtfsFileId) =>
      GtfsRepository.getAgencies(gtfsFileId);
}

final routesProvider =
    AsyncNotifierProvider.family<RoutesNotifier, List<RouteModel>, int>(
        RoutesNotifier.new);

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

/// Per-route stops visibility: routeDbId -> bool
final routeStopsVisibilityProvider =
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

// ---------------------------------------------------------------------------
// GTFS Import Progress State
// ---------------------------------------------------------------------------

/// Represents a single import task in progress
class ImportTask {
  final String id;
  final String filename;
  final double progress;
  final String step;
  final bool isComplete;
  final String? error;

  const ImportTask({
    required this.id,
    required this.filename,
    this.progress = 0.0,
    this.step = 'Iniciando...',
    this.isComplete = false,
    this.error,
  });

  ImportTask copyWith({
    double? progress,
    String? step,
    bool? isComplete,
    String? error,
  }) {
    return ImportTask(
      id: id,
      filename: filename,
      progress: progress ?? this.progress,
      step: step ?? this.step,
      isComplete: isComplete ?? this.isComplete,
      error: error ?? this.error,
    );
  }
}

/// Provider to track all active imports
final importTasksProvider =
    StateNotifierProvider<ImportTasksNotifier, Map<String, ImportTask>>(
  (_) => ImportTasksNotifier(),
);

class ImportTasksNotifier extends StateNotifier<Map<String, ImportTask>> {
  ImportTasksNotifier() : super({});

  /// Start a new import task and return its ID
  String startImport(String filename) {
    final id = DateTime.now().millisecondsSinceEpoch.toString();
    final task = ImportTask(id: id, filename: filename);
    state = {...state, id: task};
    return id;
  }

  /// Update progress for an import task
  void updateProgress(String id, String step, double progress) {
    final task = state[id];
    if (task != null) {
      state = {...state, id: task.copyWith(step: step, progress: progress)};
    }
  }

  /// Mark import as complete
  void completeImport(String id) {
    final task = state[id];
    if (task != null) {
      state = {
        ...state,
        id: task.copyWith(isComplete: true, progress: 1.0, step: 'Completado'),
      };
      // Remove after a short delay
      Future.delayed(const Duration(seconds: 2), () {
        removeImport(id);
      });
    }
  }

  /// Mark import as failed
  void failImport(String id, String error) {
    final task = state[id];
    if (task != null) {
      state = {...state, id: task.copyWith(error: error, isComplete: true)};
      // Remove after a delay
      Future.delayed(const Duration(seconds: 5), () {
        removeImport(id);
      });
    }
  }

  /// Remove an import task
  void removeImport(String id) {
    final copy = Map<String, ImportTask>.from(state);
    copy.remove(id);
    state = copy;
  }
}

/// Helper provider to run imports in background
final gtfsImportProvider = Provider((ref) => GtfsImportService(ref));

class GtfsImportService {
  final Ref ref;

  GtfsImportService(this.ref);

  /// Import GTFS from path (desktop)
  Future<void> importFromPath(int projectId, String path) async {
    final filename = path.split('/').last.split('\\').last;
    final taskId = ref.read(importTasksProvider.notifier).startImport(filename);

    try {
      final importer = GtfsImporter(
        onProgress: (step, progress) {
          ref.read(importTasksProvider.notifier).updateProgress(
                taskId,
                step,
                progress,
              );
        },
      );

      await importer.import(projectId, path);

      ref.read(importTasksProvider.notifier).completeImport(taskId);
      ref.invalidate(gtfsFilesProvider);
    } catch (e) {
      ref.read(importTasksProvider.notifier).failImport(taskId, e.toString());
      rethrow;
    }
  }

  /// Import GTFS from bytes (web)
  Future<void> importFromBytes(
    int projectId,
    String filename,
    Uint8List bytes,
  ) async {
    final taskId = ref.read(importTasksProvider.notifier).startImport(filename);

    try {
      final importer = GtfsImporter(
        onProgress: (step, progress) {
          ref.read(importTasksProvider.notifier).updateProgress(
                taskId,
                step,
                progress,
              );
        },
      );

      await importer.importFromZipBytes(projectId, filename, bytes);

      ref.read(importTasksProvider.notifier).completeImport(taskId);
      ref.invalidate(gtfsFilesProvider);
    } catch (e) {
      ref.read(importTasksProvider.notifier).failImport(taskId, e.toString());
      rethrow;
    }
  }
}
