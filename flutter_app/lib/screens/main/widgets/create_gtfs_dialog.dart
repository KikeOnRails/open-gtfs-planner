import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_theme.dart';
import '../../../providers/project_providers.dart';
import '../../../providers/simulation_providers.dart';
import 'nap_browser_dialog.dart';
import 'create_gtfs_wizard.dart';

/// The action chosen by the user in the "Create GTFS" dialog.
enum CreateGtfsAction {
  importFromFile,
  createFromScratch,
  importFromNap,
}

/// Shows a bottom sheet or dialog with the 3 GTFS creation options.
Future<void> showCreateGtfsDialog(BuildContext context, WidgetRef ref) async {
  final project = ref.read(currentProjectProvider);
  if (project == null) return;

  final action = await showDialog<CreateGtfsAction>(
    context: context,
    builder: (ctx) => const _CreateGtfsOptionsDialog(),
  );

  if (action == null || !context.mounted) return;

  switch (action) {
    case CreateGtfsAction.importFromFile:
      await _handleImportFromFile(context, ref, project.id);
      break;
    case CreateGtfsAction.createFromScratch:
      if (context.mounted) {
        await showCreateGtfsWizard(context, ref, project.id);
      }
      break;
    case CreateGtfsAction.importFromNap:
      if (context.mounted) {
        await showNapBrowserDialog(context, ref, project.id);
      }
      break;
  }
}

/// Whether to import a ZIP file or a folder.
enum _ImportFileType { zip, folder }

Future<void> _handleImportFromFile(
    BuildContext context, WidgetRef ref, int projectId) async {
  if (kIsWeb) {
    // Web only supports ZIP files
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['zip'],
      withData: true,
      dialogTitle: 'Selecciona archivo GTFS (.zip)',
    );
    if (result == null || result.files.isEmpty) return;
    final bytes = result.files.first.bytes;
    if (bytes == null) return;

    _runImportFromBytes(
        context, ref, projectId, result.files.first.name, bytes);
  } else {
    // Desktop: ask the user what they want to open
    final choice = await showDialog<_ImportFileType>(
      context: context,
      builder: (ctx) => const _ImportFileTypeDialog(),
    );
    if (choice == null || !context.mounted) return;

    String? path;
    if (choice == _ImportFileType.zip) {
      final zipResult = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['zip'],
        dialogTitle: 'Selecciona archivo GTFS (.zip)',
      );
      if (zipResult != null && zipResult.files.isNotEmpty) {
        path = zipResult.files.first.path;
      }
    } else {
      path = await FilePicker.platform.getDirectoryPath(
        dialogTitle: 'Selecciona carpeta GTFS descomprimida',
      );
    }

    if (path == null) return;

    _runImport(context, ref, projectId, path);
  }
}

Future<void> _runImport(
    BuildContext context, WidgetRef ref, int projectId, String path) async {
  try {
    await ref.read(gtfsImportProvider).importFromPath(projectId, path);
    _afterImport(ref);
  } catch (e) {
    _showImportError(context, e);
  }
}

Future<void> _runImportFromBytes(BuildContext context, WidgetRef ref,
    int projectId, String filename, Uint8List bytes) async {
  try {
    await ref
        .read(gtfsImportProvider)
        .importFromBytes(projectId, filename, bytes);
    _afterImport(ref);
  } catch (e) {
    _showImportError(context, e);
  }
}

void _afterImport(WidgetRef ref) {
  ref.invalidate(activeServicesProvider);
  ref.invalidate(activeTripsProvider);
}

void _showImportError(BuildContext context, Object e) {
  if (context.mounted) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Error al importar GTFS: $e'),
        backgroundColor: Colors.red,
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Options dialog
// ---------------------------------------------------------------------------

class _CreateGtfsOptionsDialog extends StatelessWidget {
  const _CreateGtfsOptionsDialog();

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: AppTheme.surfaceVariant,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 480),
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Header
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: AppTheme.primary.withOpacity(0.15),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: const Icon(Icons.add_circle_outline,
                        color: AppTheme.primary, size: 24),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Crear GTFS',
                          style: Theme.of(context).textTheme.titleLarge,
                        ),
                        const SizedBox(height: 2),
                        Text(
                          'Elige cómo quieres añadir datos GTFS',
                          style: Theme.of(context).textTheme.bodySmall?.copyWith(
                                color: AppTheme.onSurfaceVariant,
                              ),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close, size: 20),
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                ],
              ),
              const SizedBox(height: 24),

              // Option 1: Import from file
              _OptionTile(
                icon: Icons.upload_file_outlined,
                title: 'Importar GTFS desde fichero',
                subtitle: 'Selecciona un archivo .zip o carpeta GTFS local',
                onTap: () =>
                    Navigator.of(context).pop(CreateGtfsAction.importFromFile),
              ),
              const SizedBox(height: 12),

              // Option 2: Create from scratch
              _OptionTile(
                icon: Icons.edit_note_outlined,
                title: 'Crear GTFS desde cero',
                subtitle:
                    'Inicia un asistente para introducir la información básica',
                onTap: () =>
                    Navigator.of(context).pop(CreateGtfsAction.createFromScratch),
              ),
              const SizedBox(height: 12),

              // Option 3: Import from repository
              _OptionTile(
                icon: Icons.cloud_download_outlined,
                title: 'Importar desde repositorio',
                subtitle: 'Busca y descarga GTFS del NAP (Mitma)',
                badge: 'NAP',
                onTap: () =>
                    Navigator.of(context).pop(CreateGtfsAction.importFromNap),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _OptionTile extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final String? badge;
  final VoidCallback onTap;

  const _OptionTile({
    required this.icon,
    required this.title,
    required this.subtitle,
    this.badge,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AppTheme.surface,
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: const Color(0xFF2E3340),
              width: 1,
            ),
          ),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: AppTheme.primary.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(icon, color: AppTheme.primary, size: 22),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            title,
                            style: Theme.of(context)
                                .textTheme
                                .titleSmall
                                ?.copyWith(fontWeight: FontWeight.w600),
                          ),
                        ),
                        if (badge != null)
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 8, vertical: 2),
                            decoration: BoxDecoration(
                              color: AppTheme.accent.withOpacity(0.15),
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: Text(
                              badge!,
                              style: const TextStyle(
                                color: AppTheme.accent,
                                fontSize: 10,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(
                      subtitle,
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            color: AppTheme.onSurfaceVariant,
                          ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              const Icon(Icons.chevron_right,
                  color: AppTheme.onSurfaceVariant, size: 20),
            ],
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Dialog to choose between ZIP file or folder import
// ---------------------------------------------------------------------------

class _ImportFileTypeDialog extends StatelessWidget {
  const _ImportFileTypeDialog();

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: AppTheme.surfaceVariant,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 400),
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: AppTheme.primary.withOpacity(0.15),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: const Icon(Icons.upload_file_outlined,
                        color: AppTheme.primary, size: 24),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Text(
                      'Importar GTFS desde fichero',
                      style: Theme.of(context).textTheme.titleLarge,
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close, size: 20),
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Text(
                '¿Qué tipo de fichero quieres importar?',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: AppTheme.onSurfaceVariant,
                    ),
              ),
              const SizedBox(height: 20),
              _OptionTile(
                icon: Icons.archive_outlined,
                title: 'Archivo ZIP',
                subtitle: 'Selecciona un archivo GTFS comprimido (.zip)',
                onTap: () =>
                    Navigator.of(context).pop(_ImportFileType.zip),
              ),
              const SizedBox(height: 12),
              _OptionTile(
                icon: Icons.folder_open_outlined,
                title: 'Carpeta descomprimida',
                subtitle:
                    'Selecciona una carpeta con los archivos GTFS (.txt)',
                onTap: () =>
                    Navigator.of(context).pop(_ImportFileType.folder),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
