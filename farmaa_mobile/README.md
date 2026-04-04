# 🌾 Farmaa Mobile

> **From Farm to Future.** A digital marketplace connecting farmers and buyers for all grains.

Farmaa is a comprehensive B2B agriculture platform for the Indian market. It bridges the gap between farmers and buyers, enabling transparent pricing, real-time market insights, secure payments, and reliable delivery logistics. 

## ✨ Features

- **Role-Based Workflows:** Distinct profiles and UI for Farmers, Buyers, and Admins.
- **Market Feed:** Real-time crop listings and live price updates (powered by Supabase Realtime).
- **In-App AI Assistant:** AI-powered conversational agent tuned for agricultural advice.
- **Secure Authentication:** Seamless Email & Google Sign-In with Firebase Auth.
- **End-to-End Cart & Checkout:** Shopping cart functionality seamlessly integrated with Razorpay.
- **Live Notifications:** Stay updated with order statuses and price alerts via Firebase Cloud Messaging & local notifications.
- **Bilingual Support:** Fully supported localized languages (English & Tamil).

## 🛠 Tech Stack

- **Framework:** Flutter (Dart)
- **State Management:** Riverpod 3.x (`Notifier`, `NotifierProvider`)
- **Backend/Database:** Supabase
- **Authentication:** Firebase Auth, Google Sign-In
- **Networking:** Dio
- **Routing:** GoRouter
- **Payments:** Razorpay
- **Notifications:** Firebase Cloud Messaging & Flutter Local Notifications

## 📸 Screenshots

![Login Screen](screenshots/login.png)
![Market Feed](screenshots/market_feed.png)
![AI Assistant](screenshots/ai_assistant.png)
![Checkout](screenshots/checkout.png)

*(Add actual screenshots to the `screenshots/` directory)*

## 🚀 Getting Started

### Prerequisites

- Flutter SDK `^3.3.0`
- Dart SDK `^3.3.0 <4.0.0`
- Android Studio / Xcode

### Environment Variables

Create a `.env` file in the root directory and add the following keys:

```env
SUPABASE_URL=
SUPABASE_ANON_KEY=
ENVIRONMENT=
BASE_URL=
RAZORPAY_KEY=
RAZORPAY_SECRET=
```

### Installation

1. **Clone the repository:**
   ```bash
   git clone https://github.com/YOUR_USERNAME/YOUR_REPO.git
   cd farmaa_mobile
   ```

2. **Install dependencies:**
   ```bash
   flutter pub get
   ```

3. **Run code generation (if modifying Riverpod/Freezed/JSON):**
   ```bash
   flutter pub run build_runner build --delete-conflicting-outputs
   ```

4. **Run the app:**
   ```bash
   flutter run
   ```

### Building for Production

To build a release APK for Android:

```bash
flutter build apk --release
```

## 📂 Folder Structure

```text
lib/
├── core/                  # Core infrastructure, themes, routing, and shared services
│   ├── api/
│   ├── config/
│   ├── constants/
│   ├── providers/         # Global Riverpod providers
│   ├── router/            # GoRouter configuration
│   └── services/          # Firebase, Supabase, Notifications, Auth
├── features/              # Feature-first modules
│   ├── admin/
│   ├── ai_chat/           # Farmer AI Assistant
│   ├── auth/              # Login, Onboarding, Splash
│   ├── cart_checkout/     # Payments and Cart logic
│   ├── market/            # Live Market Prices and Feed
│   ├── my_crops/          # Crop management
│   └── shared/            # Common UI components, headers, shells
├── generated/             # Auto-generated code (Intl)
├── l10n/                  # Localization files (.arb)
└── main.dart              # Application entry point
```

## 📥 Download Latest APK

Ready to test? Download the latest stable release directly:

[Download APK](https://github.com/YOUR_USERNAME/YOUR_REPO/releases/latest)

## 🤝 Contributing & License

Contributions, issues, and feature requests are welcome!
Feel free to check [issues page](https://github.com/YOUR_USERNAME/YOUR_REPO/issues).

Distributed under the MIT License. See `LICENSE` for more information.
