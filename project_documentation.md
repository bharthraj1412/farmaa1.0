# Farmaa Project Documentation

## 1. Project Overview
Farmaa is a digital agricultural marketplace application designed to connect farmers and buyers. The project consists of a mobile application frontend built with Flutter and a RESTful API backend built with FastAPI (Python).

## 2. Backend Architecture (`farmaa_backend`)
The backend is a production-ready REST API designed to handle all core business logic and database interactions.
- **Framework**: FastAPI serving via Uvicorn.
- **Language**: Python 3.
- **Database**: PostgreSQL hosted on Supabase, utilizing SQLAlchemy as the ORM layer.
- **Entry Point**: [main.py](file:///g:/farmaa%20project/farmaa_backend/main.py) which configures CORS, Rate Limiting (`slowapi`), security headers, and router inclusion.

### 2.1 Key Backend Files
- [main.py](file:///g:/farmaa%20project/farmaa_backend/main.py): The Main FastAPI application instance. Handles startup events to ensure DB connectivity, configures restrictive CORS in production, and provides a global exception handler.
- [database.py](file:///g:/farmaa%20project/farmaa_backend/database.py): Manages the database connection pool using an SQLAlchemy engine. Connects to Supabase PostgreSQL using `psycopg2`. Provides the [get_db](file:///g:/farmaa%20project/farmaa_backend/database.py#64-78) generator dependency used by all routes to perform transactions safely.
- [models.py](file:///g:/farmaa%20project/farmaa_backend/models.py): Defines the relational database schemas via SQLAlchemy ORMs, including:
  - [User](file:///g:/farmaa%20project/farmaa_backend/models.py#16-35): Contains details of both farmers and buyers, linked dynamically by a `role` field and synced to their Firebase UID.
  - [Crop](file:///g:/farmaa%20project/farmaa_backend/models.py#37-59): Represents the agricultural products (grains, vegetables) listed by farmers, tracking inventory and price.
  - [Order](file:///g:/farmaa%20project/farmaa_backend/models.py#61-81): Manages transaction states between buyers and sellers, integrating references to payment IDs.
  - [MarketPrice](file:///g:/farmaa%20project/farmaa_backend/models.py#83-93): Tracks ongoing general market prices for various crops.
- [requirements.txt](file:///g:/farmaa%20project/farmaa_backend/requirements.txt): Outlines necessary dependencies including `fastapi`, `sqlalchemy`, `firebase-admin`, and `psycopg2-binary`.
- `routers/`: Contains modular API endpoint files grouping related functions together (`auth`, `crops`, `orders`, `market`, and [ai](file:///g:/farmaa%20project/farmaa_mobile/lib/main.dart#19-65) routers).

## 3. Frontend Architecture (`farmaa_mobile`)
The frontend is a cross-platform mobile app targeting Android and iOS.
- **Framework**: Flutter (Dart).
- **State Management**: Riverpod (`flutter_riverpod` and code-generation via `riverpod_annotation`), enforcing robust and reactive UI updates.
- **Routing**: GoRouter for deep-linkable and declarative navigation.
- **Networking**: Dio package for making and intercepting HTTP requests.
- **UI/UX**: Extensive use of Google Fonts for modern typography, `fl_chart` for market data visualization, and Lottie for dynamic animations.

### 3.1 Key Frontend Modules (`lib/`)
- [main.dart](file:///g:/farmaa%20project/farmaa_mobile/lib/main.dart): The initialization sequence of the Flutter app. Starts essential services like Firebase, Supabase, and notification managers before rendering the [FarmaaApp](file:///g:/farmaa%20project/farmaa_mobile/lib/main.dart#71-136) within a `ProviderScope`.
- [core/api/api_client.dart](file:///g:/farmaa%20project/farmaa_mobile/lib/core/api/api_client.dart): A centralized singleton [Dio](file:///g:/farmaa%20project/farmaa_mobile/lib/core/api/api_client.dart#63-93) REST client. It establishes connections to the backend, automatically attaches authorization tokens (Firebase JWT) via [_AuthInterceptor](file:///g:/farmaa%20project/farmaa_mobile/lib/core/api/api_client.dart#97-136), formats user-friendly error messages with [_ErrorInterceptor](file:///g:/farmaa%20project/farmaa_mobile/lib/core/api/api_client.dart#139-205), and employs a circuit breaker to prevent hammering offline servers.
- [core/config/environment_config.dart](file:///g:/farmaa%20project/farmaa_mobile/lib/core/config/environment_config.dart): A utility loading the [.env](file:///g:/farmaa%20project/farmaa_mobile/.env) configuration file, dynamically setting endpoints like `BASE_URL` depending on whether the app is executing in a development or production context.
- `features/`: Feature-sliced directories encapsulating their own UI screens and logic:
  - `auth/`: Login and Registration flows using Firebase integrations.
  - `market/`: Buyer-facing interfaces showing crops available for purchase.
  - `my_crops/`: Farmer-centric dashboard allowing for crop inventory management.
  - `cart_checkout/`: Shopping cart functions and integration with Razorpay for checkouts.
  - `ai_chat/`: An AI assistant interface utilizing the `/ai/` backend endpoints.

## 4. Database Connections and Third-Party Integrations
- **Primary Database Link (PostgreSQL)**: The FastAPI backend connects directly to the Supabase PostgreSQL database via SQLAlchemy using a `postgresql://` URI provided by the environment variable. The Flutter mobile application **never** talks directly to the Postgres database; it interfaces solely via the Python backend, maintaining absolute security and business logic abstraction.
- **Authentication Handshake**: Authentication uses a decoupled standard. The Flutter application integrates directly with **Firebase Auth** (via the `firebase_auth` plugin) for sign-up and login securely capturing device identity. Instead of issuing its own session tokens from scratch, the mobile app extracts the strict Firebase ID JWT Token. This token is packaged in the `Authorization: Bearer <token>` header on every backend API request. The Python backend then receives this JWT, and cryptographically challenges and verifies it against Google's Firebase Admin SDK to establish the user's identity on the backend.
- **Supabase SDK**: The Mobile App does initialize a Supabase Client (`Supabase.initialize`), which is typically utilized for subscribing to real-time events over WebSockets or securely retrieving image blobs from Supabase Storage without putting unnecessary high-bandwidth load on the Python FastAPI server.
- **Payment Gateway**: Transactions are handled natively on the frontend via Razorpay (`razorpay_flutter`). Order IDs and signatures generated upon checkout are routed through the backend for strict verification against price manipulation.

## 5. Frontend & Backend API Linking
The frontend (`farmaa_mobile`) and backend (`farmaa_backend`) communicate seamlessly over standard HTTPS protocols.
- **Production Anchor**: When deployed, the mobile app strictly points to the Vercel-deployed server at `https://farmaa1-0.vercel.app`.
- **Development Operations**: When running locally, the mobile app gracefully defaults to the standard emulator bridging IP `http://10.0.2.2:10000`, equipped with an auto-discovery protocol (`DiscoveryService`) to find local loopback endpoints.
- **Request Lifecycle**: 
  1. Action executed in Flutter UI (e.g. buying a crop).
  2. Riverpod calls a repository, utilizing the configured [ApiClient](file:///g:/farmaa%20project/farmaa_mobile/lib/core/api/api_client.dart#10-94).
  3. Dio grabs the current Firebase Authentication JWT and injects it.
  4. The request hits a FastAPI router (e.g., [orders_router.py](file:///g:/farmaa%20project/farmaa_backend/routers/orders_router.py)).
  5. The backend validates the Firebase token, converts the UID to a local SQL [User](file:///g:/farmaa%20project/farmaa_backend/models.py#16-35), opens a database transaction ([get_db](file:///g:/farmaa%20project/farmaa_backend/database.py#64-78)), modifies the `orders` output, closes the database connection, and answers back with a JSON response which the frontend parses.
