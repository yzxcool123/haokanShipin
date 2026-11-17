class VodCategory {
  const VodCategory({required this.id, required this.name});

  final String id;
  final String name;

  factory VodCategory.fromJson(Map<String, dynamic> json) {
    return VodCategory(
      id: '${json['id'] ?? ''}',
      name: '${json['name'] ?? ''}',
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
      };
}
