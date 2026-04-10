class ProjectModel {
  final int id;
  final String name;
  final DateTime createdAt;

  const ProjectModel({
    required this.id,
    required this.name,
    required this.createdAt,
  });

  factory ProjectModel.fromMap(Map<String, dynamic> map) {
    return ProjectModel(
      id: map['id'] as int,
      name: map['name'] as String,
      createdAt: DateTime.parse(map['created_at'] as String),
    );
  }

  Map<String, dynamic> toMap() => {
        'name': name,
        'created_at': createdAt.toIso8601String(),
      };

  ProjectModel copyWith({int? id, String? name, DateTime? createdAt}) =>
      ProjectModel(
        id: id ?? this.id,
        name: name ?? this.name,
        createdAt: createdAt ?? this.createdAt,
      );
}
