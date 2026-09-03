import 'dart:convert';

import 'package:flutter/material.dart';

/// 地点类型枚举（UI 使用）
enum PlaceType {
  restaurant, // 饭店
  drink, // 饮品
  entertainment, // 娱乐
  attraction, // 景点
  restroom, // 卫生间
  other, // 其他
}

/// PlaceType 的中文标签、图标辅助信息
class PlaceTypeInfo {
  final PlaceType type;
  final String key; // 对应 placeType String
  final String label;
  final IconData icon;

  const PlaceTypeInfo({
    required this.type,
    required this.key,
    required this.label,
    required this.icon,
  });
}

class PlaceTypeEnums {
  static const List<PlaceTypeInfo> all = [
    PlaceTypeInfo(type: PlaceType.restaurant, key: 'restaurant', label: '饭店', icon: Icons.restaurant),
    PlaceTypeInfo(type: PlaceType.drink, key: 'drink', label: '饮品', icon: Icons.local_cafe),
    PlaceTypeInfo(type: PlaceType.entertainment, key: 'entertainment', label: '娱乐', icon: Icons.sports_esports),
    PlaceTypeInfo(type: PlaceType.attraction, key: 'attraction', label: '景点', icon: Icons.attractions),
    PlaceTypeInfo(type: PlaceType.restroom, key: 'restroom', label: '卫生间', icon: Icons.wc),
    PlaceTypeInfo(type: PlaceType.other, key: 'other', label: '其他', icon: Icons.place),
  ];

  static PlaceTypeInfo infoOf(PlaceType t) =>
      all.firstWhere((e) => e.type == t, orElse: () => all.last);

  /// 通过 sql 字符串 key 查找 PlaceTypeInfo（兼容 UI 调用）
  static PlaceTypeInfo infoOfKey(String? key) =>
      infoOf(fromKey(key).type);

  static PlaceTypeInfo fromKey(String? key) =>
      all.firstWhere((e) => e.key == key, orElse: () => all.last);

  static String label(PlaceType? t) => infoOf(t ?? PlaceType.other).label;

  static String keyOf(PlaceType? t) => infoOf(t ?? PlaceType.other).key;

  /// 任务要求的同名方法：PlaceType 枚举 → DB 存储的 sql 字符串
  static String toSqlValue(PlaceType? t) => keyOf(t);

  static IconData icon(PlaceType? t) => infoOf(t ?? PlaceType.other).icon;
}

/// 宝藏地点（同时兼容 Repository 和 UI 两套命名：latitude↔lat / longitude↔lng / placeType:String↔type:PlaceType）
class TreasureSpot {
  final String id;
  final String name;
  final String address;
  final double? latitude;
  final double? longitude;
  final String placeType; // 存库用：'restaurant' | 'drink' | ...
  final String? folderId;
  final List<String> tags;
  final String note;
  final List<String> images;
  final DateTime createdAt;
  final DateTime updatedAt;

  /// UI 便捷构造函数
  TreasureSpot({
    required this.id,
    required this.name,
    this.address = '',
    // 经纬度接受两种命名
    double? lat,
    double? lng,
    double? latitude,
    double? longitude,
    // 类型接受两种形式
    PlaceType? type,
    String? placeType,
    this.folderId,
    this.tags = const [],
    this.note = '',
    this.images = const [],
    DateTime? createdAt,
    DateTime? updatedAt,
  })  : latitude = latitude ?? lat,
        longitude = longitude ?? lng,
        placeType = placeType ?? PlaceTypeEnums.keyOf(type ?? PlaceType.other),
        createdAt = createdAt ?? DateTime.now(),
        updatedAt = updatedAt ?? DateTime.now();

  // =============== UI 友好 getters ===============
  double? get lat => latitude;
  double? get lng => longitude;

  /// 经纬度文本，未设置时返回「未设置坐标」
  String get latLngText {
    if (latitude != null && longitude != null) {
      return '${latitude!.toStringAsFixed(5)}, ${longitude!.toStringAsFixed(5)}';
    }
    return '未设置坐标';
  }

  /// 任务要求：返回 sql 字符串形式的 type（与 placeType 字段相同）
  String get type => placeType;

  /// 兼容枚举形式（供旧代码使用，UI 修改时可逐步替换）
  PlaceType get placeTypeEnum => PlaceTypeEnums.fromKey(placeType).type;

  // =============== JSON 序列化（shared_preferences 用）===============
  factory TreasureSpot.fromJson(Map<String, dynamic> json) {
    return TreasureSpot(
      id: json['id'] as String? ?? '',
      name: json['name'] as String? ?? '',
      address: json['address'] as String? ?? '',
      latitude: (json['latitude'] as num?)?.toDouble() ??
          (json['lat'] as num?)?.toDouble(),
      longitude: (json['longitude'] as num?)?.toDouble() ??
          (json['lng'] as num?)?.toDouble(),
      placeType: (json['placeType'] as String?) ??
          (json['type'] != null ? PlaceTypeEnums.keyOf(PlaceType.values[(json['type'] as int?) ?? 5]) : 'other'),
      folderId: json['folderId'] as String?,
      tags: ((json['tags'] as List<dynamic>?) ?? const [])
          .whereType<String>()
          .toList(growable: false),
      note: json['note'] as String? ?? '',
      images: ((json['images'] as List<dynamic>?) ?? const [])
          .whereType<String>()
          .toList(growable: false),
      createdAt: json['createdAt'] is int
          ? DateTime.fromMillisecondsSinceEpoch(json['createdAt'] as int)
          : DateTime.tryParse(json['createdAt'] as String? ?? '') ??
              DateTime.now(),
      updatedAt: json['updatedAt'] is int
          ? DateTime.fromMillisecondsSinceEpoch(json['updatedAt'] as int)
          : DateTime.tryParse(json['updatedAt'] as String? ?? '') ??
              DateTime.now(),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      'address': address,
      'latitude': latitude,
      'longitude': longitude,
      'placeType': placeType,
      'folderId': folderId,
      'tags': tags,
      'note': note,
      'images': images,
      'createdAt': createdAt.millisecondsSinceEpoch,
      'updatedAt': updatedAt.millisecondsSinceEpoch,
    };
  }

  // =============== copyWith（接受两种命名参数）===============
  TreasureSpot copyWith({
    String? id,
    String? name,
    String? address,
    double? lat,
    double? lng,
    double? latitude,
    double? longitude,
    bool clearLatitude = false,
    bool clearLongitude = false,
    PlaceType? type,
    String? placeType,
    String? folderId,
    bool clearFolderId = false,
    List<String>? tags,
    String? note,
    List<String>? images,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) {
    return TreasureSpot(
      id: id ?? this.id,
      name: name ?? this.name,
      address: address ?? this.address,
      latitude: clearLatitude
          ? null
          : (latitude ?? lat ?? this.latitude),
      longitude: clearLongitude
          ? null
          : (longitude ?? lng ?? this.longitude),
      placeType: placeType ??
          (type != null ? PlaceTypeEnums.keyOf(type) : this.placeType),
      folderId: clearFolderId ? null : (folderId ?? this.folderId),
      tags: tags ?? this.tags,
      note: note ?? this.note,
      images: images ?? this.images,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }
}

/// DB row ↔ model 转换（Repository 使用）
class TreasureSpotDbAdapter {
  static TreasureSpot fromRow(Map<String, dynamic> row) {
    return TreasureSpot(
      id: row['id'] as String,
      name: row['name'] as String,
      address: row['address'] as String? ?? '',
      latitude: (row['latitude'] as num?)?.toDouble(),
      longitude: (row['longitude'] as num?)?.toDouble(),
      placeType: row['place_type'] as String? ?? 'other',
      folderId: row['folder_id'] as String?,
      tags: ((jsonDecode(row['tags'] as String? ?? '[]') as List<dynamic>))
          .whereType<String>()
          .toList(growable: false),
      note: row['note'] as String? ?? '',
      images:
          ((jsonDecode(row['images_json'] as String? ?? '[]') as List<dynamic>))
              .whereType<String>()
              .toList(growable: false),
      createdAt: DateTime.parse(row['created_at'] as String),
      updatedAt: DateTime.parse(row['updated_at'] as String),
    );
  }

  static Map<String, dynamic> toRow(TreasureSpot spot) {
    return {
      'id': spot.id,
      'name': spot.name,
      'address': spot.address.isEmpty ? null : spot.address,
      'latitude': spot.latitude,
      'longitude': spot.longitude,
      'place_type': spot.placeType,
      'folder_id': spot.folderId,
      'tags': jsonEncode(spot.tags),
      'note': spot.note.isEmpty ? null : spot.note,
      'images_json': jsonEncode(spot.images),
      'created_at': spot.createdAt.toIso8601String(),
      'updated_at': spot.updatedAt.toIso8601String(),
    };
  }
}
