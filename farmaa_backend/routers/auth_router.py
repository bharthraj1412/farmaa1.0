"""Authentication router – register, login, Google auth, profile, logout."""

from datetime import datetime, timezone
from fastapi import APIRouter, Depends, HTTPException, Request
from sqlalchemy.orm import Session
from sqlalchemy import or_

from database import get_db
from models import User
from schemas import GoogleAuthRequest, FirebaseAuthRequest, AuthResponse, UserOut, UserUpdate, RegisterRequest, LoginRequest
from auth import (
    create_access_token, create_refresh_token, get_current_user_id,
    verify_token, verify_google_id_token, verify_firebase_id_token,
)
from middleware import sanitize_string, validate_phone_number
import logging

import bcrypt

logger = logging.getLogger(__name__)

router = APIRouter(prefix="/auth", tags=["Authentication"])

def verify_password(plain_password: str, hashed_password: str) -> bool:
    try:
        return bcrypt.checkpw(plain_password.encode('utf-8'), hashed_password.encode('utf-8'))
    except Exception:
        return False

def get_password_hash(password: str) -> str:
    # Hash password with bcrypt
    salt = bcrypt.gensalt()
    hashed = bcrypt.hashpw(password.encode('utf-8'), salt)
    return hashed.decode('utf-8')


@router.post("/register", response_model=AuthResponse)
def register(body: RegisterRequest, db: Session = Depends(get_db)):
    """Register a new user with email/phone and password."""
    
    # Check if user already exists
    query = db.query(User)
    if body.email:
        user_by_email = query.filter(User.email == body.email.lower()).first()
        if user_by_email:
            raise HTTPException(status_code=400, detail="Email already registered")
            
    if body.phone:
        user_by_phone = query.filter(User.phone == body.phone).first()
        if user_by_phone:
            raise HTTPException(status_code=400, detail="Phone number already registered")

    # Sanitize inputs
    name = sanitize_string(body.name, max_length=100)
    
    # Create new user
    user = User(
        name=name if name and name != "User" else "User",
        email=body.email.lower() if body.email else None,
        phone=body.phone if body.phone else None,
        password_hash=get_password_hash(body.password),
        role="buyer", # Default role
        is_verified=True,
    )
    db.add(user)
    db.commit()
    db.refresh(user)

    # Generate tokens
    token_data = {"sub": user.id, "email": user.email, "phone": user.phone, "role": user.role}
    access_token = create_access_token(token_data)
    refresh_token = create_refresh_token(token_data)

    return AuthResponse(
        access_token=access_token,
        refresh_token=refresh_token,
        user=UserOut.model_validate(user),
    )


@router.post("/login", response_model=AuthResponse)
def login(body: LoginRequest, db: Session = Depends(get_db)):
    """Authenticate user with email or phone and password."""
    
    # Find user by email or phone
    identifier = body.email_or_phone.strip().lower()
    user = db.query(User).filter(
        or_(
            User.email == identifier,
            User.phone == identifier,
            User.phone == f"+91{identifier}" if not identifier.startswith("+") else False
        )
    ).first()

    if not user:
        raise HTTPException(status_code=401, detail="Invalid credentials")
        
    if not user.password_hash:
        raise HTTPException(
            status_code=401, 
            detail="Account created via Google. Please login with Google."
        )

    # Verify password
    if not verify_password(body.password, user.password_hash):
        raise HTTPException(status_code=401, detail="Invalid credentials")

    # Generate tokens
    token_data = {"sub": user.id, "email": user.email, "phone": user.phone, "role": user.role}
    access_token = create_access_token(token_data)
    refresh_token = create_refresh_token(token_data)

    return AuthResponse(
        access_token=access_token,
        refresh_token=refresh_token,
        user=UserOut.model_validate(user),
    )


@router.post("/firebase", response_model=AuthResponse)
def firebase_auth(body: FirebaseAuthRequest, db: Session = Depends(get_db)):
    """Authenticate via Firebase ID token. Creates user if not exists, returns JWT."""
    # 1. Verify the Firebase ID token server-side
    firebase_user = verify_firebase_id_token(body.firebase_id_token)
    if firebase_user is None:
        raise HTTPException(
            status_code=401,
            detail="Invalid or expired Firebase token",
        )

    # 2. Validate email matches
    verified_email = firebase_user.get("email", "").lower()
    if verified_email and verified_email != body.email.lower():
        raise HTTPException(
            status_code=400,
            detail="Email mismatch between Firebase token and request",
        )
    email = verified_email or body.email.lower()

    # 3. Find or create user (try by firebase_uid first, then email)
    firebase_uid = firebase_user.get("uid")
    user = None
    if firebase_uid:
        user = db.query(User).filter(User.firebase_uid == firebase_uid).first()
    if user is None:
        user = db.query(User).filter(User.email == email).first()

    if user is None:
        user = User(
            email=email,
            firebase_uid=firebase_uid,
            name=sanitize_string(body.name, max_length=100) or "User",
            role="buyer",
            profile_image=body.profile_image or firebase_user.get("picture"),
            is_verified=firebase_user.get("email_verified", False),
        )
        db.add(user)
        db.commit()
        db.refresh(user)
        logger.info(f"[Farmaa] New Firebase user created: {email}")
    else:
        # Link firebase_uid if not already set
        if firebase_uid and not user.firebase_uid:
            user.firebase_uid = firebase_uid
        # Update profile image and name if provided
        if body.name and body.name != "User" and not user.name:
            user.name = sanitize_string(body.name, max_length=100)
        if body.profile_image and not user.profile_image:
            user.profile_image = body.profile_image
        if not user.is_verified and firebase_user.get("email_verified", False):
            user.is_verified = True
        user.updated_at = datetime.now(timezone.utc)
        db.commit()
        db.refresh(user)

    # 4. Generate backend JWTs (used for /auth/me etc.)
    token_data = {"sub": user.id, "email": user.email, "role": user.role}
    access_token = create_access_token(token_data)
    refresh_token = create_refresh_token(token_data)

    return AuthResponse(
        access_token=access_token,
        refresh_token=refresh_token,
        user=UserOut.model_validate(user),
    )


@router.post("/refresh")
def refresh_access_token(refresh_token: str):
    """Exchange a refresh token for a new access token."""
    payload = verify_token(refresh_token, expected_type="refresh")
    user_id = payload.get("sub")
    if not user_id:
        raise HTTPException(status_code=401, detail="Invalid refresh token")

    new_access = create_access_token({"sub": user_id})
    return {"access_token": new_access, "token_type": "bearer"}


@router.get("/me", response_model=UserOut)
def get_profile(user_id: str = Depends(get_current_user_id), db: Session = Depends(get_db)):
    user = db.query(User).filter(User.id == user_id).first()
    if user is None:
        raise HTTPException(status_code=404, detail="User not found")
    return UserOut.model_validate(user)


@router.patch("/me", response_model=UserOut)
def update_profile(body: UserUpdate, user_id: str = Depends(get_current_user_id), db: Session = Depends(get_db)):
    user = db.query(User).filter(User.id == user_id).first()
    if user is None:
        raise HTTPException(status_code=404, detail="User not found")

    if body.name is not None:
        user.name = sanitize_string(body.name, max_length=100)
    if body.phone is not None:
        new_phone = body.phone.strip()
        if new_phone and not validate_phone_number(new_phone):
            raise HTTPException(status_code=400, detail="Invalid phone number format")
        if new_phone != user.phone:
            # Check for duplicate phone
            existing = db.query(User).filter(User.phone == new_phone, User.id != user_id).first()
            if existing:
                raise HTTPException(status_code=400, detail="Phone number already in use")
            user.phone = new_phone
    if body.email is not None:
        new_email = body.email.strip().lower()
        if new_email != user.email:
            # Check for duplicate email
            existing = db.query(User).filter(User.email == new_email, User.id != user_id).first()
            if existing:
                raise HTTPException(status_code=400, detail="Email already in use")
            user.email = new_email
    user.updated_at = datetime.now(timezone.utc)

    db.commit()
    db.refresh(user)
    return UserOut.model_validate(user)


@router.post("/logout")
def logout():
    return {"message": "Logged out successfully"}


@router.post("/google", response_model=AuthResponse)
def google_auth(body: GoogleAuthRequest, db: Session = Depends(get_db)):
    """Authenticate with Google. Validates ID token server-side. Creates user if not exists."""
    if not body.email:
        raise HTTPException(status_code=400, detail="Email is required for Google authentication.")

    # Verify Google ID token server-side
    google_info = verify_google_id_token(body.google_id_token)

    # If verification returned data, validate email matches
    if google_info is not None:
        if google_info["email"].lower() != body.email.lower():
            raise HTTPException(
                status_code=400,
                detail="Email mismatch between token and request"
            )
        # Use verified data from Google
        verified_name = google_info.get("name", body.name)
        verified_email = google_info["email"]
        profile_image = google_info.get("picture", body.profile_image)
    else:
        # Dev mode fallback – trust the client data
        verified_name = body.name
        verified_email = body.email
        profile_image = body.profile_image

    # Validate role
    role = body.role.lower().strip()
    if role not in ("farmer", "buyer"):
        raise HTTPException(status_code=400, detail="Role must be 'farmer' or 'buyer'")

    # Find or create user by email
    user = db.query(User).filter(User.email == verified_email).first()

    if user is None:
        # Create new user
        user = User(
            email=verified_email,
            phone=None,
            name=sanitize_string(verified_name, max_length=100),
            role=role,
            village=sanitize_string(body.village) if body.village else None,
            district=sanitize_string(body.district) if body.district else None,
            organization=sanitize_string(body.org) if body.org else None,
            profile_image=profile_image,
            is_verified=True,
        )
        db.add(user)
        db.commit()
        db.refresh(user)
    else:
        # Update profile image and name if changed
        if verified_name and verified_name != "User":
            user.name = verified_name
        if profile_image:
            user.profile_image = profile_image
        if role:
            user.role = role
        user.updated_at = datetime.now(timezone.utc)
        db.commit()
        db.refresh(user)

    # Generate tokens
    token_data = {"sub": user.id, "email": user.email, "role": user.role}
    access_token = create_access_token(token_data)
    refresh_token = create_refresh_token(token_data)

    return AuthResponse(
        access_token=access_token,
        refresh_token=refresh_token,
        user=UserOut.model_validate(user),
    )
