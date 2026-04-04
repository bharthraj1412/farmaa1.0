import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:razorpay_flutter/razorpay_flutter.dart';
import '../../../core/constants/app_constants.dart';
import '../../../core/models/cart_item.dart';
import '../../../core/providers/auth_provider.dart';
import '../../../core/providers/cart_provider.dart';
import '../../../core/providers/notification_provider.dart';
import '../../../core/router/app_router.dart';
import '../../../core/services/order_service.dart';
import '../../../core/services/notification_service.dart';
import '../../../core/theme/app_theme.dart';
import '../../shared/screens/notifications_screen.dart';
import '../../../generated/l10n/app_localizations.dart';

class CheckoutScreen extends ConsumerStatefulWidget {
  final List<CartItem> items;
  final bool isCartCheckout;

  const CheckoutScreen({
    super.key,
    required this.items,
    required this.isCartCheckout,
  });

  @override
  ConsumerState<CheckoutScreen> createState() => _CheckoutScreenState();
}

class _CheckoutScreenState extends ConsumerState<CheckoutScreen> {
  late Razorpay _razorpay;
  bool _isProcessing = false;
  String? _profileError;

  double get _totalAmount =>
      widget.items.fold(0, (sum, item) => sum + item.subtotal);

  @override
  void initState() {
    super.initState();
    _razorpay = Razorpay();
    _razorpay.on(Razorpay.EVENT_PAYMENT_SUCCESS, _handlePaymentSuccess);
    _razorpay.on(Razorpay.EVENT_PAYMENT_ERROR, _handlePaymentError);
    _razorpay.on(Razorpay.EVENT_EXTERNAL_WALLET, _handleExternalWallet);

    WidgetsBinding.instance.addPostFrameCallback((_) => _checkProfile());
  }

  @override
  void dispose() {
    _razorpay.clear();
    super.dispose();
  }

  // ── Profile check ─────────────────────────────────────────────────────────

  void _checkProfile() {
    final user = ref.read(currentUserProvider);
    if (user == null) {
      setState(() => _profileError = 'Please log in to continue.');
      return;
    }
    if (!user.profileCompleted) {
      setState(() => _profileError =
          'Please complete your profile before placing orders.');
      return;
    }
    if (user.mobileNumber == null || user.mobileNumber!.isEmpty) {
      setState(() => _profileError =
          'Please add a mobile number to your profile before ordering.');
      return;
    }
    setState(() => _profileError = null);
  }

  // ── Payment flow ──────────────────────────────────────────────────────────

  void _startPayment() {
    final user = ref.read(currentUserProvider);
    if (user == null || !user.profileCompleted) {
      _showError('Please complete your profile before ordering.');
      Future.delayed(const Duration(seconds: 1), () {
        if (mounted) context.go(AppRoutes.completeProfile);
      });
      return;
    }

    final options = {
      'key': AppConstants.razorpayKey,
      'amount': (_totalAmount * 100).toInt(),
      'name': 'Farmaa',
      'description': widget.items.length == 1
          ? 'Purchase of ${widget.items.first.crop.name}'
          : 'Purchase of ${widget.items.length} items',
      'prefill': {
        'contact': user.mobileNumber ?? '9876543210',
        'email': user.email ??
            '${user.name.replaceAll(' ', '').toLowerCase()}@farmaa.in',
      },
      'theme': {'color': '#1A5E20'},
      'external': {
        'wallets': ['paytm']
      },
    };

    try {
      _razorpay.open(options);
    } catch (e) {
      _showError('Could not open payment gateway: $e');
    }
  }

  void _handlePaymentSuccess(PaymentSuccessResponse response) async {
    setState(() => _isProcessing = true);

    final user = ref.read(currentUserProvider);
    final deliveryAddress = user?.address ??
        (user?.district != null
            ? '${user!.district}${user.postalCode != null ? ', ${user.postalCode}' : ''}'
            : null);

    final successItems = <CartItem>[];
    final failedItems = <CartItem>[];
    final failedReasons = <String>[];

    try {
      for (final item in widget.items) {
        try {
          await OrderService.instance.createOrder(
            cropId: item.crop.id,
            quantityKg: item.quantityKg,
            paymentId: response.paymentId,
            razorpayOrderId: response.orderId,
            signature: response.signature,
            cropName: item.crop.name,
            deliveryAddress: deliveryAddress,
          );
          successItems.add(item);
        } catch (e) {
          debugPrint('[Checkout] Order failed for ${item.crop.name}: $e');
          failedItems.add(item);
          // Extract actual server error message
          String reason = 'Unknown error';
          if (e is DioException && e.response?.data is Map) {
            reason = e.response?.data['detail'] ?? reason;
          } else {
            reason = e.toString().replaceAll('Exception: ', '');
          }
          failedReasons.add('${item.crop.name}: $reason');
        }
      }

      if (widget.isCartCheckout && successItems.isNotEmpty) {
        ref.read(cartNotifierProvider.notifier).clear();
      }

      if (successItems.isNotEmpty) {
        final title = successItems.length == 1
            ? successItems.first.crop.name
            : '${successItems.length} items';

        final totalQty =
            successItems.fold(0.0, (sum, item) => sum + item.quantityKg);

        ref.read(notificationsProvider.notifier).addNotification(
              title: '✅ Order Confirmed!',
              body: 'Your order for $title has been placed. '
                  'Waiting for farmer confirmation.',
              type: NotificationType.order,
            );

        if (mounted) {
          if (failedItems.isNotEmpty) {
            _showError(
                '${successItems.length} order(s) placed. '
                '${failedItems.length} failed:\n${failedReasons.join("\n")}');
          }
          context.go(
            AppRoutes.orderConfirmation,
            extra: {
              'orderId': response.paymentId ??
                  'ORD-${DateTime.now().millisecondsSinceEpoch}',
              'cropName': title,
              'quantity': totalQty,
              'totalAmount':
                  successItems.fold(0.0, (s, i) => s + i.subtotal),
            },
          );
        }
      } else {
        // All orders failed — show detailed error
        final errorMsg = failedReasons.isNotEmpty
            ? 'Order failed:\n${failedReasons.join("\n")}'
            : 'Failed to place orders. Please ensure your profile is complete.';
        _showError(errorMsg);

        await NotificationService.instance.showOrderNotification(
          title: '❌ Order Failed',
          body: 'Your payment was processed but orders could not be placed. '
              'Please contact support.',
        );
      }
    } catch (e) {
      _showError('Failed to process orders: $e');
    } finally {
      if (mounted) setState(() => _isProcessing = false);
    }
  }

  void _handlePaymentError(PaymentFailureResponse response) {
    _showError('Payment failed: ${response.message ?? 'Unknown error'}');
  }

  void _handleExternalWallet(ExternalWalletResponse response) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('External wallet: ${response.walletName}'),
        backgroundColor: AppTheme.warningAmber,
      ),
    );
  }

  void _showError(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(msg, maxLines: 5),
        backgroundColor: AppTheme.errorRed,
        duration: const Duration(seconds: 6),
        action: SnackBarAction(
          label: 'OK',
          textColor: Colors.white,
          onPressed: () {},
        ),
      ),
    );
  }

  // ── Build ─────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final user = ref.watch(currentUserProvider);

    return Scaffold(
      appBar: AppBar(title: Text(l.checkout)),
      body: _isProcessing
          ? Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Container(
                    padding: const EdgeInsets.all(24),
                    decoration: BoxDecoration(
                      color: AppTheme.primaryGreen.withValues(alpha: 0.1),
                      shape: BoxShape.circle,
                    ),
                    child: const CircularProgressIndicator(
                      color: AppTheme.primaryGreen,
                      strokeWidth: 3,
                    ),
                  ),
                  const SizedBox(height: 24),
                  Text(
                    'Processing your order...',
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.w600,
                        ),
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    'Please wait, do not close the app',
                    style: TextStyle(color: AppTheme.textLight, fontSize: 13),
                  ),
                ],
              ),
            )
          : Column(
              children: [
                // Profile warning banner
                if (_profileError != null)
                  _ProfileWarningBanner(
                    message: _profileError!,
                    onTap: () => context.go(AppRoutes.completeProfile),
                  ),

                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.all(20),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          l.orderSummary,
                          style: Theme.of(context)
                              .textTheme
                              .titleLarge
                              ?.copyWith(fontWeight: FontWeight.w700),
                        ),
                        const SizedBox(height: 16),

                        // Items list
                        Expanded(
                          child: ListView.separated(
                            itemCount: widget.items.length,
                            separatorBuilder: (_, __) =>
                                const Divider(height: 20),
                            itemBuilder: (ctx, i) {
                              final item = widget.items[i];
                              return Container(
                                padding: const EdgeInsets.all(12),
                                decoration: BoxDecoration(
                                  color: Colors.white,
                                  borderRadius: AppTheme.radiusMedium,
                                  boxShadow: [
                                    BoxShadow(
                                      color: Colors.black
                                          .withValues(alpha: 0.04),
                                      blurRadius: 8,
                                      offset: const Offset(0, 2),
                                    ),
                                  ],
                                ),
                                child: Column(
                                  crossAxisAlignment:
                                      CrossAxisAlignment.start,
                                  children: [
                                    _summaryRow(
                                      l.crop,
                                      '${item.crop.emoji} ${item.crop.name}',
                                    ),
                                    _summaryRow(
                                      'Farmer',
                                      item.crop.farmerName,
                                    ),
                                    _summaryRow(
                                      l.quantity,
                                      '${item.quantityKg.toStringAsFixed(1)} kg',
                                    ),
                                    _summaryRow(
                                      l.pricePerKg,
                                      '₹${item.crop.pricePerKg.toStringAsFixed(2)}',
                                    ),
                                    const Divider(height: 12),
                                    _summaryRow(
                                      'Subtotal',
                                      '₹${item.subtotal.toStringAsFixed(2)}',
                                      isBold: true,
                                    ),
                                  ],
                                ),
                              );
                            },
                          ),
                        ),

                        // Delivery address
                        if (user?.address != null &&
                            user!.address!.isNotEmpty) ...[
                          const SizedBox(height: 12),
                          Container(
                            width: double.infinity,
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              color: AppTheme.primaryGreen
                                  .withValues(alpha: 0.05),
                              borderRadius: AppTheme.radiusMedium,
                              border: Border.all(
                                color: AppTheme.primaryGreen
                                    .withValues(alpha: 0.2),
                              ),
                            ),
                            child: Row(
                              children: [
                                const Icon(Icons.location_on,
                                    size: 18,
                                    color: AppTheme.primaryGreen),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      const Text(
                                        'Delivery Address',
                                        style: TextStyle(
                                          fontSize: 11,
                                          color: AppTheme.textLight,
                                          fontWeight: FontWeight.w600,
                                        ),
                                      ),
                                      Text(
                                        user.address!,
                                        style: const TextStyle(fontSize: 13),
                                        maxLines: 2,
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],

                        const Divider(height: 24, thickness: 2),

                        _summaryRow(
                          l.totalAmount,
                          '₹${_totalAmount.toStringAsFixed(2)}',
                          isBold: true,
                          fontSize: 20,
                        ),
                        const SizedBox(height: 8),

                        // Secure payment badge
                        Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            const Icon(Icons.lock,
                                size: 14, color: AppTheme.textLight),
                            const SizedBox(width: 4),
                            Text(
                              'Secured by Razorpay',
                              style: Theme.of(context)
                                  .textTheme
                                  .bodySmall
                                  ?.copyWith(color: AppTheme.textLight),
                            ),
                          ],
                        ),
                        const SizedBox(height: 20),

                        // Pay button
                        SizedBox(
                          width: double.infinity,
                          height: 54,
                          child: ElevatedButton.icon(
                            onPressed: _profileError != null
                                ? null
                                : _startPayment,
                            icon: const Icon(Icons.payment),
                            label: Text(
                              _profileError != null
                                  ? 'Complete Profile First'
                                  : '${l.payNow} ₹${_totalAmount.toStringAsFixed(2)}',
                              style: const TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: _profileError != null
                                  ? AppTheme.textLight
                                  : AppTheme.primaryGreen,
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(14),
                              ),
                            ),
                          ),
                        ),

                        if (_profileError != null) ...[
                          const SizedBox(height: 12),
                          SizedBox(
                            width: double.infinity,
                            child: OutlinedButton.icon(
                              onPressed: () =>
                                  context.go(AppRoutes.completeProfile),
                              icon: const Icon(Icons.person_outline),
                              label: const Text('Complete My Profile'),
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
              ],
            ),
    );
  }

  Widget _summaryRow(
    String label,
    String value, {
    bool isBold = false,
    double fontSize = 14,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            label,
            style: const TextStyle(color: AppTheme.textMedium, fontSize: 14),
          ),
          Text(
            value,
            style: TextStyle(
              fontWeight: isBold ? FontWeight.w800 : FontWeight.w600,
              fontSize: fontSize,
              color: isBold ? AppTheme.primaryGreen : AppTheme.textDark,
            ),
          ),
        ],
      ),
    );
  }
}

// ── Profile Warning Banner ────────────────────────────────────────────────────

class _ProfileWarningBanner extends StatelessWidget {
  final String message;
  final VoidCallback onTap;

  const _ProfileWarningBanner({required this.message, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        color: AppTheme.warningAmber.withValues(alpha: 0.15),
        child: Row(
          children: [
            const Icon(Icons.warning_amber_rounded,
                color: AppTheme.warningAmber, size: 20),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                message,
                style: const TextStyle(
                    color: AppTheme.accentAmberDark, fontSize: 13),
              ),
            ),
            const Icon(Icons.arrow_forward_ios,
                size: 14, color: AppTheme.accentAmberDark),
          ],
        ),
      ),
    );
  }
}
