import 'package:flutter/foundation.dart';
import '../api/api_client.dart';
import '../models/order_model.dart';
import 'notification_service.dart';

/// Manages order placement and status updates with integrated local notifications.
class OrderService {
  OrderService._();
  static final OrderService instance = OrderService._();

  final _dio = ApiClient().dio;

  // ── Fetch orders ──────────────────────────────────────────────────────────

  /// Fetches all orders where the current user is buyer or seller.
  Future<List<OrderModel>> getMyOrders() async {
    final response = await _dio.get('/orders/my-orders');
    final list = (response.data as List<dynamic>?) ?? [];
    return list
        .map((e) => OrderModel.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  /// Fetch a single order by ID.
  Future<OrderModel> getOrderById(String orderId) async {
    final response = await _dio.get('/orders/$orderId');
    return OrderModel.fromJson(response.data as Map<String, dynamic>);
  }

  // ── Place order ───────────────────────────────────────────────────────────

  /// Places a new order and shows a local confirmation notification.
  Future<OrderModel> createOrder({
    required String cropId,
    required double quantityKg,
    String? paymentId,
    String? razorpayOrderId,
    String? signature,
    String? cropName,
    String? deliveryAddress,
  }) async {
    try {
      final response = await _dio.post('/orders/', data: {
        'crop_id': cropId,
        'quantity_kg': quantityKg,
        if (paymentId != null) 'payment_id': paymentId,
        if (razorpayOrderId != null) 'razorpay_order_id': razorpayOrderId,
        if (signature != null) 'razorpay_signature': signature,
        if (deliveryAddress != null && deliveryAddress.isNotEmpty)
          'delivery_address': deliveryAddress,
      });

      final order =
          OrderModel.fromJson(response.data as Map<String, dynamic>);

      // Show order confirmation notification
      final name = cropName ?? order.cropName;
      await NotificationService.instance.showOrderNotification(
        title: '✅ Order Confirmed!',
        body: 'Your order for ${quantityKg.toStringAsFixed(0)} kg of $name '
            '(₹${order.totalAmount.toStringAsFixed(0)}) has been placed. '
            'Waiting for farmer confirmation.',
        orderId: order.id,
      );

      return order;
    } catch (e) {
      debugPrint('[OrderService] createOrder failed: $e');
      rethrow;
    }
  }

  // ── Update order status ───────────────────────────────────────────────────

  /// Updates the status of an order with role-appropriate notification.
  Future<OrderModel> updateOrderStatus(
    String orderId,
    String status, {
    String? cropName,
    bool isFarmerAction = false,
  }) async {
    try {
      final response = await _dio.patch(
        '/orders/$orderId/status',
        data: {'status': status},
      );

      final order =
          OrderModel.fromJson(response.data as Map<String, dynamic>);
      final name = cropName ?? order.cropName;

      // Show status-specific notification
      await _notifyStatusChange(order, name, isFarmerAction);

      return order;
    } catch (e) {
      debugPrint('[OrderService] updateOrderStatus failed: $e');
      rethrow;
    }
  }

  Future<void> _notifyStatusChange(
    OrderModel order,
    String cropName,
    bool isFarmerAction,
  ) async {
    String title;
    String body;

    switch (order.status) {
      case OrderStatus.confirmed:
        title = '🎉 Order Confirmed';
        body = isFarmerAction
            ? 'You confirmed the order for $cropName. Please prepare shipment.'
            : 'The farmer has confirmed your order for $cropName!';
        break;

      case OrderStatus.processing:
        title = '⚙️ Order Processing';
        body = 'Your order for $cropName is being prepared for shipment.';
        break;

      case OrderStatus.shipped:
        title = '🚚 Order Shipped';
        body = 'Great news! Your $cropName order is on its way.';
        break;

      case OrderStatus.delivered:
        title = '✅ Order Delivered';
        body =
            'Your $cropName has been delivered. Thank you for using Farmaa!';
        break;

      case OrderStatus.cancelled:
        title = '❌ Order Cancelled';
        body = 'The order for $cropName has been cancelled. '
            'Stock has been restored.';
        break;

      default:
        return; // No notification for pending/other statuses
    }

    await NotificationService.instance.showOrderNotification(
      title: title,
      body: body,
      orderId: order.id,
    );
  }
}
