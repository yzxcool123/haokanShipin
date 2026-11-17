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

  factory VodItem.fromJson(Map<String, dynamic> json) {
    return VodItem(
      sourceKey: '${json['sourceKey'] ?? ''}',
      id: '${json['id'] ?? ''}',
      name: '${json['name'] ?? ''}',
      pic: '${json['pic'] ?? ''}',
      remarks: '${json['remarks'] ?? ''}',
      score: '${json['score'] ?? ''}',
      typeName: '${json['typeName'] ?? ''}',
      description: '${json['description'] ?? ''}',
    );
  }

  Map<String, dynamic> toJson() => {
        'sourceKey': sourceKey,
        'id': id,
        'name': name,
        'pic': pic,
        'remarks': remarks,
        'score': score,
        'typeName': typeName,
        'description': description,
      };
}
