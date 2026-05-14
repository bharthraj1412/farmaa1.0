import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Live price/stock update received via Supabase Realtime.
class MarketPriceUpdate {
  final String id;
  final String cropName;
  final String category;
  final double pricePerKg;
  final String marketName;
  final DateTime recordedAt;

  const MarketPriceUpdate({
    required this.id,
    required this.cropName,
    required this.category,
    required this.pricePerKg,
    required this.marketName,
    required this.recordedAt,
  });

  factory MarketPriceUpdate.fromMap(Map<String, dynamic> m) {
    return MarketPriceUpdate(
      id:          m['id']?.toString() ?? '',
      cropName:    m['crop_name']?.toString() ?? '',
      category:    m['category']?.toString() ?? 'Other',
      pricePerKg:  (m['price_per_kg'] as num?)?.toDouble() ?? 0.0,
      marketName:  m['market_name']?.toString() ?? '',
      recordedAt:  m['recorded_at'] != null
          ? DateTime.tryParse(m['recorded_at'].toString()) ?? DateTime.now()
          : DateTime.now(),
    );
  }
}

/// Crop stock update received via Supabase Realtime.
class StockUpdate {
  final String cropId;
  final double newStockKg;
  final bool isAvailable;

  const StockUpdate({
    required this.cropId,
    required this.newStockKg,
    required this.isAvailable,
  });

  factory StockUpdate.fromMap(Map<String, dynamic> m) {
    return StockUpdate(
      cropId:      m['id']?.toString() ?? '',
      newStockKg:  (m['stock_kg'] as num?)?.toDouble() ?? 0.0,
      isAvailable: m['is_available'] as bool? ?? false,
    );
  }
}

/// Supabase Realtime service – subscribes to live market price and
/// crop stock changes so the Flutter UI can update without polling.
///
/// Usage:
/// ```dart
/// final svc = RealtimeService.instance;
/// svc.priceUpdates.listen((update) => setState(() => ...));
/// svc.stockUpdates.listen((update) => setState(() => ...));
/// await svc.init();          // call once in main or a root widget
/// await svc.dispose();       // call on app exit / provider dispose
/// ```
class RealtimeService {
  RealtimeService._();
  static final RealtimeService instance = RealtimeService._();

  final _supabase = Supabase.instance.client;

  // Stream controllers
  final _priceController = StreamController<MarketPriceUpdate>.broadcast();
  final _stockController = StreamController<StockUpdate>.broadcast();

  Stream<MarketPriceUpdate> get priceUpdates => _priceController.stream;
  Stream<StockUpdate>       get stockUpdates  => _stockController.stream;

  RealtimeChannel? _priceChannel;
  RealtimeChannel? _stockChannel;
  bool _initialized = false;

  /// Start listening to Supabase Realtime.
  ///
  /// Safe to call multiple times — subsequent calls are no-ops.
  Future<void> init() async {
    if (_initialized) return;
    _initialized = true;

    try {
      // ── Market prices channel ──────────────────────────────────
      // Fires on INSERT (new price recorded from APMC / manual entry).
      _priceChannel = _supabase
          .channel('public:market_prices')
          .onPostgresChanges(
            event:    PostgresChangeEvent.insert,
            schema:   'public',
            table:    'market_prices',
            callback: (payload) {
              try {
                final row = payload.newRecord;
                if (row.isNotEmpty) {
                  _priceController.add(MarketPriceUpdate.fromMap(row));
                }
              } catch (e) {
                debugPrint('[Realtime] Error parsing price update: $e');
              }
            },
          )
          .subscribe((status, [error]) {
            debugPrint('[Realtime] market_prices channel: $status');
            if (error != null) debugPrint('[Realtime] Error: $error');
          });

      // ── Crops channel ──────────────────────────────────────────
      // Fires on UPDATE (stock changed, price changed, availability changed).
      _stockChannel = _supabase
          .channel('public:crops')
          .onPostgresChanges(
            event:    PostgresChangeEvent.update,
            schema:   'public',
            table:    'crops',
            callback: (payload) {
              try {
                final row = payload.newRecord;
                if (row.isNotEmpty) {
                  _stockController.add(StockUpdate.fromMap(row));
                }
              } catch (e) {
                debugPrint('[Realtime] Error parsing stock update: $e');
              }
            },
          )
          .subscribe((status, [error]) {
            debugPrint('[Realtime] crops channel: $status');
          });

      debugPrint('[Realtime] Subscribed to market_prices and crops channels ✓');
    } catch (e) {
      debugPrint('[Realtime] Could not initialize Supabase Realtime: $e');
      _initialized = false;
    }
  }

  /// Fetch recent market prices as a one-shot stream (for initial load).
  ///
  /// Returns the 40 most recent rows, then keeps streaming new inserts
  /// via the Realtime channel.
  Stream<List<Map<String, dynamic>>> latestPricesStream({
    String? category,
    int limit = 40,
  }) {
    var query = _supabase
        .from('market_prices')
        .stream(primaryKey: ['id'])
        .order('recorded_at', ascending: false)
        .limit(limit);

    // stream() doesn't support WHERE filters directly;
    // filter client-side when category is provided.
    if (category != null) {
      return query.map((rows) =>
          rows.where((r) => r['category'] == category).toList());
    }
    return query;
  }

  /// Disconnect both channels and close stream controllers.
  Future<void> dispose() async {
    if (_priceChannel != null) {
      await _supabase.removeChannel(_priceChannel!);
    }
    if (_stockChannel != null) {
      await _supabase.removeChannel(_stockChannel!);
    }
    await _priceController.close();
    await _stockController.close();
    _initialized = false;
    debugPrint('[Realtime] Channels removed and streams closed.');
  }
}
