class CollectionNote {
  final String id;
  final String collectionId;
  final String content;
  final DateTime createdAt;

  const CollectionNote({
    required this.id,
    required this.collectionId,
    required this.content,
    required this.createdAt,
  });

  factory CollectionNote.fromRow(Map<String, dynamic> row) {
    return CollectionNote(
      id: row['id'] as String,
      collectionId: row['collection_id'] as String,
      content: row['content'] as String? ?? '',
      createdAt: DateTime.parse(row['created_at'] as String),
    );
  }

  Map<String, dynamic> toRow() {
    return {
      'id': id,
      'collection_id': collectionId,
      'content': content,
      'created_at': createdAt.toIso8601String(),
    };
  }
}
