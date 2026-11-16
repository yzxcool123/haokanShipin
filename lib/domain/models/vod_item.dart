class VodItem {
  const VodItem({
    required this.sourceKey,
    required this.id,
    required this.name,
    this.pic = '',
    this.remarks = '',
    this.score = '',
    this.typeName = '',
    this.description = '',
  });

  final String sourceKey;
  final String id;
  final String name;
  final String pic;
  final String remarks;
  final String score;
  final String typeName;
  final String description;
}
