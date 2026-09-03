import 'package:flutter/material.dart';

/// 地点文件夹（同时支持两套命名：iconCode ↔ iconCodePoint，都指向同一个值）
class SpotFolder {
  final String id;
  final String name;
  final int iconCode; // Icons.xxx.codePoint
  final int colorValue; // Color.value (ARGB)
  final int sortOrder;
  final DateTime createdAt;

  SpotFolder({
    required this.id,
    required this.name,
    // 接受两种命名构造
    int? iconCode,
    int? iconCodePoint,
    required this.colorValue,
    this.sortOrder = 0,
    DateTime? createdAt,
  })  : iconCode = iconCode ?? iconCodePoint ?? Icons.folder.codePoint,
        createdAt = createdAt ?? DateTime.now();

  // =============== UI 友好 getters ===============
  int get iconCodePoint => iconCode;

  IconData get iconData => IconData(
        iconCode,
        fontFamily: 'MaterialIcons',
      );

  /// 任务要求的同名 getter
  IconData get icon => iconData;

  Color get color => Color(colorValue);

  // =============== JSON 序列化 ===============
  factory SpotFolder.fromJson(Map<String, dynamic> json) {
    return SpotFolder(
      id: json['id'] as String? ?? '',
      name: json['name'] as String? ?? '',
      iconCode: json['iconCode'] as int? ??
          json['iconCodePoint'] as int? ??
          Icons.folder.codePoint,
      colorValue: json['colorValue'] as int? ?? Colors.blue.value,
      sortOrder: json['sortOrder'] as int? ?? 0,
      createdAt: json['createdAt'] is int
          ? DateTime.fromMillisecondsSinceEpoch(json['createdAt'] as int)
          : DateTime.tryParse(json['createdAt'] as String? ?? '') ??
              DateTime.now(),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      'iconCode': iconCode,
      'iconCodePoint': iconCode,
      'colorValue': colorValue,
      'sortOrder': sortOrder,
      'createdAt': createdAt.millisecondsSinceEpoch,
    };
  }

  // =============== copyWith（接受 iconCode / iconCodePoint 任一种）===============
  SpotFolder copyWith({
    String? id,
    String? name,
    int? iconCode,
    int? iconCodePoint,
    int? colorValue,
    int? sortOrder,
    DateTime? createdAt,
  }) {
    return SpotFolder(
      id: id ?? this.id,
      name: name ?? this.name,
      iconCode: iconCode ?? iconCodePoint ?? this.iconCode,
      colorValue: colorValue ?? this.colorValue,
      sortOrder: sortOrder ?? this.sortOrder,
      createdAt: createdAt ?? this.createdAt,
    );
  }
}

/// DB row ↔ model 转换（Repository 使用）
class SpotFolderDbAdapter {
  static SpotFolder fromRow(Map<String, dynamic> row) {
    return SpotFolder(
      id: row['id'] as String,
      name: row['name'] as String,
      iconCode: row['icon_code'] as int? ?? 0,
      colorValue: row['color_value'] as int? ?? 0,
      sortOrder: row['sort_order'] as int? ?? 0,
      createdAt: DateTime.parse(row['created_at'] as String),
    );
  }

  static Map<String, dynamic> toRow(SpotFolder folder) {
    return {
      'id': folder.id,
      'name': folder.name,
      'icon_code': folder.iconCode,
      'color_value': folder.colorValue,
      'sort_order': folder.sortOrder,
      'created_at': folder.createdAt.toIso8601String(),
    };
  }
}

/// 文件夹图标预设：20 个 Material Icons
class FolderIconPresets {
  static const List<IconData> icons = [
    Icons.folder,
    Icons.favorite,
    Icons.fastfood,
    Icons.local_cafe,
    Icons.local_drink,
    Icons.restaurant,
    Icons.hotel,
    Icons.attractions,
    Icons.nature,
    Icons.nature_people,
    Icons.park,
    Icons.museum,
    Icons.shopping_bag,
    Icons.storefront,
    Icons.directions_car,
    Icons.directions_walk,
    Icons.wc,
    Icons.child_friendly,
    Icons.star,
    Icons.place,
  ];
}

/// 文件夹颜色预设：8 个 MaterialColor
class FolderColorPresets {
  static const List<Color> colors = [
    Colors.blue,
    Colors.green,
    Colors.orange,
    Colors.red,
    Colors.purple,
    Colors.teal,
    Colors.pink,
    Colors.amber,
  ];
}
