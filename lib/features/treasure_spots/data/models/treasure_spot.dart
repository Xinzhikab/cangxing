import 'dart:convert';

import 'package:flutter/material.dart';

enum PlaceType {
  restaurant,
  drink,
  entertainment,
  attraction,
  restroom,
  other,
}

class PlaceTypeInfo {
  final PlaceType type;
  final String key;
  final String label;
  final IconData icon;

  const PlaceTypeInfo({required this.type, required this.key, required this.label, required this.icon});
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

  static PlaceTypeInfo infoOf(PlaceType t) => all.firstWhere((e) => e.type == t, orElse: () => all.last);
  static PlaceTypeInfo infoOfKey(String? key) => infoOf(fromKey(key).type);
  static PlaceTypeInfo fromKey(String? key) => all.firstWhere((e) => e.key == key, orElse: () => all.last);
  static String label(PlaceType? t) => infoOf(t ?? PlaceType.other).label;
  static String keyOf(PlaceType? t) => infoOf(t ?? PlaceType.other).key;
  static String toSqlValue(PlaceType? t) => keyOf(t);
  static IconData icon(PlaceType? t) => infoOf(t ?? PlaceType.other).icon;
}

class TreasureSpot {
  final String id;
  final String name;
  final String address;
  final double? latitude;
  final double? longitude;
  final String placeType;
  final String? folderId;
  final List<String> tags;
  final String note;
  final List<String> images;
  final DateTime createdAt;
  final DateTime updatedAt;

  TreasureSpot({
    required this.id,
    required this.name,
    this.address = '',
    double? lat,
    double? lng,
    double? latitude,
    double? longitude,
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

  double? get lat => latitude;
  double? get lng => longitude;
  String get latLngText {
    if (latitude != null && longitude != null) {
      return '${latitude!.toStringAsFixed(5)}, ${longitude!.toStringAsFixed(5)}';
    }
    return '未设置坐标';
  }
  String get type => placeType;
  PlaceType get placeTypeEnum => PlaceTypeEnums.fromKey(placeType).type;

  factory TreasureSpot.fromJson(Map<String, dynamic> json) {
    return TreasureSpot(
      id: json['id'] as String? ?? '',
      name: json['name'] as String? ?? '',
      address: json['address'] as String? ?? '',
      latitude: (json['latitude'] as num?)?.toDouble() ?? (json['lat'] as num?)?.toDouble(),
      longitude: (json['longitude'] as num?)?.toDouble() ?? (json['lng'] as num?)?.toDouble(),
      placeType: (json['placeType'] as String?) ??
          (json['type'] != null ? PlaceTypeEnums.keyOf(PlaceType.values[(json['type'] as int?) ?? 5]) : 'other'),
      folderId: json['folderId'] as String?,
      tags: ((json['tags'] as List<dynamic>?) ?? const []).whereType<String>().toList(growable: false),
      note: json['note'] as String? ?? '',
      images: ((json['images'] as List<dynamic>?) ?? const []).whereType<String>().toList(growable: false),
      createdAt: json['createdAt'] is int
          ? DateTime.fromMillisecondsSinceEpoch(json['createdAt'] as int)
          : DateTime.tryParse(json['createdAt'] as String? ?? '') ?? DateTime.now(),
      updatedAt: json['updatedAt'] is int
          ? DateTime.fromMillisecondsSinceEpoch(json['updatedAt'] as int)
          : DateTime.tryParse(json['updatedAt'] as String? ?? '') ?? DateTime.now(),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id, 'name': name, 'address': address, 'latitude': latitude, 'longitude': longitude,
      'placeType': placeType, 'folderId': folderId, 'tags': tags, 'note': note, 'images': images,
      'createdAt': createdAt.millisecondsSinceEpoch, 'updatedAt': updatedAt.millisecondsSinceEpoch,
    };
  }

  TreasureSpot copyWith({
    String? id, String? name, String? address, double? lat, double? lng,
    double? latitude, double? longitude, bool clearLatitude = false, bool clearLongitude = false,
    PlaceType? type, String? placeType, String? folderId, bool clearFolderId = false,
    List<String>? tags, String? note, List<String>? images, DateTime? createdAt, DateTime? updatedAt,
  }) {
    return TreasureSpot(
      id: id ?? this.id, name: name ?? this.name, address: address ?? this.address,
      latitude: clearLatitude ? null : (latitude ?? lat ?? this.latitude),
      longitude: clearLongitude ? null : (longitude ?? lng ?? this.longitude),
      placeType: placeType ?? (type != null ? PlaceTypeEnums.keyOf(type) : this.placeType),
      folderId: clearFolderId ? null : (folderId ?? this.folderId),
      tags: tags ?? this.tags, note: note ?? this.note, images: images ?? this.images,
      createdAt: createdAt ?? this.createdAt, updatedAt: updatedAt ?? this.updatedAt,
    );
  }
}

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
      tags: ((jsonDecode(row['tags'] as String? ?? '[]') as List<dynamic>)).whereType<String>().toList(growable: false),
      note: row['note'] as String? ?? '',
      images: ((jsonDecode(row['images_json'] as String? ?? '[]') as List<dynamic>)).whereType<String>().toList(growable: false),
      createdAt: DateTime.parse(row['created_at'] as String),
      updatedAt: DateTime.parse(row['updated_at'] as String),
    );
  }

  static Map<String, dynamic> toRow(TreasureSpot spot) {
    return {
      'id': spot.id, 'name': spot.name, 'address': spot.address.isEmpty ? null : spot.address,
      'latitude': spot.latitude, 'longitude': spot.longitude, 'place_type': spot.placeType,
      'folder_id': spot.folderId, 'tags': jsonEncode(spot.tags), 'note': spot.note.isEmpty ? null : spot.note,
      'images_json': jsonEncode(spot.images), 'created_at': spot.createdAt.toIso8601String(),
      'updated_at': spot.updatedAt.toIso8601String(),
    };
  }
}
