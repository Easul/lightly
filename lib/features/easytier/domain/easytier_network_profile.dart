import 'easytier_config.dart';

class EasyTierNetworkProfile {
  const EasyTierNetworkProfile({
    required this.id,
    required this.name,
    required this.config,
    required this.createdAt,
    required this.updatedAt,
  });

  final String id;
  final String name;
  final EasyTierConfig config;
  final DateTime createdAt;
  final DateTime updatedAt;

  EasyTierNetworkProfile copyWith({
    String? id,
    String? name,
    EasyTierConfig? config,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) {
    return EasyTierNetworkProfile(
      id: id ?? this.id,
      name: name ?? this.name,
      config: config ?? this.config,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      'config': config.toJson(),
      'createdAt': createdAt.toIso8601String(),
      'updatedAt': updatedAt.toIso8601String(),
    };
  }

  factory EasyTierNetworkProfile.fromJson(Map<String, dynamic> json) {
    return EasyTierNetworkProfile(
      id: json['id'] as String? ?? '',
      name: json['name'] as String? ?? '未命名网络',
      config: EasyTierConfig.fromJson(
        Map<String, dynamic>.from(
          json['config'] as Map? ?? const <String, dynamic>{},
        ),
      ),
      createdAt:
          DateTime.tryParse(json['createdAt'] as String? ?? '') ??
          DateTime.now(),
      updatedAt:
          DateTime.tryParse(json['updatedAt'] as String? ?? '') ??
          DateTime.now(),
    );
  }
}
