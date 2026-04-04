"""JWT token creation and verification with enhanced security."""

import os
import logging
from datetime import datetime, timedelta, timezone
from jose import JWTError, jwt
from fastapi import Depends, HTTPException, status
from fastapi.security import HTTPBearer, HTTPAuthorizationCredentials
from dotenv import load_dotenv

load_dotenv()

logger = logging.getLogger(__name__)

# ── Configuration ────────────────────────────────────────────────────────────

ENVIRONMENT = os.getenv("ENVIRONMENT", "development")
SECRET_KEY = os.getenv("SECRET_KEY")

# Enforce strong secret in production
if ENVIRONMENT == "production" and (not SECRET_KEY or SECRET_KEY.startswith("farmaa-dev")):
    logger.critical("[Farmaa] CRITICAL: SECRET_KEY is not set or using dev default in production!")
    raise RuntimeError("SECRET_KEY must be set to a strong value in production")

# Fallback for development only
if not SECRET_KEY:
    SECRET_KEY = "farmaa-dev-secret-NOT-FOR-PRODUCTION"
    logger.warning("[Farmaa] Using development SECRET_KEY. DO NOT use in production!")

ALGORITHM = "HS256"
# FIX: exported so auth_router and Flutter client can align on the same value
ACCESS_TOKEN_EXPIRY_MINUTES = 10080  # 7 days
REFRESH_TOKEN_EXPIRY_DAYS = 30

ISSUER = "farmaa-api"
AUDIENCE = "farmaa-mobile"

security = HTTPBearer(auto_error=False)


# ── Token Creation ───────────────────────────────────────────────────────────

def create_access_token(data: dict) -> str:
    """Create a JWT access token with standard claims."""
    to_encode = data.copy()
    now = datetime.now(timezone.utc)
    expire = now + timedelta(minutes=ACCESS_TOKEN_EXPIRY_MINUTES)
    to_encode.update({
        "exp": expire,
        "iat": now,
        "iss": ISSUER,
        "aud": AUDIENCE,
        "type": "access",
    })
    return jwt.encode(to_encode, SECRET_KEY, algorithm=ALGORITHM)


def create_refresh_token(data: dict) -> str:
    """Create a long-lived refresh token."""
    to_encode = {"sub": data.get("sub")}
    now = datetime.now(timezone.utc)
    expire = now + timedelta(days=REFRESH_TOKEN_EXPIRY_DAYS)
    to_encode.update({
        "exp": expire,
        "iat": now,
        "iss": ISSUER,
        "aud": AUDIENCE,
        "type": "refresh",
    })
    return jwt.encode(to_encode, SECRET_KEY, algorithm=ALGORITHM)


# ── Token Verification ──────────────────────────────────────────────────────

def verify_token(token: str, expected_type: str = "access") -> dict:
    """Verify and decode a JWT token with claim validation."""
    try:
        payload = jwt.decode(
            token,
            SECRET_KEY,
            algorithms=[ALGORITHM],
            audience=AUDIENCE,
            issuer=ISSUER,
        )
        # Validate token type
        token_type = payload.get("type", "access")
        if token_type != expected_type:
            raise HTTPException(
                status_code=status.HTTP_401_UNAUTHORIZED,
                detail=f"Invalid token type. Expected {expected_type}.",
            )
        return payload
    except JWTError as e:
        logger.warning(f"[Farmaa] Token verification failed: {e}")
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="Invalid or expired token",
        )


def get_current_user_id(
    credentials: HTTPAuthorizationCredentials = Depends(security),
) -> str:
    """FastAPI dependency – extracts user_id from Bearer token."""
    if credentials is None:
        raise HTTPException(status_code=401, detail="Not authenticated")

    token = credentials.credentials
    payload = verify_token(token)   # raises 401 on failure
    user_id = payload.get("sub")
    if not user_id:
        raise HTTPException(status_code=401, detail="Invalid token: missing subject")
    return user_id


# ── Firebase / Google ID Token Verification ─────────────────────────────────

_firebase_initialized = False
_firebase_available = False

FIREBASE_PROJECT_ID = os.getenv("FIREBASE_PROJECT_ID", "farmaa-bdbe3")


def _init_firebase():
    """Initialize Firebase Admin SDK (lazy, once)."""
    global _firebase_initialized, _firebase_available
    if _firebase_initialized:
        return
    try:
        import firebase_admin
        from firebase_admin import credentials as fb_credentials

        if not firebase_admin._apps:
            cred_path = os.getenv("FIREBASE_CREDENTIALS_PATH")
            cred_json = os.getenv("FIREBASE_CREDENTIALS_JSON")

            if cred_json:
                import json
                cred_dict = json.loads(cred_json)
                cred = fb_credentials.Certificate(cred_dict)
                firebase_admin.initialize_app(cred)
                _firebase_available = True
            elif cred_path and os.path.exists(cred_path):
                cred = fb_credentials.Certificate(cred_path)
                firebase_admin.initialize_app(cred)
                _firebase_available = True
            else:
                logger.warning("[Farmaa] No Firebase credentials found. Using Google public-key fallback.")
                _firebase_available = False
        else:
            _firebase_available = True

        _firebase_initialized = True
        if _firebase_available:
            logger.info("[Farmaa] Firebase Admin SDK initialised successfully")
    except Exception as e:
        logger.error(f"[Farmaa] Firebase Admin SDK init failed: {e}")
        _firebase_initialized = True
        _firebase_available = False


def _verify_with_firebase(id_token: str) -> dict:
    """Verify using Firebase Admin SDK (requires service account credentials)."""
    from firebase_admin import auth as firebase_auth
    decoded_token = firebase_auth.verify_id_token(id_token)
    return {
        "uid": decoded_token.get("uid"),
        "sub": decoded_token.get("sub") or decoded_token.get("user_id"),
        "email": decoded_token.get("email"),
        "name": decoded_token.get("name", "User"),
        "picture": decoded_token.get("picture"),
        "email_verified": decoded_token.get("email_verified", False),
    }


def _verify_with_google_public_keys(id_token: str) -> dict:
    """Verify Firebase ID token using Google's public certificates (no service account needed)."""
    from google.oauth2 import id_token as google_id_token
    from google.auth.transport import requests as google_requests

    decoded = google_id_token.verify_firebase_token(
        id_token,
        google_requests.Request(),
        audience=FIREBASE_PROJECT_ID,
    )

    return {
        "uid": decoded.get("user_id") or decoded.get("sub"),
        "sub": decoded.get("sub"),
        "email": decoded.get("email"),
        "name": decoded.get("name", "User"),
        "picture": decoded.get("picture"),
        "email_verified": decoded.get("email_verified", False),
    }


def verify_firebase_id_token(id_token: str) -> dict | None:
    """Verify a Firebase ID token and return user info.

    Strategy:
    1. Try Firebase Admin SDK (if credentials are available)
    2. Fall back to Google public-key verification (always works)

    Returns dict with: uid, email, name, picture, email_verified
    Returns None if all verification methods fail.
    """
    _init_firebase()
    if _firebase_available:
        try:
            result = _verify_with_firebase(id_token)
            logger.debug("[Farmaa] Token verified via Firebase Admin SDK")
            return result
        except Exception as e:
            logger.warning(f"[Farmaa] Firebase Admin verification failed: {e}")

    try:
        result = _verify_with_google_public_keys(id_token)
        logger.info("[Farmaa] Token verified via Google public keys")
        return result
    except Exception as e:
        logger.error(f"[Farmaa] Google public-key verification also failed: {e}")
        return None
