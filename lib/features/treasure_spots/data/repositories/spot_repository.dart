import 'package:fav_app/features/treasure_spots/data/models/treasure_spot.dart';

abstract class TreasureSpotRepository {
  Future<TreasureSpot> create(TreasureSpot spot);
  Future<TreasureSpot> update(TreasureSpot spot);
  Future<void> delete(String id);
  Future<TreasureSpot?> getById(String id);
  Future<List<TreasureSpot>> listAll();
  Future<List<TreasureSpot>> listByFolder(String? folderId);
  Future<List<TreasureSpot>> searchByName(String keyword);
}
