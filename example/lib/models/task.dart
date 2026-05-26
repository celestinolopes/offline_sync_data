/// Modelo de domínio espelhado no JSON do json-server (`db.json`).
class Task {
  const Task({
    required this.id,
    required this.title,
    required this.updatedAt,
    this.completed = false,
  });

  final String id;
  final String title;
  final DateTime updatedAt;
  final bool completed;

  factory Task.fromJson(Map<String, dynamic> json) => Task(
        id: json['id'] as String,
        title: json['title'] as String,
        completed: json['completed'] as bool? ?? false,
        updatedAt: DateTime.parse(json['updatedAt'] as String),
      );

  factory Task.newLocal({required String title}) => Task(
        id: DateTime.now().microsecondsSinceEpoch.toString(),
        title: title,
        updatedAt: DateTime.now().toUtc(),
      );

  Task copyWith({bool? completed}) => Task(
        id: id,
        title: title,
        completed: completed ?? this.completed,
        updatedAt: DateTime.now().toUtc(),
      );

  Map<String, dynamic> toJson() => <String, dynamic>{
        'id': id,
        'title': title,
        'completed': completed,
        'updatedAt': updatedAt.toIso8601String(),
      };
}
