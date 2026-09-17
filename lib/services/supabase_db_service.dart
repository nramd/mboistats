import 'package:flutter/foundation.dart';
import 'package:mboistats/services/supabase_auth_service.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'dart:async';

SupabaseClient get _supabase => Supabase.instance.client;

class SupabaseDbService with ChangeNotifier {
  final SupabaseAuthService _authService;
  List<Map<String, dynamic>> _favoriteItems = [];
  Set<String> _favoriteIds = {};
  List<Map<String, dynamic>> get favoriteItems => _favoriteItems;
  Set<String> get favoriteIds => _favoriteIds;
  StreamSubscription<AuthState>? _authSubscription;
  StreamSubscription<List<Map<String, dynamic>>>? _favoriteStreamSubscription;
  SupabaseDbService(this._authService) {
    checkCurrentUser();
    _authSubscription = _authService.authStateChanges.listen(_onAuthStateChanged);
  }
  void checkCurrentUser() {
    final user = _authService.currentUser;
    if (user != null) {
      _listenToFavorites(user.id);
    }
  }
  void _onAuthStateChanged(AuthState authState) {
    final user = authState.session?.user;
    if (user != null) {
      _listenToFavorites(user.id);
    } else {
      _clearFavorites();
    }
  }
  void _listenToFavorites(String userId) {
    _favoriteStreamSubscription?.cancel();
    _favoriteStreamSubscription = _supabase
        .from('favorites')
        .stream(primaryKey: ['id'])
        .eq('user_id', userId)
        .order('created_at', ascending: false)
        .listen(
      (list) {
        _favoriteItems = list.map(_flattenItemData).toList();
        _favoriteIds =
            _favoriteItems.map((item) => generateItemId(item['item_type'], item['title'])).toSet();
        notifyListeners();
      },
      onError: (e) {
        debugPrint("Gagal mendengarkan stream favorit: $e");
      },
    );
  }
  Map<String, dynamic> _flattenItemData(Map<String, dynamic> map) {
    final itemData = map['item_data'] as Map<String, dynamic>? ?? {};
    return {
      'id': map['id'],
      'user_id': map['user_id'],
      'item_id': map['item_id'], 
      'item_type': map['item_type'],
      'title': map['title'],
      'created_at': map['created_at'],
      ...itemData,
    };
  }
  void _clearFavorites() {
    _favoriteStreamSubscription?.cancel();
    _favoriteItems = [];
    _favoriteIds = {};
    notifyListeners();
  }
  @override
  void dispose() {
    _authSubscription?.cancel();
    _favoriteStreamSubscription?.cancel();
    super.dispose();
  }
  String generateItemId(String? itemType, String? itemTitle) {
    final type = itemType ?? 'unknown';
    final title = itemTitle ?? 'Tanpa Judul';
    final cleanTitle = title.replaceAll(RegExp(r'\s+'), '_');
    final sanitizedTitle = cleanTitle.trim();
    return 'favorite_${type}_$sanitizedTitle';
  }
  Future<void> addFavorite(Map<String, dynamic> item) async {
    final userId = _authService.currentUser?.id;
    if (userId == null) {
      return;
    }
    final itemType = item['type'] as String? ?? 'unknown';
    final title = item['title'] as String? ?? 'Tanpa Judul';
    final itemId = generateItemId(itemType, title);
    if (_favoriteIds.contains(itemId)) {
      return; 
    }
    final Map<String, dynamic> itemData = Map.from(item);
    itemData.remove('type');
    itemData.remove('title');
    try {
      final newRecord = await _supabase.from('favorites').insert({
        'user_id': userId,
        'item_id': itemId, 
        'item_type': itemType,
        'title': title, 
        'item_data': itemData,
      }).select(); 
      if (newRecord.isNotEmpty) {
        final newItem = _flattenItemData(newRecord[0]);
        _favoriteItems.insert(0, newItem); 
        _favoriteIds.add(itemId);
      }
      notifyListeners();
    } catch (e) {
      debugPrint("Gagal menambahkan favorit: $e");
    }
  }
  Future<void> removeFavorite(String? itemType, String? itemTitle) async {
    final userId = _authService.currentUser?.id;
    if (userId == null) {
      return;
    }
    final itemId = generateItemId(itemType, itemTitle);
    if (!_favoriteIds.contains(itemId)) {
      return;
    }
    try {
      await _supabase
          .from('favorites')
          .delete()
          .eq('item_id', itemId); 
      _favoriteItems.removeWhere((item) => 
          generateItemId(item['item_type'], item['title']) == itemId);
      _favoriteIds.remove(itemId);
      notifyListeners();
    } catch (e) {
      debugPrint("Gagal menghapus favorit: $e");
    }
  }
}