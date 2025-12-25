abstract interface class HeroServicing {
  Future<Map<String, dynamic>?> search(String name);
  Future<Map<String, dynamic>?> getById(String id);
}
