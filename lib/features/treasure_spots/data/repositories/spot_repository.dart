import 'package:fav_app/features/treasure_spots/data/models/treasure_spot.dart';

abstract class TreasureSpotRepository {
  Future<TreasureSpot> create(TreasureSpot spot);

  Future<TreasureSpot> update(TreasureSpot spot);

  Future<void> delete(String id);

  Future<TreasureSpot?> getById(String id);

  Future<List<TreasureSpot>> listAll();

  /// folderId 为 null 时列出未归类的点；
  /// 传空字符串或特定 id 时只列出该文件夹下的点。
  Future<List<TreasureSpot>> listByFolder(String? folderId);

  Future<List<TreasureSpot>> searchByName(String keyword);
}
