import 'dart:async';
import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/services/crop_service.dart';
import '../../../core/services/realtime_service.dart';
import '../../../core/theme/app_theme.dart';
import '../../../generated/l10n/app_localizations.dart';

const List<String> _tnDistricts = [
  'Ariyalur', 'Chennai', 'Coimbatore', 'Cuddalore', 'Dharmapuri',
  'Dindigul', 'Erode', 'Kancheepuram', 'Kanyakumari', 'Karur',
  'Krishnagiri', 'Madurai', 'Namakkal', 'Pudukkottai', 'Ramanathapuram',
  'Salem', 'Sivaganga', 'Thanjavur', 'Theni', 'Thoothukudi',
  'Tiruchirappalli', 'Tirunelveli', 'Tiruppur', 'Tiruvallur',
  'Tiruvannamalai', 'Vellore', 'Viluppuram', 'Virudhunagar',
];

class MarketPricesScreen extends ConsumerStatefulWidget {
  const MarketPricesScreen({super.key});

  @override
  ConsumerState<MarketPricesScreen> createState() => _MarketPricesScreenState();
}

class _MarketPricesScreenState extends ConsumerState<MarketPricesScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tabController;

  String _selectedDistrict = 'Salem';
  List<Map<String, dynamic>> _prices = [];
  bool _isLoading = false;

  // Live price ticker (most recent updates via Realtime)
  final List<MarketPriceUpdate> _liveUpdates = [];
  StreamSubscription<MarketPriceUpdate>? _realtimeSub;
  bool _hasLiveUpdate = false;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _tabController.addListener(() {
      if (!_tabController.indexIsChanging) _fetchPrices();
    });
    _fetchPrices();
    _subscribeRealtime();
  }

  @override
  void dispose() {
    _tabController.dispose();
    _realtimeSub?.cancel();
    super.dispose();
  }

  void _subscribeRealtime() {
    _realtimeSub = RealtimeService.instance.priceUpdates.listen((update) {
      if (!mounted) return;
      setState(() {
        _hasLiveUpdate = true;
        _liveUpdates.insert(0, update);
        if (_liveUpdates.length > 10) _liveUpdates.removeLast();

        // Also inject into price list
        final newEntry = {
          'crop_name':   update.cropName,
          'category':    update.category,
          'price_per_kg': update.pricePerKg,
          'market_name': update.marketName,
          'date':        _fmtDate(update.recordedAt),
          'price':       update.pricePerKg * 100, // convert to /quintal for chart
        };
        _prices.insert(0, newEntry);
        if (_prices.length > 50) _prices.removeLast();
      });
    });
  }

  Future<void> _fetchPrices() async {
    final commodity = _tabController.index == 0 ? 'Millet' : 'Wheat';
    setState(() => _isLoading = true);
    try {
      final data = await CropService.instance.getMarketPrices(
        commodity: commodity,
        district:  _selectedDistrict,
      );
      if (mounted) {
        setState(() {
          _prices = data.isNotEmpty ? _toChartData(data) : _demoData();
        });
      }
    } catch (_) {
      if (mounted) setState(() => _prices = _demoData());
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  List<Map<String, dynamic>> _toChartData(List<Map<String, dynamic>> raw) {
    return raw.map((r) => {
      ...r,
      'date':  _fmtDate(
        r['recorded_at'] != null
            ? DateTime.tryParse(r['recorded_at'].toString()) ?? DateTime.now()
            : DateTime.now(),
      ),
      'price': ((r['price_per_kg'] as num?)?.toDouble() ?? 0) * 100,
    }).toList();
  }

  List<Map<String, dynamic>> _demoData() {
    final base = _tabController.index == 0 ? 2800.0 : 2200.0;
    return List.generate(7, (i) {
      final dt = DateTime.now().subtract(Duration(days: 6 - i));
      final variation = (i - 3) * 20.0 + (base * 0.02 * (i % 2 == 0 ? 1 : -1));
      return {
        'date':  _fmtDate(dt),
        'price': base + variation,
        'price_per_kg': (base + variation) / 100,
        'crop_name': _tabController.index == 0 ? 'Ragi (Finger Millet)' : 'Wheat (HD-2967)',
        'market_name': _selectedDistrict,
      };
    });
  }

  String _fmtDate(DateTime dt) =>
      '${dt.day} ${['Jan','Feb','Mar','Apr','May','Jun','Jul','Aug','Sep','Oct','Nov','Dec'][dt.month - 1]}';

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    return Scaffold(
      backgroundColor: AppTheme.surfaceCream,
      appBar: AppBar(
        title: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(l.marketPrices),
            if (_hasLiveUpdate) ...[
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: AppTheme.successGreen,
                  borderRadius: AppTheme.radiusRound,
                ),
                child: const Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    _PulseDot(),
                    SizedBox(width: 4),
                    Text('LIVE', style: TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.w700)),
                  ],
                ),
              ),
            ],
          ],
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh_rounded),
            onPressed: _fetchPrices,
            tooltip: 'Refresh',
          ),
        ],
        bottom: TabBar(
          controller: _tabController,
          labelColor: AppTheme.primaryGreen,
          indicatorColor: AppTheme.primaryGreen,
          indicatorWeight: 3,
          tabs: [
            Tab(icon: const Text('🌾'), text: l.grainMillet),
            Tab(icon: const Text('🌿'), text: l.grainWheat),
          ],
        ),
      ),
      body: Column(
        children: [
          // Live update banner
          if (_liveUpdates.isNotEmpty)
            _LiveUpdateBanner(updates: _liveUpdates),

          // District selector
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
            child: DropdownButtonFormField<String>(
              value: _selectedDistrict,
              items: _tnDistricts
                  .map((d) => DropdownMenuItem(value: d, child: Text(d)))
                  .toList(),
              onChanged: (v) {
                if (v != null && v != _selectedDistrict) {
                  setState(() => _selectedDistrict = v);
                  _fetchPrices();
                }
              },
              decoration: InputDecoration(
                labelText: l.district,
                prefixIcon: const Icon(Icons.map_outlined),
                contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              ),
            ),
          ),
          const SizedBox(height: 8),

          Expanded(
            child: _isLoading
                ? const Center(child: CircularProgressIndicator())
                : TabBarView(
                    controller: _tabController,
                    children: [
                      _PriceContent(prices: _prices, commodity: l.grainMillet),
                      _PriceContent(prices: _prices, commodity: l.grainWheat),
                    ],
                  ),
          ),
        ],
      ),
    );
  }
}

// ── Live update banner ───────────────────────────────────────────────────────

class _LiveUpdateBanner extends StatelessWidget {
  final List<MarketPriceUpdate> updates;
  const _LiveUpdateBanner({required this.updates});

  @override
  Widget build(BuildContext context) {
    final latest = updates.first;
    return AnimatedContainer(
      duration: const Duration(milliseconds: 300),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      color: AppTheme.successGreen.withValues(alpha: 0.1),
      child: Row(
        children: [
          const _PulseDot(color: AppTheme.successGreen),
          const SizedBox(width: 8),
          const Icon(Icons.trending_up, size: 16, color: AppTheme.successGreen),
          const SizedBox(width: 6),
          Expanded(
            child: Text(
              '${latest.cropName} — ₹${latest.pricePerKg.toStringAsFixed(0)}/kg '
              '@ ${latest.marketName}',
              style: const TextStyle(
                fontSize: 12,
                color: AppTheme.successGreen,
                fontWeight: FontWeight.w600,
              ),
              overflow: TextOverflow.ellipsis,
            ),
          ),
          Text(
            'LIVE UPDATE',
            style: TextStyle(
              fontSize: 10,
              color: AppTheme.successGreen.withValues(alpha: 0.7),
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}

// ── Pulsing dot indicator ────────────────────────────────────────────────────

class _PulseDot extends StatefulWidget {
  final Color color;
  const _PulseDot({this.color = Colors.white});

  @override
  State<_PulseDot> createState() => _PulseDotState();
}

class _PulseDotState extends State<_PulseDot> with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 800),
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _ctrl,
      builder: (_, __) => Container(
        width: 7,
        height: 7,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: widget.color.withValues(alpha: 0.4 + _ctrl.value * 0.6),
        ),
      ),
    );
  }
}

// ── Price content tab ────────────────────────────────────────────────────────

class _PriceContent extends StatelessWidget {
  final List<Map<String, dynamic>> prices;
  final String commodity;

  const _PriceContent({required this.prices, required this.commodity});

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    if (prices.isEmpty) return Center(child: Text(l.noPriceData));

    final latestPricePerQuintal = (prices.last['price'] as num?)?.toDouble() ?? 0;
    final prevPricePerQuintal = prices.length > 1
        ? (prices[prices.length - 2]['price'] as num?)?.toDouble() ?? latestPricePerQuintal
        : latestPricePerQuintal;
    final change   = latestPricePerQuintal - prevPricePerQuintal;
    final isRising = change >= 0;

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Price summary card
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              gradient: AppTheme.primaryGradient,
              borderRadius: AppTheme.radiusLarge,
              boxShadow: AppTheme.elevatedShadow,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '$commodity — ${l.todaysRate}',
                  style: const TextStyle(color: Colors.white70, fontSize: 13),
                ),
                const SizedBox(height: 4),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(
                      '₹${latestPricePerQuintal.toStringAsFixed(0)}',
                      style: const TextStyle(
                        color: Colors.white, fontSize: 36, fontWeight: FontWeight.w800),
                    ),
                    Text(l.quintal,
                        style: const TextStyle(color: Colors.white54, fontSize: 14)),
                    const Spacer(),
                    _changeBadge(change, isRising),
                  ],
                ),
                const SizedBox(height: 4),
                Text(
                  '₹${(latestPricePerQuintal / 100).toStringAsFixed(2)}/kg',
                  style: const TextStyle(color: Colors.white60, fontSize: 12),
                ),
              ],
            ),
          ),
          const SizedBox(height: 20),

          // 7-day chart
          Text(l.sevenDayTrend, style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 12),
          Container(
            height: 200,
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: AppTheme.radiusLarge,
              boxShadow: AppTheme.cardShadow,
            ),
            child: LineChart(_buildChart()),
          ),
          const SizedBox(height: 20),

          // Historical table
          Text(l.historicalData, style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 8),
          ...prices.take(15).map(
            (p) => Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          p['crop_name']?.toString() ?? commodity,
                          style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
                          maxLines: 1, overflow: TextOverflow.ellipsis,
                        ),
                        Text(p['market_name']?.toString() ?? '',
                            style: const TextStyle(fontSize: 10, color: AppTheme.textLight)),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text(p['date']?.toString() ?? '',
                      style: const TextStyle(color: AppTheme.textMedium, fontSize: 11)),
                  const SizedBox(width: 12),
                  Text(
                    '₹${(p['price'] as num?)?.toStringAsFixed(0) ?? '—'}${l.quintal}',
                    style: const TextStyle(
                      fontWeight: FontWeight.w600, color: AppTheme.primaryGreen),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 40),
        ],
      ),
    );
  }

  Widget _changeBadge(double change, bool isRising) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
    decoration: BoxDecoration(
      color: (isRising ? Colors.greenAccent : Colors.redAccent).withValues(alpha: 0.2),
      borderRadius: AppTheme.radiusRound,
    ),
    child: Row(
      children: [
        Icon(isRising ? Icons.trending_up : Icons.trending_down,
            color: isRising ? Colors.greenAccent : Colors.redAccent, size: 16),
        const SizedBox(width: 4),
        Text(
          '${isRising ? '+' : ''}${change.toStringAsFixed(0)}',
          style: TextStyle(
            color: isRising ? Colors.greenAccent : Colors.redAccent,
            fontWeight: FontWeight.w700,
          ),
        ),
      ],
    ),
  );

  LineChartData _buildChart() {
    final spots = prices.asMap().entries.map(
      (e) => FlSpot(e.key.toDouble(), (e.value['price'] as num?)?.toDouble() ?? 0),
    ).toList();

    if (spots.isEmpty) {
      return LineChartData(
        gridData: const FlGridData(show: false),
        titlesData: const FlTitlesData(show: false),
        borderData: FlBorderData(show: false),
        lineBarsData: [],
      );
    }

    final minY = spots.map((s) => s.y).reduce((a, b) => a < b ? a : b) - 100;
    final maxY = spots.map((s) => s.y).reduce((a, b) => a > b ? a : b) + 100;

    return LineChartData(
      minY: minY,
      maxY: maxY,
      gridData: FlGridData(
        drawVerticalLine: false,
        getDrawingHorizontalLine: (_) => const FlLine(color: AppTheme.borderLight, strokeWidth: 1),
      ),
      titlesData: FlTitlesData(
        topTitles:   const AxisTitles(sideTitles: SideTitles(showTitles: false)),
        rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
        leftTitles:  AxisTitles(
          sideTitles: SideTitles(
            showTitles: true,
            reservedSize: 50,
            getTitlesWidget: (val, _) => Text(
              '₹${val.toStringAsFixed(0)}',
              style: const TextStyle(fontSize: 9, color: AppTheme.textLight),
            ),
          ),
        ),
        bottomTitles: AxisTitles(
          sideTitles: SideTitles(
            showTitles: true,
            getTitlesWidget: (val, _) {
              final idx = val.toInt();
              if (idx < 0 || idx >= prices.length) return const SizedBox.shrink();
              return Text(
                prices[idx]['date']?.toString().split(' ').first ?? '',
                style: const TextStyle(fontSize: 9, color: AppTheme.textLight),
              );
            },
          ),
        ),
      ),
      borderData: FlBorderData(show: false),
      lineBarsData: [
        LineChartBarData(
          spots: spots,
          isCurved: true,
          color: AppTheme.primaryGreen,
          barWidth: 3,
          dotData: FlDotData(
            getDotPainter: (_, __, ___, ____) => FlDotCirclePainter(
              radius: 4,
              color: AppTheme.primaryGreen,
              strokeWidth: 2,
              strokeColor: Colors.white,
            ),
          ),
          belowBarData: BarAreaData(
            show: true,
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [
                AppTheme.primaryGreen.withValues(alpha: 0.3),
                AppTheme.primaryGreen.withValues(alpha: 0.0),
              ],
            ),
          ),
        ),
      ],
    );
  }
}
