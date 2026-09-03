import 'package:uuid/uuid.dart';
import 'package:fav_app/features/collections/data/services/database_service.dart';
import 'package:fav_app/features/treasure_spots/data/models/treasure_spot.dart';
import 'package:fav_app/features/treasure_spots/data/repositories/spot_repository.dart';

class TreasureSpotRepositoryImpl implements TreasureSpotRepository {
  final DatabaseService db;
  final Uuid _uuid = const Uuid();
  final void Function()? onChanged;

  TreasureSpotRepositoryImpl({
    required this.db,
    this.onChanged,
  });

  @override
  Future<TreasureSpot> create(TreasureSpot spot) async {
    final database = await db.database;
    final effectiveId = spot.id.isEmpty ? _uuid.v4() : spot.id;
    final now = DateTime.now();
    final effectiveSpot = spot.id.isEmpty
        ? spot.copyWith(id: effectiveId, createdAt: now, updatedAt: now)
        : spot.copyWith(updatedAt: now);
    await database.insert(
      'treasure_spots',
      TreasureSpotDbAdapter.toRow(effectiveSpot),
    );
    onChanged?.call();
    return effectiveSpot;
  }

  @override
  Future<TreasureSpot> update(TreasureSpot spot) async {
    final database = await db.database;
    final effectiveSpot = spot.copyWith(updatedAt: DateTime.now());
    await database.update(
      'treasure_spots',
      TreasureSpotDbAdapter.toRow(effectiveSpot),
      where: 'id = ?',
      whereArgs: [spot.id],
    );
    onChanged?.call();
    return effectiveSpot;
  }

  @override
  Future<void> delete(String id) async {
    final database = await db.database;
    await database.delete(
      'treasure_spots',
      where: 'id = ?',
      whereArgs: [id],
    );
    onChanged?.call();
  }

  @override
  Future<TreasureSpot?> getById(String id) async {
    final database = await db.database;
    final rows = await database.query(
      'treasure_spots',
      where: 'id = ?',
      whereArgs: [id],
      limit: 1,
    );
    if (rows.isEmpty) return null;
    return TreasureSpotDbAdapter.fromRow(rows.first);
  }

  @override
  Future<List<TreasureSpot>> listAll() async {
    final database = await db.database;
    final rows = await database.query(
      'treasure_spots',
      orderBy: 'updated_at DESC, created_at DESC',
    );
    return rows.map(TreasureSpotDbAdapter.fromRow).toList();
  }

  @override
  Future<List<TreasureSpot>> listByFolder(String? folderId) async {
    final database = await db.database;
    final List<Map<String, dynamic>> rows;
    if (folderId == null) {
      // null 文件夹：列出 folder_id IS NULL 的未归类藏宝点
      rows = await database.query(
        'treasure_spots',
        where: 'folder_id IS NULL',
        orderBy: 'updated_at DESC, created_at DESC',
      );
    } else {
      rows = await database.query(
        'treasure_spots',
        where: 'folder_id = ?',
        whereArgs: [folderId],
        orderBy: 'updated_at DESC, created_at DESC',
      );
    }
    return rows.map(TreasureSpotDbAdapter.fromRow).toList();
  }

  @override
  Future<List<TreasureSpot>> searchByName(String keyword) async {
    final database = await db.database;
    final kw = keyword.trim();
    if (kw.isEmpty) return const [];
    final like = '%$kw%';
    final rows = await database.query(
      'treasure_spots',
      where: 'name LIKE ? OR address LIKE ? OR note LIKE ?',
      whereArgs: [like, like, like],
      orderBy: 'updated_at DESC',
    );
    return rows.map(TreasureSpotDbAdapter.fromRow).toList();
  }
}
