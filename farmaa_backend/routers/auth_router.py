"""Authentication router – Google auth, profile completion, profile management, logout."""

from datetime import datetime, timezone
from fastapi import APIRouter, Depends, HTTPException, Request
from sqlalchemy.orm import Session

from database import get_db
from models import User
from schemas import GoogleAuthRequest, ProfileCompleteRequest, AuthResponse, UserOut, UserUpdate
from auth import (
    create_access_token, create_refresh_token, get_current_user_id,
    verify_token, verify_firebase_id_token,
)
from middleware import sanitize_string
import logging

logger = logging.getLogger(__name__)

router = APIRouter(prefix="/auth", tags=["Authentication"])


# ── Google Auth (sole entry point) ──────────────────────────────────────────

@router.post("/google", response_model=AuthResponse)
def google_auth(body: GoogleAuthRequest, db: Session = Depends(get_db)):
    """Authenticate with Google. Validates Firebase/Google ID token server-side.
    Creates user if not exists. Returns profile_completed flag for routing."""
    if not body.email:
        raise HTTPException(status_code=400, detail="Email is required for Google authentication.")

    # Verify the Firebase/Google ID token server-side
    firebase_user = verify_firebase_id_token(body.google_id_token)
    if firebase_user is None:
        raise HTTPException(
            status_code=401,
            detail="Invalid or expired authentication token",
        )

    # Trust ONLY the verified email from the token
    verified_email = firebase_user.get("email", "").lower()
    if verified_email and verified_email != body.email.lower():
        raise HTTPException(
            status_code=400,
            detail="Email mismatch between token and request"
        )
    email = verified_email or body.email.lower()
    firebase_uid = firebase_user.get("uid")
    google_sub = firebase_user.get("sub")  # Google's unique ID

    # Find or create user (by firebase_uid, google_id, or email)
    user = None
    if firebase_uid:
        user = db.query(User).filter(User.firebase_uid == firebase_uid).first()
    if user is None and google_sub:
        user = db.query(User).filter(User.google_id == google_sub).first()
    if user is None:
        user = db.query(User).filter(User.email == email).first()

    if user is None:
        # New user – create with minimal data
        user = User(
            email=email,
            firebase_uid=firebase_uid,
            google_id=google_sub,
            name=sanitize_string(body.name, max_length=100) or "User",
            role="buyer",
            profile_image=body.profile_image or firebase_user.get("picture"),
            is_verified=firebase_user.get("email_verified", False),
            profile_completed=False,
        )
        db.add(user)
        db.commit()
        db.refresh(user)
        logger.info(f"[Farmaa] New Google user created: {email}")
    else:
        # Existing user – update links and metadata
        if firebase_uid and not user.firebase_uid:
            user.firebase_uid = firebase_uid
        if google_sub and not user.google_id:
            user.google_id = google_sub
        if body.name and body.name != "User" and (not user.name or user.name == "User"):
            user.name = sanitize_string(body.name, max_length=100)
        if body.profile_image and not user.profile_image:
            user.profile_image = body.profile_image
        if not user.is_verified and firebase_user.get("email_verified", False):
            user.is_verified = True
        user.updated_at = datetime.now(timezone.utc)
        db.commit()
        db.refresh(user)

    # Generate backend JWTs
    token_data = {"sub": user.id, "email": user.email, "role": user.role}
    access_token = create_access_token(token_data)
    refresh_token = create_refresh_token(token_data)

    return AuthResponse(
        access_token=access_token,
        refresh_token=refresh_token,
        user=UserOut.model_validate(user),
        profile_completed=user.profile_completed or False,
    )


# ── Profile Completion (mandatory for new users) ────────────────────────────

@router.post("/complete-profile", response_model=UserOut)
def complete_profile(
    body: ProfileCompleteRequest,
    user_id: str = Depends(get_current_user_id),
    db: Session = Depends(get_db),
):
    """Complete user profile after first Google login. Required before accessing dashboard."""
    user = db.query(User).filter(User.id == user_id).first()
    if user is None:
        raise HTTPException(status_code=404, detail="User not found")

    # Check duplicate mobile number
    existing = db.query(User).filter(
        User.mobile_number == body.mobile_number,
        User.id != user_id,
    ).first()
    if existing:
        raise HTTPException(status_code=400, detail="Mobile number already registered to another account")

    # Update profile fields
    user.name = sanitize_string(body.name, max_length=100)
    user.mobile_number = body.mobile_number
    user.district = sanitize_string(body.district, max_length=100)
    user.postal_code = body.postal_code
    user.address = sanitize_string(body.address, max_length=500)
    user.company_name = sanitize_string(body.company_name, max_length=150) if body.company_name else None
    user.profile_completed = True
    user.updated_at = datetime.now(timezone.utc)

    db.commit()
    db.refresh(user)
    logger.info(f"[Farmaa] Profile completed for user: {user.email}")

    return UserOut.model_validate(user)


# ── Token Refresh ───────────────────────────────────────────────────────────

@router.post("/refresh")
def refresh_access_token(refresh_token: str):
    """Exchange a refresh token for a new access token."""
    payload = verify_token(refresh_token, expected_type="refresh")
    user_id = payload.get("sub")
    if not user_id:
        raise HTTPException(status_code=401, detail="Invalid refresh token")

    new_access = create_access_token({"sub": user_id})
    return {"access_token": new_access, "token_type": "bearer"}


# ── Profile ─────────────────────────────────────────────────────────────────

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
    if body.mobile_number is not None:
        if body.mobile_number != user.mobile_number:
            existing = db.query(User).filter(
                User.mobile_number == body.mobile_number,
                User.id != user_id,
            ).first()
            if existing:
                raise HTTPException(status_code=400, detail="Mobile number already in use")
            user.mobile_number = body.mobile_number
    if body.district is not None:
        user.district = sanitize_string(body.district, max_length=100) if body.district else None
    if body.postal_code is not None:
        user.postal_code = body.postal_code if body.postal_code else None
    if body.address is not None:
        user.address = sanitize_string(body.address, max_length=500) if body.address else None
    if body.company_name is not None:
        user.company_name = sanitize_string(body.company_name, max_length=150) if body.company_name else None

    user.updated_at = datetime.now(timezone.utc)
    db.commit()
    db.refresh(user)
    return UserOut.model_validate(user)


# ── Logout ──────────────────────────────────────────────────────────────────

@router.post("/logout")
def logout():
    return {"message": "Logged out successfully"}
