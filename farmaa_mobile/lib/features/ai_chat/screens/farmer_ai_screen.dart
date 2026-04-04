import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/api/api_client.dart';
import '../../../core/theme/app_theme.dart';
import '../../../generated/l10n/app_localizations.dart';

class FarmerAIScreen extends ConsumerStatefulWidget {
  const FarmerAIScreen({super.key});

  @override
  ConsumerState<FarmerAIScreen> createState() => _FarmerAIScreenState();
}

class _FarmerAIScreenState extends ConsumerState<FarmerAIScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tabController;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    return Scaffold(
      backgroundColor: AppTheme.surfaceCream,
      appBar: AppBar(
        title: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.all(6),
              decoration: BoxDecoration(
                gradient: AppTheme.primaryGradient,
                borderRadius: BorderRadius.circular(8),
              ),
              child: const Icon(Icons.auto_awesome, color: Colors.white, size: 18),
            ),
            const SizedBox(width: 10),
            Text('${l.aiAssistant}',
                style: const TextStyle(fontWeight: FontWeight.w700)),
          ],
        ),
        bottom: TabBar(
          controller: _tabController,
          labelColor: AppTheme.primaryGreen,
          indicatorColor: AppTheme.primaryGreen,
          indicatorWeight: 3,
          labelStyle: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
          unselectedLabelStyle: const TextStyle(fontSize: 13),
          tabs: [
            Tab(text: '💬 Chat'),
            Tab(text: '🌾 ${l.yieldPrediction}'),
            Tab(text: '♻️ ${l.sustainability}'),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: const [
          _AIChatTab(),
          _YieldPredictionTab(),
          _SustainabilityTab(),
        ],
      ),
    );
  }
}

// ── Tab 1: AI Chat ──────────────────────────────────────────────────────────────

class _AIChatTab extends StatefulWidget {
  const _AIChatTab();

  @override
  State<_AIChatTab> createState() => _AIChatTabState();
}

class _AIChatTabState extends State<_AIChatTab> {
  final _controller = TextEditingController();
  final _scrollController = ScrollController();
  final _dio = ApiClient().dio;
  final List<_ChatMsg> _messages = [];
  bool _loading = false;

  final _quickPrompts = [
    '📊 Current market prices',
    '🌾 How to improve yield?',
    '🐛 Pest control tips',
    '🏛️ Government schemes',
    '🌻 Millet farming guide',
    '🌍 Soil health tips',
  ];

  @override
  void dispose() {
    _controller.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  Future<void> _send(String text) async {
    if (text.trim().isEmpty) return;
    _controller.clear();

    setState(() {
      _messages.add(_ChatMsg(role: 'user', content: text.trim()));
      _loading = true;
    });
    _scrollToBottom();

    try {
      final msgs = _messages
          .map((m) => {'role': m.role, 'content': m.content})
          .toList();
      final resp = await _dio.post('/ai/chat', data: {'messages': msgs});
      final data = resp.data as Map<String, dynamic>;
      setState(() {
        _messages.add(_ChatMsg(
          role: 'assistant',
          content: data['content'] ?? 'Sorry, I could not process that.',
        ));
      });
    } catch (e) {
      setState(() {
        _messages.add(_ChatMsg(
          role: 'assistant',
          content: '⚠️ Could not reach AI advisor. Please try again.',
        ));
      });
    } finally {
      setState(() => _loading = false);
      _scrollToBottom();
    }
  }

  void _scrollToBottom() {
    Future.delayed(const Duration(milliseconds: 100), () {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOut,
        );
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Expanded(
          child: _messages.isEmpty
              ? _buildWelcome()
              : ListView.builder(
                  controller: _scrollController,
                  padding: const EdgeInsets.all(16),
                  itemCount: _messages.length + (_loading ? 1 : 0),
                  itemBuilder: (ctx, i) {
                    if (i == _messages.length) return _buildTypingIndicator();
                    return _buildBubble(_messages[i]);
                  },
                ),
        ),
        _buildInputBar(),
      ],
    );
  }

  Widget _buildWelcome() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Column(
        children: [
          const SizedBox(height: 20),
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              gradient: AppTheme.primaryGradient,
              borderRadius: AppTheme.radiusLarge,
            ),
            child: const Column(
              children: [
                Icon(Icons.auto_awesome, color: Colors.white, size: 48),
                SizedBox(height: 12),
                Text(
                  'Farmaa AI Advisor',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 22,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                SizedBox(height: 6),
                Text(
                  'Your intelligent farming companion.\nAsk anything about crops, prices, pests, or schemes!',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: Colors.white70, fontSize: 13, height: 1.4),
                ),
              ],
            ),
          ),
          const SizedBox(height: 20),
          const Align(
            alignment: Alignment.centerLeft,
            child: Text(
              'Quick questions:',
              style: TextStyle(fontWeight: FontWeight.w600, fontSize: 14),
            ),
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: _quickPrompts
                .map((p) => ActionChip(
                      label: Text(p, style: const TextStyle(fontSize: 12)),
                      onPressed: () => _send(p),
                      backgroundColor:
                          AppTheme.primaryGreen.withValues(alpha: 0.08),
                      side: BorderSide(
                        color: AppTheme.primaryGreen.withValues(alpha: 0.3),
                      ),
                    ))
                .toList(),
          ),
        ],
      ),
    );
  }

  Widget _buildBubble(_ChatMsg msg) {
    final isUser = msg.role == 'user';
    return Align(
      alignment: isUser ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        margin: EdgeInsets.only(
          bottom: 10,
          left: isUser ? 48 : 0,
          right: isUser ? 0 : 48,
        ),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          color: isUser ? AppTheme.primaryGreen : Colors.white,
          borderRadius: BorderRadius.only(
            topLeft: const Radius.circular(16),
            topRight: const Radius.circular(16),
            bottomLeft: Radius.circular(isUser ? 16 : 4),
            bottomRight: Radius.circular(isUser ? 4 : 16),
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.06),
              blurRadius: 6,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Text(
          msg.content,
          style: TextStyle(
            color: isUser ? Colors.white : AppTheme.textDark,
            fontSize: 14,
            height: 1.4,
          ),
        ),
      ),
    );
  }

  Widget _buildTypingIndicator() {
    return Align(
      alignment: Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.only(bottom: 10, right: 48),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            _Dot(delay: 0),
            const SizedBox(width: 4),
            _Dot(delay: 150),
            const SizedBox(width: 4),
            _Dot(delay: 300),
          ],
        ),
      ),
    );
  }

  Widget _buildInputBar() {
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
      decoration: BoxDecoration(
        color: Colors.white,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.05),
            blurRadius: 10,
            offset: const Offset(0, -2),
          ),
        ],
      ),
      child: SafeArea(
        child: Row(
          children: [
            Expanded(
              child: TextField(
                controller: _controller,
                textInputAction: TextInputAction.send,
                onSubmitted: _send,
                decoration: InputDecoration(
                  hintText: 'Ask about farming, prices, pests...',
                  hintStyle: const TextStyle(fontSize: 14, color: AppTheme.textLight),
                  filled: true,
                  fillColor: AppTheme.surfaceCream,
                  contentPadding:
                      const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(24),
                    borderSide: BorderSide.none,
                  ),
                ),
              ),
            ),
            const SizedBox(width: 8),
            Container(
              decoration: const BoxDecoration(
                color: AppTheme.primaryGreen,
                shape: BoxShape.circle,
              ),
              child: IconButton(
                icon: const Icon(Icons.send_rounded, color: Colors.white, size: 20),
                onPressed: _loading ? null : () => _send(_controller.text),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ChatMsg {
  final String role;
  final String content;
  _ChatMsg({required this.role, required this.content});
}

// ── Animated typing dot ─────────────────────────────────────────────────────────

class _Dot extends StatefulWidget {
  final int delay;
  const _Dot({required this.delay});

  @override
  State<_Dot> createState() => _DotState();
}

class _DotState extends State<_Dot> with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 600),
    );
    Future.delayed(Duration(milliseconds: widget.delay), () {
      if (mounted) _ctrl.repeat(reverse: true);
    });
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
        width: 8,
        height: 8,
        decoration: BoxDecoration(
          color: AppTheme.primaryGreen.withValues(alpha: 0.3 + _ctrl.value * 0.7),
          shape: BoxShape.circle,
        ),
      ),
    );
  }
}

// ── Tab 2: Yield Prediction ─────────────────────────────────────────────────────

class _YieldPredictionTab extends StatefulWidget {
  const _YieldPredictionTab();

  @override
  State<_YieldPredictionTab> createState() => _YieldPredictionTabState();
}

class _YieldPredictionTabState extends State<_YieldPredictionTab> {
  final _areaCtrl = TextEditingController(text: '1');
  final _dio = ApiClient().dio;
  String _crop = 'Millet';
  String _season = 'Kharif';
  String _soil = 'Red';
  String _irrigation = 'Drip';
  bool _loading = false;
  String? _result;

  Future<void> _predict() async {
    setState(() {
      _loading = true;
      _result = null;
    });

    try {
      final area = double.tryParse(_areaCtrl.text) ?? 1.0;
      final resp = await _dio.post('/ai/yield-predict', data: {
        'crop': _crop,
        'area_hectares': area,
        'season': _season,
        'soil_type': _soil,
        'irrigation': _irrigation,
      });
      final data = resp.data as Map<String, dynamic>;
      setState(() => _result = data['content'] ?? 'No result available');
    } catch (e) {
      setState(() => _result = '⚠️ Could not get prediction. Please try again.');
    } finally {
      setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Crop chips
          _label(l.crop),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            children: ['Millet', 'Wheat', 'Rice', 'Maize', 'Pulses'].map((c) {
              final emoji = {
                'Millet': '🌾', 'Wheat': '🌿', 'Rice': '🍚',
                'Maize': '🌽', 'Pulses': '🫘'
              }[c] ?? '🌱';
              return ChoiceChip(
                label: Text('$emoji $c'),
                selected: _crop == c,
                onSelected: (_) => setState(() => _crop = c),
                selectedColor: AppTheme.primaryGreen,
                labelStyle: TextStyle(
                  color: _crop == c ? Colors.white : AppTheme.textDark,
                  fontWeight: FontWeight.w600,
                ),
              );
            }).toList(),
          ),
          const SizedBox(height: 16),
          _label(l.area),
          const SizedBox(height: 6),
          TextFormField(
            controller: _areaCtrl,
            keyboardType: TextInputType.number,
            decoration: InputDecoration(
              suffixText: 'hectares',
              filled: true,
              fillColor: Colors.white,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide(color: Colors.grey.shade300),
              ),
            ),
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(child: _buildDropdown(l.season, ['Kharif', 'Rabi', 'Zaid'],
                  _season, (v) => setState(() => _season = v!))),
              const SizedBox(width: 12),
              Expanded(child: _buildDropdown(l.soilType, ['Red', 'Black', 'Sandy', 'Loamy'],
                  _soil, (v) => setState(() => _soil = v!))),
            ],
          ),
          const SizedBox(height: 16),
          _buildDropdown(l.irrigation, ['Drip', 'Canal', 'Rainfed'],
              _irrigation, (v) => setState(() => _irrigation = v!)),
          const SizedBox(height: 20),
          SizedBox(
            width: double.infinity,
            height: 50,
            child: ElevatedButton.icon(
              onPressed: _loading ? null : _predict,
              icon: _loading
                  ? const SizedBox(
                      width: 20, height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                  : const Icon(Icons.analytics_outlined),
              label: Text(l.predictYieldBtn,
                  style: const TextStyle(fontWeight: FontWeight.w700)),
              style: ElevatedButton.styleFrom(
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                ),
              ),
            ),
          ),
          if (_result != null) ...[
            const SizedBox(height: 20),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: AppTheme.radiusLarge,
                boxShadow: AppTheme.cardShadow,
              ),
              child: Text(
                _result!,
                style: const TextStyle(fontSize: 14, height: 1.5),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _label(String text) => Text(text,
      style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14));

  Widget _buildDropdown(
      String label, List<String> items, String value, ValueChanged<String?> onChanged) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _label(label),
        const SizedBox(height: 6),
        DropdownButtonFormField<String>(
          value: value,
          items: items.map((i) => DropdownMenuItem(value: i, child: Text(i))).toList(),
          onChanged: onChanged,
          decoration: InputDecoration(
            filled: true,
            fillColor: Colors.white,
            contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide(color: Colors.grey.shade300),
            ),
          ),
        ),
      ],
    );
  }
}

// ── Tab 3: Sustainability Score ──────────────────────────────────────────────────

class _SustainabilityTab extends StatefulWidget {
  const _SustainabilityTab();

  @override
  State<_SustainabilityTab> createState() => _SustainabilityTabState();
}

class _SustainabilityTabState extends State<_SustainabilityTab> {
  final _dio = ApiClient().dio;
  String _irrigation = 'Drip';
  String _fertilizer = 'Organic';
  bool _cropRotation = true;
  bool _loading = false;
  String? _result;

  Future<void> _calculate() async {
    setState(() {
      _loading = true;
      _result = null;
    });

    try {
      final resp = await _dio.post('/ai/sustainability', data: {
        'irrigation': _irrigation,
        'fertilizer': _fertilizer,
        'crop_rotation': _cropRotation,
      });
      final data = resp.data as Map<String, dynamic>;
      setState(() => _result = data['content'] ?? 'No result available');
    } catch (e) {
      setState(() =>
          _result = '⚠️ Could not calculate score. Please try again.');
    } finally {
      setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: AppTheme.primaryGreen.withValues(alpha: 0.06),
              borderRadius: AppTheme.radiusMedium,
            ),
            child: Row(
              children: [
                const Icon(Icons.eco, color: AppTheme.primaryGreen, size: 20),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    l.sustainabilityDesc,
                    style: const TextStyle(
                        color: AppTheme.textMedium, height: 1.4, fontSize: 13),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 20),
          _buildDropdownRow(l.irrigationMethod, ['Drip', 'Canal', 'Rainfed'],
              _irrigation, (v) => setState(() => _irrigation = v!)),
          const SizedBox(height: 16),
          _buildDropdownRow(l.fertilizerType, ['Organic', 'Mixed', 'Chemical'],
              _fertilizer, (v) => setState(() => _fertilizer = v!)),
          const SizedBox(height: 12),
          Container(
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(12),
            ),
            child: SwitchListTile(
              value: _cropRotation,
              onChanged: (v) => setState(() => _cropRotation = v),
              title: Text(l.cropRotationPracticed,
                  style: const TextStyle(fontWeight: FontWeight.w600)),
              activeColor: AppTheme.primaryGreen,
              contentPadding: const EdgeInsets.symmetric(horizontal: 12),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
          ),
          const SizedBox(height: 20),
          SizedBox(
            width: double.infinity,
            height: 50,
            child: ElevatedButton.icon(
              onPressed: _loading ? null : _calculate,
              icon: _loading
                  ? const SizedBox(
                      width: 20, height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                  : const Icon(Icons.eco_outlined),
              label: Text(l.calculateScoreBtn,
                  style: const TextStyle(fontWeight: FontWeight.w700)),
              style: ElevatedButton.styleFrom(
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                ),
              ),
            ),
          ),
          if (_result != null) ...[
            const SizedBox(height: 20),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: AppTheme.radiusLarge,
                boxShadow: AppTheme.cardShadow,
              ),
              child: Text(
                _result!,
                style: const TextStyle(fontSize: 14, height: 1.5),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildDropdownRow(String label, List<String> items, String value,
      ValueChanged<String?> onChanged) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14)),
        const SizedBox(height: 6),
        DropdownButtonFormField<String>(
          value: value,
          items: items.map((i) => DropdownMenuItem(value: i, child: Text(i))).toList(),
          onChanged: onChanged,
          decoration: InputDecoration(
            filled: true,
            fillColor: Colors.white,
            contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide(color: Colors.grey.shade300),
            ),
          ),
        ),
      ],
    );
  }
}
