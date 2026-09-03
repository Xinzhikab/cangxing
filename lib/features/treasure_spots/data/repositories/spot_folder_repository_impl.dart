import 'package:sqflite/sqflite.dart';
import 'package:uuid/uuid.dart';
import 'package:fav_app/features/collections/data/services/database_service.dart';
import 'package:fav_app/features/treasure_spots/data/models/spot_folder.dart';
import 'package:fav_app/features/treasure_spots/data/repositories/spot_folder_repository.dart';

class SpotFolderRepositoryImpl implements SpotFolderRepository {
  final DatabaseService db;
  final Uuid _uuid = const Uuid();
  final void Function()? onChanged;

  SpotFolderRepositoryImpl({
    required this.db,
    this.onChanged,
  });

  @override
  Future<SpotFolder> create(SpotFolder folder) async {
    final database = await db.database;
    final effectiveId = folder.id.isEmpty ? _uuid.v4() : folder.id;
    final effectiveFolder =
        folder.id.isEmpty ? folder.copyWith(id: effectiveId) : folder;
    await database.insert(
      'spot_folders',
      SpotFolderDbAdapter.toRow(effectiveFolder),
    );
    onChanged?.call();
    return effectiveFolder;
  }

  @override
  Future<SpotFolder> update(SpotFolder folder) async {
    final database = await db.database;
    await database.update(
      'spot_folders',
      SpotFolderDbAdapter.toRow(folder),
      where: 'id = ?',
      whereArgs: [folder.id],
    );
    onChanged?.call();
    return folder;
  }

  @override
  Future<void> delete(String id) async {
    final database = await db.database;
    await database.transaction((txn) async {
      // 文件夹被删除后，其下藏宝点回退到「未归类」(folder_id = NULL)
      await txn.update(
        'treasure_spots',
        {'folder_id': null},
        where: 'folder_id = ?',
        whereArgs: [id],
      );
      await txn.delete(
        'spot_folders',
        where: 'id = ?',
        whereArgs: [id],
      );
    });
    onChanged?.call();
  }

  @override
  Future<List<SpotFolder>> listAll() async {
    final database = await db.database;
    final rows = await database.query(
      'spot_folders',
      orderBy: 'sort_order ASC, created_at ASC',
    );
    return rows.map(SpotFolderDbAdapter.fromRow).toList();
  }

  @override
  Future<SpotFolder?> getById(String id) async {
    final database = await db.database;
    final rows = await database.query(
      'spot_folders',
      where: 'id = ?',
      whereArgs: [id],
      limit: 1,
    );
    if (rows.isEmpty) return null;
    return SpotFolderDbAdapter.fromRow(rows.first);
  }
}
