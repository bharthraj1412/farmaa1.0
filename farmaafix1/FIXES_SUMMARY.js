// ============================================================
// FARMAA — Complete Fix Summary
// ============================================================
// This file documents all changes needed. Copy each section
// to the corresponding file in your project.
// ============================================================

// ─────────────────────────────────────────────────────────────
// FIX 1: Android permission for notifications (API 33+)
// File: farmaa_mobile/android/app/src/main/AndroidManifest.xml
// Add BEFORE <application> tag:
// ─────────────────────────────────────────────────────────────
/*
<uses-permission android:name="android.permission.INTERNET"/>
<uses-permission android:name="android.permission.ACCESS_NETWORK_STATE"/>
<uses-permission android:name="android.permission.RECEIVE_BOOT_COMPLETED"/>
<uses-permission android:name="android.permission.VIBRATE"/>
<uses-permission android:name="android.permission.POST_NOTIFICATIONS"/>
*/

// ─────────────────────────────────────────────────────────────
// FIX 2: sales_tab.dart — pass isFarmerAction to updateOrderStatus
// File: farmaa_mobile/lib/features/shared/screens/sales_tab.dart
// Change _updateStatus method:
// ─────────────────────────────────────────────────────────────
/*
Future<void> _updateStatus(String orderId, String status) async {
  try {
    final order = _orders.firstWhere((o) => o.id == orderId);
    await OrderService.instance.updateOrderStatus(
      orderId,
      status,
      cropName: order.cropName,
      isFarmerAction: true,  // Add this
    );
    await _load();
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Order $status successfully'),
          backgroundColor: (status == 'confirmed' || status == 'delivered')
              ? AppTheme.successGreen
              : AppTheme.errorRed,
        ),
      );
    }
  } catch (e) {
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
            content: Text(e.toString()), backgroundColor: AppTheme.errorRed),
      );
    }
  }
}
*/

// ─────────────────────────────────────────────────────────────
// FIX 3: pubspec.yaml — no changes needed
// All packages already included in your pubspec.yaml
// ─────────────────────────────────────────────────────────────

// ─────────────────────────────────────────────────────────────
// FIX 4: Supabase SQL — run this to clean up duplicate mobiles
// Run in Supabase SQL Editor to fix existing data:
// ─────────────────────────────────────────────────────────────
/*
-- Find and fix duplicate mobile numbers
-- Step 1: View duplicates
SELECT mobile_number, COUNT(*) as cnt, 
       array_agg(id) as user_ids,
       array_agg(profile_completed::text) as profiles,
       array_agg(firebase_uid) as uids
FROM users 
WHERE mobile_number IS NOT NULL
GROUP BY mobile_number 
HAVING COUNT(*) > 1;

-- Step 2: Clear mobile from incomplete/orphan accounts (safe to run)
UPDATE users u1
SET mobile_number = NULL
WHERE mobile_number IS NOT NULL
  AND profile_completed = FALSE
  AND EXISTS (
    SELECT 1 FROM users u2
    WHERE u2.mobile_number = u1.mobile_number
      AND u2.id != u1.id
      AND u2.profile_completed = TRUE
  );

-- Step 3: Also clear from accounts with no firebase_uid (legacy)
UPDATE users
SET mobile_number = NULL
WHERE firebase_uid IS NULL
  AND google_id IS NULL
  AND mobile_number IN (
    SELECT mobile_number FROM users
    WHERE firebase_uid IS NOT NULL
      AND mobile_number IS NOT NULL
  );
*/
