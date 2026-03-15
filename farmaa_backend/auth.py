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
    """FastAPI dependency – extracts user_id from Bearer token.
    
    Accepts both Firebase ID tokens and legacy custom JWTs.
    For Firebase tokens, resolves the email to the actual DB user ID.
    """
    if credentials is None:
        raise HTTPException(status_code=401, detail="Not authenticated")
    
    token = credentials.credentials
    
    # Try Firebase ID token verification first
    firebase_user = verify_firebase_id_token(token)
    if firebase_user is not None:
        # Resolve Firebase email to actual DB user ID
        email = firebase_user.get("email", "").lower()
        if not email:
            raise HTTPException(status_code=401, detail="Firebase token missing email")
        
        # Lazy import to avoid circular dependencies
        from database import get_db
        from models import User
        db = next(get_db())
        try:
            user = db.query(User).filter(User.email == email).first()
            if user is None:
                raise HTTPException(
                    status_code=401,
                    detail="User not found. Please register first.",
                )
            return user.id
        finally:
            db.close()
    
    # Fallback to custom JWT verification
    payload = verify_token(token)
    user_id = payload.get("sub")
    if user_id is None:
        raise HTTPException(status_code=401, detail="Invalid token payload")
    return user_id


# ── Firebase ID Token Verification ──────────────────────────────────────────

_firebase_initialized = False

def _init_firebase():
    """Initialize Firebase Admin SDK (lazy, once)."""
    global _firebase_initialized
    if _firebase_initialized:
        return
    try:
        import firebase_admin
        from firebase_admin import credentials as fb_credentials
        
        # Try to load service account from env var or file
        cred_path = os.getenv("FIREBASE_CREDENTIALS_PATH")
        cred_json = os.getenv("FIREBASE_CREDENTIALS_JSON")
        
        if cred_json:
            import json
            cred_dict = json.loads(cred_json)
            cred = fb_credentials.Certificate(cred_dict)
            firebase_admin.initialize_app(cred)
        elif cred_path and os.path.exists(cred_path):
            cred = fb_credentials.Certificate(cred_path)
            firebase_admin.initialize_app(cred)
        else:
            # Initialize without credentials (uses Application Default Credentials)
            firebase_admin.initialize_app()
        
        _firebase_initialized = True
        logger.info("[Farmaa] Firebase Admin SDK initialized successfully")
    except Exception as e:
        logger.warning(f"[Farmaa] Firebase Admin SDK init failed: {e}")
        _firebase_initialized = False


def verify_firebase_id_token(id_token: str) -> dict:
    """Verify a Firebase ID token and return user info.
    
    Returns dict with: uid, email, name, picture, email_verified
    Returns None if verification fails (allows fallback to custom JWT).
    """
    try:
        _init_firebase()
        if not _firebase_initialized:
            return None
            
        from firebase_admin import auth as firebase_auth
        
        decoded_token = firebase_auth.verify_id_token(id_token)
        
        return {
            "uid": decoded_token.get("uid"),
            "email": decoded_token.get("email"),
            "name": decoded_token.get("name", "User"),
            "picture": decoded_token.get("picture"),
            "email_verified": decoded_token.get("email_verified", False),
        }
    except Exception as e:
        logger.debug(f"[Farmaa] Firebase token verification failed: {e}")
        return None


# ── Google ID Token Verification ─────────────────────────────────────────────

def verify_google_id_token(id_token: str) -> dict:
    """Verify a Google ID token and return the user info.
    
    Returns dict with: sub, email, name, picture, email_verified
    Raises HTTPException if verification fails.
    """
    try:
        from google.oauth2 import id_token as google_id_token
        from google.auth.transport import requests as google_requests

        # Verify the token with Google's servers
        idinfo = google_id_token.verify_oauth2_token(
            id_token,
            google_requests.Request(),
            # Don't specify audience to accept any valid Google token
            # In production, you should set this to your client ID
        )

        # Verify the issuer
        if idinfo.get("iss") not in ["accounts.google.com", "https://accounts.google.com"]:
            raise HTTPException(
                status_code=status.HTTP_401_UNAUTHORIZED,
                detail="Invalid Google token issuer",
            )

        # Check email is verified
        if not idinfo.get("email_verified", False):
            raise HTTPException(
                status_code=status.HTTP_401_UNAUTHORIZED,
                detail="Google email not verified",
            )

        return {
            "sub": idinfo.get("sub"),
            "email": idinfo.get("email"),
            "name": idinfo.get("name", "User"),
            "picture": idinfo.get("picture"),
            "email_verified": idinfo.get("email_verified", False),
        }
    except HTTPException:
        raise
    except Exception as e:
        logger.warning(f"[Farmaa] Google token verification failed: {e}")
        # In development, allow fallback
        if ENVIRONMENT != "production":
            logger.info("[Farmaa] Dev mode: Skipping Google token verification")
            return None
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="Failed to verify Google ID token",
        )
