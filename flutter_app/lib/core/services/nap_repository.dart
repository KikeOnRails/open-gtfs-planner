import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

/// Model representing a GTFS dataset from the NAP (Mitma) repository.
class NapGtfsDataset {
  final int conjuntoDatoId;
  final String nombre;
  final String? descripcion;
  final List<NapTransportType> tiposTransporte;
  final List<NapFichero> ficheros;
  final String? organizacionNombre;
  final List<NapRegion> regiones;
  final List<NapOperador> operadores;

  const NapGtfsDataset({
    required this.conjuntoDatoId,
    required this.nombre,
    this.descripcion,
    required this.tiposTransporte,
    required this.ficheros,
    this.organizacionNombre,
    required this.regiones,
    required this.operadores,
  });

  /// The first GTFS-ZIP file ID, if available.
  int? get primaryFicheroId {
    final gtfsFiles =
        ficheros.where((f) => f.tipoFicheroNombre == 'GTFS-ZIP').toList();
    if (gtfsFiles.isEmpty) return null;
    return gtfsFiles.first.ficheroId;
  }

  /// Summary info about the primary file.
  NapFichero? get primaryFichero {
    final gtfsFiles =
        ficheros.where((f) => f.tipoFicheroNombre == 'GTFS-ZIP').toList();
    if (gtfsFiles.isEmpty) return null;
    return gtfsFiles.first;
  }

  /// Human-readable transport types.
  String get transportTypesText =>
      tiposTransporte.map((t) => t.nombre).join(', ');

  /// Human-readable regions.
  String get regionesText => regiones.map((r) => r.nombre).join(', ');

  factory NapGtfsDataset.fromJson(Map<String, dynamic> json) {
    return NapGtfsDataset(
      conjuntoDatoId: json['conjuntoDatoId'] as int,
      nombre: (json['nombre'] as String? ?? '').trim(),
      descripcion: json['descripcion'] as String?,
      tiposTransporte: (json['tiposTransporte'] as List<dynamic>? ?? [])
          .map((t) => NapTransportType.fromJson(t as Map<String, dynamic>))
          .toList(),
      ficheros: (json['ficherosDto'] as List<dynamic>? ?? [])
          .map((f) => NapFichero.fromJson(f as Map<String, dynamic>))
          .toList(),
      organizacionNombre: (json['organizacion']
          as Map<String, dynamic>?)?['nombre'] as String?,
      regiones: (json['regiones'] as List<dynamic>? ?? [])
          .map((r) => NapRegion.fromJson(r as Map<String, dynamic>))
          .toList(),
      operadores: (json['operadores'] as List<dynamic>? ?? [])
          .map((o) => NapOperador.fromJson(o as Map<String, dynamic>))
          .toList(),
    );
  }
}

class NapTransportType {
  final int tipoTransporteId;
  final String nombre;

  const NapTransportType({
    required this.tipoTransporteId,
    required this.nombre,
  });

  factory NapTransportType.fromJson(Map<String, dynamic> json) {
    return NapTransportType(
      tipoTransporteId: json['tipoTransporteId'] as int,
      nombre: json['nombre'] as String? ?? '',
    );
  }
}

class NapFichero {
  final int ficheroId;
  final String tipoFicheroNombre;
  final int? numeroViajes;
  final int? numeroRutas;
  final int? numeroParadas;
  final int? tamanio;
  final bool validado;
  final String? fechaActualizacion;

  const NapFichero({
    required this.ficheroId,
    required this.tipoFicheroNombre,
    this.numeroViajes,
    this.numeroRutas,
    this.numeroParadas,
    this.tamanio,
    required this.validado,
    this.fechaActualizacion,
  });

  String get sizeText {
    if (tamanio == null) return '';
    if (tamanio! < 1024) return '$tamanio B';
    if (tamanio! < 1024 * 1024) return '${(tamanio! / 1024).toStringAsFixed(1)} KB';
    return '${(tamanio! / (1024 * 1024)).toStringAsFixed(1)} MB';
  }

  factory NapFichero.fromJson(Map<String, dynamic> json) {
    return NapFichero(
      ficheroId: json['ficheroId'] as int,
      tipoFicheroNombre: json['tipoFicheroNombre'] as String? ?? '',
      numeroViajes: json['numeroViajes'] as int?,
      numeroRutas: json['numeroRutas'] as int?,
      numeroParadas: json['numeroParadas'] as int?,
      tamanio: json['tamanio'] as int?,
      validado: json['validado'] as bool? ?? false,
      fechaActualizacion: json['fechaActualizacion'] as String?,
    );
  }
}

class NapRegion {
  final int regionId;
  final String nombre;
  final String? tipoNombre;

  const NapRegion({
    required this.regionId,
    required this.nombre,
    this.tipoNombre,
  });

  factory NapRegion.fromJson(Map<String, dynamic> json) {
    return NapRegion(
      regionId: json['regionId'] as int,
      nombre: json['nombre'] as String? ?? '',
      tipoNombre: json['tipoNombre'] as String?,
    );
  }
}

class NapOperador {
  final int operadorId;
  final String nombre;
  final String? url;

  const NapOperador({
    required this.operadorId,
    required this.nombre,
    this.url,
  });

  factory NapOperador.fromJson(Map<String, dynamic> json) {
    return NapOperador(
      operadorId: json['operadorId'] as int,
      nombre: json['nombre'] as String? ?? '',
      url: json['url'] as String?,
    );
  }
}

/// Service for interacting with the NAP (Mitma) GTFS repository.
class NapRepositoryService {
  static const String _baseUrl = 'https://nap.mitma.es/api/Fichero';
  static const String _apiKey = 'fc710ae6-45cb-4924-9602-bde8b9ef12bf';

  static Map<String, String> get _headers => {
        'ApiKey': _apiKey,
      };

  /// Cached datasets list.
  static List<NapGtfsDataset>? _cachedDatasets;

  /// Fetch all available GTFS datasets from the NAP.
  static Future<List<NapGtfsDataset>> getDatasets({bool forceRefresh = false}) async {
    if (_cachedDatasets != null && !forceRefresh) {
      return _cachedDatasets!;
    }

    final uri = Uri.parse('$_baseUrl/GetList');
    final response = await http.get(uri, headers: _headers);

    if (response.statusCode == 200 || response.statusCode == 301 || response.statusCode == 302) {
      // Handle redirects manually if needed
      final body = response.body;
      final json = jsonDecode(body) as Map<String, dynamic>;
      final items = json['conjuntosDatoDto'] as List<dynamic>? ?? [];
      _cachedDatasets = items
          .map((item) => NapGtfsDataset.fromJson(item as Map<String, dynamic>))
          .where((d) => d.primaryFicheroId != null) // Only datasets with GTFS files
          .toList();
      return _cachedDatasets!;
    }

    throw Exception(
        'Error al obtener datos del NAP: ${response.statusCode}');
  }

  /// Download a GTFS ZIP file by its ficheroId.
  /// Returns the raw bytes of the ZIP file.
  static Future<Uint8List> downloadFile(int ficheroId) async {
    final uri = Uri.parse('$_baseUrl/download/$ficheroId');
    final response = await http.get(uri, headers: _headers);

    if (response.statusCode == 200) {
      return response.bodyBytes;
    }

    throw Exception(
        'Error al descargar fichero del NAP: ${response.statusCode}');
  }

  /// Search datasets by name, description, region, or organization.
  static Future<List<NapGtfsDataset>> search(String query) async {
    final datasets = await getDatasets();
    if (query.isEmpty) return datasets;

    final lowerQuery = query.toLowerCase();
    return datasets.where((d) {
      return d.nombre.toLowerCase().contains(lowerQuery) ||
          (d.descripcion?.toLowerCase().contains(lowerQuery) ?? false) ||
          (d.organizacionNombre?.toLowerCase().contains(lowerQuery) ?? false) ||
          d.regiones.any((r) => r.nombre.toLowerCase().contains(lowerQuery)) ||
          d.operadores.any((o) => o.nombre.toLowerCase().contains(lowerQuery)) ||
          d.tiposTransporte
              .any((t) => t.nombre.toLowerCase().contains(lowerQuery));
    }).toList();
  }

  /// Clear the cached datasets.
  static void clearCache() {
    _cachedDatasets = null;
  }
}
