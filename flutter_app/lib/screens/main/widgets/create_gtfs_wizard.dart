import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/database/app_database.dart';
import '../../../core/database/gtfs_repository.dart';
import '../../../core/theme/app_theme.dart';
import '../../../providers/project_providers.dart';
import '../../../providers/simulation_providers.dart';

/// Shows a wizard dialog to create a GTFS file from scratch
/// with basic agency information.
Future<void> showCreateGtfsWizard(
    BuildContext context, WidgetRef ref, int projectId) async {
  final result = await showDialog<bool>(
    context: context,
    barrierDismissible: false,
    builder: (ctx) => _CreateGtfsWizardDialog(projectId: projectId),
  );

  if (result == true) {
    ref.invalidate(gtfsFilesProvider);
    ref.invalidate(activeServicesProvider);
    ref.invalidate(activeTripsProvider);
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('GTFS creado correctamente'),
          backgroundColor: AppTheme.primary,
        ),
      );
    }
  }
}

class _CreateGtfsWizardDialog extends StatefulWidget {
  final int projectId;

  const _CreateGtfsWizardDialog({required this.projectId});

  @override
  State<_CreateGtfsWizardDialog> createState() =>
      _CreateGtfsWizardDialogState();
}

class _CreateGtfsWizardDialogState extends State<_CreateGtfsWizardDialog> {
  final _formKey = GlobalKey<FormState>();

  // GTFS file name
  final _gtfsNameController = TextEditingController(text: 'Nuevo GTFS');

  // Agency fields
  final _agencyIdController = TextEditingController();
  final _agencyNameController = TextEditingController();
  final _agencyUrlController = TextEditingController();
  final _agencyTimezoneController =
      TextEditingController(text: 'Europe/Madrid');
  final _agencyLangController = TextEditingController(text: 'es');

  bool _isCreating = false;

  @override
  void dispose() {
    _gtfsNameController.dispose();
    _agencyIdController.dispose();
    _agencyNameController.dispose();
    _agencyUrlController.dispose();
    _agencyTimezoneController.dispose();
    _agencyLangController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: AppTheme.surfaceVariant,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 520, maxHeight: 600),
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
                    child: const Icon(Icons.edit_note_outlined,
                        color: AppTheme.primary, size: 24),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Crear GTFS desde cero',
                          style: Theme.of(context).textTheme.titleLarge,
                        ),
                        const SizedBox(height: 2),
                        Text(
                          'Introduce la información básica de la agencia',
                          style:
                              Theme.of(context).textTheme.bodySmall?.copyWith(
                                    color: AppTheme.onSurfaceVariant,
                                  ),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close, size: 20),
                    onPressed: _isCreating
                        ? null
                        : () => Navigator.of(context).pop(false),
                  ),
                ],
              ),
              const SizedBox(height: 24),

              // Form
              Flexible(
                child: SingleChildScrollView(
                  child: Form(
                    key: _formKey,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // GTFS Name
                        Text(
                          'Nombre del GTFS',
                          style:
                              Theme.of(context).textTheme.titleSmall?.copyWith(
                                    color: AppTheme.onSurfaceVariant,
                                    fontWeight: FontWeight.w600,
                                  ),
                        ),
                        const SizedBox(height: 8),
                        TextFormField(
                          controller: _gtfsNameController,
                          decoration: const InputDecoration(
                            hintText: 'Ej: Transporte urbano de mi ciudad',
                          ),
                          validator: (v) => v == null || v.trim().isEmpty
                              ? 'Campo obligatorio'
                              : null,
                        ),

                        const SizedBox(height: 20),
                        const Divider(color: Color(0xFF2E3340)),
                        const SizedBox(height: 12),

                        Text(
                          'Agencia de transporte',
                          style:
                              Theme.of(context).textTheme.titleSmall?.copyWith(
                                    color: AppTheme.primary,
                                    fontWeight: FontWeight.w600,
                                  ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          'Datos de agency.txt del estándar GTFS',
                          style:
                              Theme.of(context).textTheme.bodySmall?.copyWith(
                                    color: AppTheme.onSurfaceVariant,
                                  ),
                        ),
                        const SizedBox(height: 16),

                        // Agency ID
                        TextFormField(
                          controller: _agencyIdController,
                          decoration: const InputDecoration(
                            labelText: 'agency_id',
                            hintText: 'Ej: AGC001',
                          ),
                        ),
                        const SizedBox(height: 12),

                        // Agency Name (required)
                        TextFormField(
                          controller: _agencyNameController,
                          decoration: const InputDecoration(
                            labelText: 'agency_name *',
                            hintText: 'Ej: Empresa Municipal de Transportes',
                          ),
                          validator: (v) => v == null || v.trim().isEmpty
                              ? 'El nombre de la agencia es obligatorio'
                              : null,
                        ),
                        const SizedBox(height: 12),

                        // Agency URL
                        TextFormField(
                          controller: _agencyUrlController,
                          decoration: const InputDecoration(
                            labelText: 'agency_url',
                            hintText: 'Ej: https://www.emt.es',
                          ),
                        ),
                        const SizedBox(height: 12),

                        // Agency Timezone
                        TextFormField(
                          controller: _agencyTimezoneController,
                          decoration: const InputDecoration(
                            labelText: 'agency_timezone',
                            hintText: 'Ej: Europe/Madrid',
                          ),
                        ),
                        const SizedBox(height: 12),

                        // Agency Language
                        TextFormField(
                          controller: _agencyLangController,
                          decoration: const InputDecoration(
                            labelText: 'agency_lang',
                            hintText: 'Ej: es',
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),

              const SizedBox(height: 24),

              // Actions
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton(
                    onPressed: _isCreating
                        ? null
                        : () => Navigator.of(context).pop(false),
                    child: const Text('Cancelar'),
                  ),
                  const SizedBox(width: 12),
                  ElevatedButton.icon(
                    onPressed: _isCreating ? null : _createGtfs,
                    icon: _isCreating
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: Colors.white,
                            ),
                          )
                        : const Icon(Icons.check, size: 18),
                    label: Text(_isCreating ? 'Creando...' : 'Crear GTFS'),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _createGtfs() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => _isCreating = true);

    try {
      final gtfsName = _gtfsNameController.text.trim();

      // Create the GTFS file record
      final gtfsFile = await GtfsRepository.createGtfsFile(
        widget.projectId,
        gtfsName,
        'created_from_scratch',
      );

      // Insert the agency
      final db = await AppDatabase.instance;
      await db.insert('gtfs_agencies', {
        'gtfs_file_id': gtfsFile.id,
        'agency_id': _agencyIdController.text.trim().isEmpty
            ? null
            : _agencyIdController.text.trim(),
        'agency_name': _agencyNameController.text.trim(),
        'agency_url': _agencyUrlController.text.trim().isEmpty
            ? null
            : _agencyUrlController.text.trim(),
        'agency_timezone': _agencyTimezoneController.text.trim().isEmpty
            ? null
            : _agencyTimezoneController.text.trim(),
      });

      if (mounted) {
        Navigator.of(context).pop(true);
      }
    } catch (e) {
      setState(() => _isCreating = false);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error al crear GTFS: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }
}
