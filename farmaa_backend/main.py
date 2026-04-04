"""Farmaa API – Production-ready FastAPI backend.

WebSocket endpoint: /market/ws/prices  (self-hosted only)
For Vercel: use Supabase Realtime from the Flutter client instead.
"""

import os
import traceback
from contextlib import asynccontextmanager
from fastapi import FastAPI, Request
from fastapi.middleware.cors import CORSMiddleware
from fastapi.responses import JSONResponse, HTMLResponse

from database import Base, engine
from routers import auth_router, crops_router, orders_router, ai_router, market_router
from middleware import SecurityHeadersMiddleware, RequestLoggingMiddleware

ENVIRONMENT = os.getenv("ENVIRONMENT", "development")


@asynccontextmanager
async def lifespan(app: FastAPI):
    if engine is not None:
        try:
            from database import create_tables, check_database_health
            is_healthy, message = check_database_health()
            if is_healthy:
                success = create_tables()
                if success:
                    print("[Farmaa] Database initialized successfully ✓")
                else:
                    print("[Farmaa] WARNING: Database table creation failed")
            else:
                print(f"[Farmaa] WARNING: Database health check failed: {message}")
        except Exception as e:
            print(f"[Farmaa] WARNING: Could not initialize DB on startup: {e}")
    else:
        print("[Farmaa] WARNING: No DATABASE_URL configured. Running without database.")
    yield


# ── App ──
app = FastAPI(
    title="Farmaa API",
    version="1.1.0",
    docs_url="/docs",
    redoc_url="/redoc",
    lifespan=lifespan,
)

# ── Security Middleware ──
app.add_middleware(SecurityHeadersMiddleware)
app.add_middleware(RequestLoggingMiddleware)

# ── CORS ──
if ENVIRONMENT == "production":
    allowed_origins = [
        "https://farmaa1-0.vercel.app",
        "https://farmaa.app",
        "https://www.farmaa.app",
    ]
else:
    allowed_origins = ["*"]

app.add_middleware(
    CORSMiddleware,
    allow_origins=allowed_origins,
    allow_credentials=True,
    allow_methods=["GET", "POST", "PUT", "PATCH", "DELETE", "OPTIONS"],
    allow_headers=["Authorization", "Content-Type", "Accept", "X-App-Version", "X-Request-ID"],
    expose_headers=["X-Request-ID"],
)

# ── Rate Limiting ──
try:
    from slowapi import Limiter, _rate_limit_exceeded_handler
    from slowapi.util import get_remote_address
    from slowapi.errors import RateLimitExceeded

    limiter = Limiter(key_func=get_remote_address, default_limits=["200/minute"])
    app.state.limiter = limiter
    app.add_exception_handler(RateLimitExceeded, _rate_limit_exceeded_handler)
except ImportError:
    print("[Farmaa] WARNING: slowapi not installed. Rate limiting disabled.")
    limiter = None

# ── Routers ──
app.include_router(auth_router)
app.include_router(crops_router)
app.include_router(orders_router)
app.include_router(ai_router)
app.include_router(market_router)


# ── Global Exception Handler ──
@app.exception_handler(Exception)
async def global_exception_handler(request: Request, exc: Exception):
    request_id = getattr(request.state, "request_id", "unknown")
    traceback.print_exc()
    return JSONResponse(
        status_code=500,
        content={
            "detail": "Internal server error. Please try again later.",
            "request_id": request_id,
        },
    )


# ── Health Checks ──
@app.get("/health")
def health():
    return {"status": "ok", "environment": ENVIRONMENT, "version": "1.1.0"}


@app.get("/health/db")
def health_db():
    from database import check_database_health
    is_healthy, message = check_database_health()
    return {
        "status": "ok",
        "environment": ENVIRONMENT,
        "database": {"connected": is_healthy, "message": message},
    }


@app.get("/health/ws")
def health_ws():
    """Check how many WebSocket clients are connected."""
    from routers.market_router import price_manager
    return {
        "status": "ok",
        "websocket_clients": len(price_manager.active),
        "note": "WebSocket at /market/ws/prices (self-hosted only; use Supabase Realtime on Vercel)",
    }


@app.get("/favicon.ico", include_in_schema=False)
@app.get("/favicon.png", include_in_schema=False)
async def favicon():
    return JSONResponse(status_code=204, content=None)


@app.get("/")
def root():
    return {
        "name":           "Farmaa API",
        "version":        "1.1.0",
        "status":         "online",
        "docs":           "/docs",
        "websocket":      "/market/ws/prices",
        "privacy_policy": "/privacy",
        "terms_of_service": "/tos",
    }


# ── Legal Pages ──
@app.get("/privacy", response_class=HTMLResponse)
def privacy_policy():
    return """
    <html>
        <head><title>Privacy Policy - Farmaa</title>
        <style>body{font-family:sans-serif;line-height:1.6;max-width:800px;margin:40px auto;padding:20px;color:#333}h1{color:#2e7d32}h2{color:#388e3c;margin-top:20px}</style>
        </head>
        <body>
            <h1>Privacy Policy for Farmaa</h1>
            <p>Last Updated: April 04, 2026</p>
            <p>Farmaa ("we," "our," or "us") is committed to protecting your privacy.</p>
            <h2>1. Information We Collect</h2>
            <p><strong>Google Account Information:</strong> When you sign in via Google, we collect your name, email address, and profile picture.</p>
            <h2>2. How We Use Your Information</h2>
            <ul><li>Authentication and account management.</li><li>Facilitate transactions between farmers and buyers.</li><li>Communicate app updates and support.</li></ul>
            <h2>3. Information Sharing</h2>
            <p>We do not sell your personal information.</p>
            <h2>4. Data Security</h2>
            <p>We implement TLS encryption, JWT-based authentication, and secure database connections.</p>
            <h2>5. Contact Us</h2>
            <p>Email: <strong>bharathraj1412p@gmail.com</strong></p>
        </body>
    </html>
    """


@app.get("/tos", response_class=HTMLResponse)
def terms_of_service():
    return """
    <html>
        <head><title>Terms of Service - Farmaa</title>
        <style>body{font-family:sans-serif;line-height:1.6;max-width:800px;margin:40px auto;padding:20px;color:#333}h1{color:#1565c0}h2{color:#1976d2;margin-top:20px}</style>
        </head>
        <body>
            <h1>Terms of Service for Farmaa</h1>
            <p>Last Updated: April 04, 2026</p>
            <h2>1. Use of Service</h2>
            <p>You must use Farmaa in compliance with all applicable laws.</p>
            <h2>2. User Conduct</h2>
            <p>Users must provide accurate information regarding crops and pricing. Fraudulent activity will lead to account termination.</p>
            <h2>3. Liability</h2>
            <p>Farmaa is a platform connecting users and is not responsible for the quality of goods beyond our platform's technical scope.</p>
            <h2>4. Contact</h2>
            <p>For support: <strong>bharathraj1412p@gmail.com</strong></p>
        </body>
    </html>
    """
