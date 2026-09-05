import 'package:fav_app/features/treasure_spots/data/models/spot_folder.dart';

abstract class SpotFolderRepository {
  Future<SpotFolder> create(SpotFolder folder);
  Future<SpotFolder> update(SpotFolder folder);
  Future<void> delete(String id);
  Future<List<SpotFolder>> listAll();
  Future<SpotFolder?> getById(String id);
}
