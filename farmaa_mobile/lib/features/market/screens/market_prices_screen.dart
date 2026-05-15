import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/services/crop_service.dart';
import '../../../core/theme/app_theme.dart';

// ── All grain categories with emoji icons ────────────────────────────────────

const _categoryIcons = <String, String>{
  'Rice': '🍚',
  'Wheat': '🌾',
  'Millet': '🌿',
  'Maize': '🌽',
  'Pulses': '🫘',
  'Barley': '🌱',
  'Oilseed': '🥜',
};

const _allCategories = ['Rice', 'Wheat', 'Millet', 'Maize', 'Pulses', 'Barley', 'Oilseed'];

// ── Main Screen ──────────────────────────────────────────────────────────────

class MarketPricesScreen extends ConsumerStatefulWidget {
  const MarketPricesScreen({super.key});

  @override
  ConsumerState<MarketPricesScreen> createState() => _MarketPricesScreenState();
}

class _MarketPricesScreenState extends ConsumerState<MarketPricesScreen> {
  String _selectedCategory = 'Rice';
  List<Map<String, dynamic>> _prices = [];
  bool _isLoading = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _fetchPrices();
  }

  Future<void> _fetchPrices() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });
    try {
      final data = await CropService.instance.getMarketPrices(
        category: _selectedCategory,
      );
      if (mounted) setState(() => _prices = data);
    } catch (e) {
      if (mounted) setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.surfaceCream,
      appBar: AppBar(
        title: const Text('Market Prices'),
        elevation: 0,
      ),
      body: Column(
        children: [
          // ── Category chips ──
          SizedBox(
            height: 56,
            child: ListView.builder(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              itemCount: _allCategories.length,
              itemBuilder: (ctx, i) {
                final cat = _allCategories[i];
                final selected = cat == _selectedCategory;
                return Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: ChoiceChip(
                    label: Text(
                      '${_categoryIcons[cat] ?? ''} $cat',
                      style: TextStyle(
                        color: selected ? Colors.white : AppTheme.textDark,
                        fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
                      ),
                    ),
                    selected: selected,
                    selectedColor: AppTheme.primaryGreen,
                    backgroundColor: Colors.white,
                    side: BorderSide(
                      color: selected ? AppTheme.primaryGreen : AppTheme.borderLight,
                    ),
                    onSelected: (_) {
                      setState(() => _selectedCategory = cat);
                      _fetchPrices();
                    },
                  ),
                );
              },
            ),
          ),

          // ── Content ──
          Expanded(
            child: _isLoading
                ? const Center(child: CircularProgressIndicator())
                : _error != null
                    ? Center(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(Icons.cloud_off, size: 48, color: AppTheme.textLight),
                            const SizedBox(height: 12),
                            Text('Could not load prices', style: TextStyle(color: AppTheme.textMedium)),
                            const SizedBox(height: 8),
                            ElevatedButton(onPressed: _fetchPrices, child: const Text('Retry')),
                          ],
                        ),
                      )
                    : _prices.isEmpty
                        ? const Center(child: Text('No price data available'))
                        : _PriceListView(
                            prices: _prices,
                            category: _selectedCategory,
                          ),
          ),
        ],
      ),
    );
  }
}

// ── Price List ────────────────────────────────────────────────────────────────

class _PriceListView extends StatelessWidget {
  final List<Map<String, dynamic>> prices;
  final String category;

  const _PriceListView({required this.prices, required this.category});

  @override
  Widget build(BuildContext context) {
    // Group prices by grain name
    final grouped = <String, List<Map<String, dynamic>>>{};
    for (final p in prices) {
      final name = p['crop_name']?.toString() ?? 'Unknown';
      (grouped[name] ??= []).add(p);
    }
    final grainNames = grouped.keys.toList()..sort();

    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
      itemCount: grainNames.length,
      itemBuilder: (ctx, i) {
        final grain = grainNames[i];
        final entries = grouped[grain]!;
        return _GrainCard(grain: grain, entries: entries);
      },
    );
  }
}

// ── Individual Grain Card ────────────────────────────────────────────────────

class _GrainCard extends StatelessWidget {
  final String grain;
  final List<Map<String, dynamic>> entries;

  const _GrainCard({required this.grain, required this.entries});

  @override
  Widget build(BuildContext context) {
    // Calculate stats
    final prices = entries
        .map((e) => ((e['price_per_kg'] as num?) ?? 0).toDouble() * 100) // per kg → per quintal
        .toList();
    final avg = prices.isEmpty ? 0.0 : prices.reduce((a, b) => a + b) / prices.length;
    final minP = prices.isEmpty ? 0.0 : prices.reduce((a, b) => a < b ? a : b);
    final maxP = prices.isEmpty ? 0.0 : prices.reduce((a, b) => a > b ? a : b);

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      shape: RoundedRectangleBorder(borderRadius: AppTheme.radiusLarge),
      elevation: 1,
      child: ExpansionTile(
        shape: RoundedRectangleBorder(borderRadius: AppTheme.radiusLarge),
        collapsedShape: RoundedRectangleBorder(borderRadius: AppTheme.radiusLarge),
        tilePadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
        leading: Container(
          width: 44,
          height: 44,
          decoration: BoxDecoration(
            color: AppTheme.primaryGreen.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Center(
            child: Text(
              _categoryIcons[entries.first['category']?.toString()] ?? '🌾',
              style: const TextStyle(fontSize: 22),
            ),
          ),
        ),
        title: Text(grain, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 15)),
        subtitle: Text(
          '₹${avg.toStringAsFixed(0)}/qtl  •  ${entries.length} markets',
          style: const TextStyle(color: AppTheme.textMedium, fontSize: 12),
        ),
        trailing: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Text(
              '₹${avg.toStringAsFixed(0)}',
              style: const TextStyle(
                fontWeight: FontWeight.w700,
                fontSize: 16,
                color: AppTheme.primaryGreen,
              ),
            ),
            Text(
              '${minP.toStringAsFixed(0)} – ${maxP.toStringAsFixed(0)}',
              style: const TextStyle(color: AppTheme.textLight, fontSize: 11),
            ),
          ],
        ),
        children: [
          const Divider(height: 1),
          // Market-wise prices table
          Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              children: entries.take(10).map((e) {
                final mkt = e['market_name']?.toString() ?? '';
                final pq = ((e['price_per_kg'] as num?) ?? 0).toDouble() * 100;
                return Padding(
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  child: Row(
                    children: [
                      const Icon(Icons.storefront, size: 14, color: AppTheme.textLight),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(mkt, style: const TextStyle(fontSize: 13), overflow: TextOverflow.ellipsis),
                      ),
                      Text(
                        '₹${pq.toStringAsFixed(0)}/qtl',
                        style: const TextStyle(fontWeight: FontWeight.w600, color: AppTheme.primaryGreen, fontSize: 13),
                      ),
                    ],
                  ),
                );
              }).toList(),
            ),
          ),
          if (entries.length > 10)
            Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: Text(
                '+${entries.length - 10} more markets',
                style: const TextStyle(color: AppTheme.textLight, fontSize: 12),
              ),
            ),
        ],
      ),
    );
  }
}
