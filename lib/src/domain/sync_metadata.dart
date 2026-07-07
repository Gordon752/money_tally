import 'json_helpers.dart';

class SyncMetadata {
  const SyncMetadata({
    required this.createdAt,
    required this.updatedAt,
    required this.deviceId,
    this.deletedAt,
    this.version = 1,
  });

  factory SyncMetadata.fresh({DateTime? now, String deviceId = 'local'}) {
    final timestamp = now ?? DateTime.now().toUtc();
    return SyncMetadata(
      createdAt: timestamp,
      updatedAt: timestamp,
      deviceId: deviceId,
    );
  }

  final DateTime createdAt;
  final DateTime updatedAt;
  final DateTime? deletedAt;
  final String deviceId;
  final int version;

  bool get isDeleted => deletedAt != null;

  SyncMetadata touched({DateTime? now, String? deviceId}) {
    return SyncMetadata(
      createdAt: createdAt,
      updatedAt: now ?? DateTime.now().toUtc(),
      deletedAt: deletedAt,
      deviceId: deviceId ?? this.deviceId,
      version: version + 1,
    );
  }

  SyncMetadata deleted({DateTime? now, String? deviceId}) {
    final timestamp = now ?? DateTime.now().toUtc();
    return SyncMetadata(
      createdAt: createdAt,
      updatedAt: timestamp,
      deletedAt: timestamp,
      deviceId: deviceId ?? this.deviceId,
      version: version + 1,
    );
  }

  Map<String, Object?> toJson() {
    return {
      'createdAt': createdAt.toIso8601String(),
      'updatedAt': updatedAt.toIso8601String(),
      'deletedAt': deletedAt?.toIso8601String(),
      'deviceId': deviceId,
      'version': version,
    };
  }

  factory SyncMetadata.fromJson(Map<String, Object?> json) {
    return SyncMetadata(
      createdAt: dateTimeFromJson(json['createdAt']),
      updatedAt: dateTimeFromJson(json['updatedAt']),
      deletedAt: json['deletedAt'] == null
          ? null
          : dateTimeFromJson(json['deletedAt']),
      deviceId: json['deviceId'] as String? ?? 'local',
      version: json['version'] as int? ?? 1,
    );
  }
}
