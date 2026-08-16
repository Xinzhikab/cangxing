import 'package:uuid/uuid.dart';

import 'package:fav_app/features/collections/data/models/category.dart';
import 'package:fav_app/features/collections/data/repositories/category_repository.dart';

/// 推荐的文件夹分类模板：按「领域」划分，少而稳定；
/// 标签管「主题」（多而灵活），与文件夹互补。
const Map<String, String> kCategoryTemplate = {
  '游戏攻略': '游戏攻略、评测、配装（可再分单机/手游）',
  '数码评测': '手机、电脑、外设等硬件评测与购买参考',
  '电脑技巧': '系统设置、效率工具、故障排查',
  '软件工具': 'App/软件推荐、使用教程、配置分享',
  '教程学习': '编程、设计等成体系的学习资料',
  '杂谈娱乐': '杂谈、梗图、临时存放区',
};

/// 批量导入模板文件夹：跳过已存在的同名顶层文件夹。
/// 返回实际新建的文件夹数量。
Future<int> importCategoryTemplate(
  CategoryRepository repo,
  Iterable<String> names,
) async {
  await repo.ready;
  final existing = (await repo.listAll())
      .where((c) => c.parentId == null)
      .map((c) => c.name)
      .toSet();
  var order = existing.length;
  var created = 0;
  for (final name in names) {
    if (existing.contains(name)) continue;
    await repo.create(Category(
      id: const Uuid().v4(),
      name: name,
      parentId: null,
      sortOrder: order++,
      createdAt: DateTime.now(),
    ));
    created++;
  }
  return created;
}
