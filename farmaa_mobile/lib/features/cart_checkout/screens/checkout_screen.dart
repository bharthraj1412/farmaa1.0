import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:razorpay_flutter/razorpay_flutter.dart';
import '../../../core/constants/app_constants.dart';
import '../../../core/models/cart_item.dart';
import '../../../core/providers/cart_provider.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/router/app_router.dart';
import '../../../core/services/order_service.dart';
import '../../../core/services/notification_service.dart';
import '../../../core/providers/auth_provider.dart';
import '../../../core/api/api_client.dart';
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

  double get _totalAmount =>
      widget.items.fold(0, (sum, item) => sum + item.subtotal);

  @override
  void initState() {
    super.initState();
    _razorpay = Razorpay();
    _razorpay.on(Razorpay.EVENT_PAYMENT_SUCCESS, _handlePaymentSuccess);
    _razorpay.on(Razorpay.EVENT_PAYMENT_ERROR, _handlePaymentError);
    _razorpay.on(Razorpay.EVENT_EXTERNAL_WALLET, _handleExternalWallet);
  }

  @override
  void dispose() {
    _razorpay.clear();
    super.dispose();
  }

  void _startPayment() {
    final user = ref.read(currentUserProvider);
    ApiClient().resetCircuitBreaker();

    var options = {
      'key': AppConstants.razorpayKey,
      'amount': (_totalAmount * 100).toInt(), // Amount in paise
      'name': 'Farmaa',
      'description': widget.items.length == 1
          ? 'Purchase of ${widget.items.first.crop.name}'
          : 'Purchase of ${widget.items.length} items',
      'prefill': {
        'contact': user?.mobileNumber ?? '9876543210',
        'email':
            '${user?.name.replaceAll(' ', '').toLowerCase() ?? 'user'}@farmaa.in'
      },
      'external': {
        'wallets': ['paytm']
      }
    };

    try {
      _razorpay.open(options);
    } catch (e) {
      debugPrint('Error: $e');
    }
  }

  void _handlePaymentSuccess(PaymentSuccessResponse response) async {
    setState(() => _isProcessing = true);

    try {
      // POST order to backend via OrderService for EACH item
      for (final item in widget.items) {
        await OrderService.instance.createOrder(
          cropId: item.crop.id,
          quantityKg: item.quantityKg,
          paymentId: response.paymentId,
          razorpayOrderId: response.orderId,
          signature: response.signature,
        );
      }

      // If it was a cart checkout, clear the cart!
      if (widget.isCartCheckout) {
        ref.read(cartNotifierProvider.notifier).clear();
      }
      
      final title = widget.items.length == 1
          ? widget.items.first.crop.name
          : 'Multiple Items (${widget.items.length})';
          
      // Show local notification
      await NotificationService.instance.showLocal(
        title: 'Order Confirmed ✅',
        body: 'Your order for $title has been placed successfully.',
      );

      if (mounted) {
        final totalQty = widget.items.fold(0.0, (sum, item) => sum + item.quantityKg);

        context.go(
          AppRoutes.orderConfirmation,
          extra: {
            'orderId': response.paymentId ??
                'ORD-${DateTime.now().millisecondsSinceEpoch}',
            'cropName': title,
            'quantity': totalQty,
            'totalAmount': _totalAmount,
          },
        );
      }
    } catch (e) {
      if (mounted) {
        _showError('Failed to record order: $e');
      }
    } finally {
      if (mounted) setState(() => _isProcessing = false);
    }
  }

  void _handlePaymentError(PaymentFailureResponse response) {
    _showError('Payment failed: ${response.message}');
  }

  void _handleExternalWallet(ExternalWalletResponse response) {
    _showError('External wallet selected: ${response.walletName}');
  }

  void _showError(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(msg),
        backgroundColor: AppTheme.errorRed,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);

    return Scaffold(
      appBar: AppBar(title: Text(l.checkout)),
      body: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(l.orderSummary, style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 16),
            
            // Item list summary
            Expanded(
              child: ListView.separated(
                itemCount: widget.items.length,
                separatorBuilder: (_, __) => const Divider(height: 16),
                itemBuilder: (context, index) {
                  final item = widget.items[index];
                  return Column(
                    children: [
                      _summaryRow(l.crop, item.crop.name),
                      _summaryRow(l.quantity, '${item.quantityKg.toStringAsFixed(1)} kg'),
                      _summaryRow(
                          l.pricePerKg, '₹${item.crop.pricePerKg.toStringAsFixed(2)}'),
                      _summaryRow('Subtotal', '₹${item.subtotal.toStringAsFixed(2)}'),
                    ],
                  );
                },
              ),
            ),
            
            const Divider(height: 32, thickness: 2),
            _summaryRow(l.totalAmount, '₹${_totalAmount.toStringAsFixed(2)}',
                isBold: true),
            const SizedBox(height: 24),
            
            SizedBox(
              width: double.infinity,
              height: 54,
              child: ElevatedButton(
                onPressed: _isProcessing ? null : _startPayment,
                child: _isProcessing
                    ? const CircularProgressIndicator(color: Colors.white)
                    : Text(l.payNow),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _summaryRow(String label, String value, {bool isBold = false}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: const TextStyle(color: AppTheme.textMedium)),
          Text(
            value,
            style: TextStyle(
              fontWeight: isBold ? FontWeight.w800 : FontWeight.w600,
              fontSize: isBold ? 18 : 14,
              color: isBold ? AppTheme.primaryGreen : AppTheme.textDark,
            ),
          ),
        ],
      ),
    );
  }
}
