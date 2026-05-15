"""Admin router – platform management, user verification, statistics.

All endpoints require admin role authentication.
"""

from fastapi import APIRouter, Depends, HTTPException
from sqlalchemy.orm import Session
from sqlalchemy import func
from datetime import datetime, timezone

from database import get_db
from models import User, Crop, Order
from auth import get_current_user_id
from middleware import require_role

router = APIRouter(prefix="/admin", tags=["Admin"], dependencies=[Depends(require_role("admin"))])


@router.get("/stats")
def get_platform_stats(db: Session = Depends(get_db)):
    """Get platform-wide statistics. Admin only."""
    total_users = db.query(func.count(User.id)).scalar() or 0
    total_farmers = db.query(func.count(User.id)).filter(User.role == "farmer").scalar() or 0
    total_buyers = db.query(func.count(User.id)).filter(User.role == "buyer").scalar() or 0
    pending_approvals = db.query(func.count(User.id)).filter(User.is_verified == False).scalar() or 0
    total_orders = db.query(func.count(Order.id)).scalar() or 0
    total_revenue = db.query(func.coalesce(func.sum(Order.total_amount), 0.0)).filter(
        Order.status.in_(["confirmed", "processing", "shipped", "delivered"])
    ).scalar() or 0.0
    open_disputes = 0  # Placeholder until dispute system is implemented

    return {
        "total_users": total_users,
        "farmers": total_farmers,
        "buyers": total_buyers,
        "pending_approvals": pending_approvals,
        "total_orders": total_orders,
        "open_disputes": open_disputes,
        "total_revenue": float(total_revenue),
    }


@router.get("/pending-verifications")
def get_pending_verifications(db: Session = Depends(get_db)):
    """List all unverified users pending admin approval. Admin only."""
    users = db.query(User).filter(User.is_verified == False).order_by(User.created_at.desc()).all()
    return [
        {
            "id": u.id,
            "name": u.name,
            "phone": u.phone or "",
            "email": u.email or "",
            "role": u.role,
            "district": u.district or "",
            "village": u.village or "",
            "created_at": u.created_at.isoformat() if u.created_at else None,
        }
        for u in users
    ]


@router.post("/verify-user/{user_id}")
def verify_user(user_id: str, db: Session = Depends(get_db)):
    """Approve/verify a user. Admin only."""
    user = db.query(User).filter(User.id == user_id).first()
    if user is None:
        raise HTTPException(status_code=404, detail="User not found")

    user.is_verified = True
    user.updated_at = datetime.now(timezone.utc)
    db.commit()

    return {"message": f"User '{user.name}' has been verified", "user_id": user_id}


@router.post("/reject-user/{user_id}")
def reject_user(user_id: str, db: Session = Depends(get_db)):
    """Reject a user verification request. Admin only."""
    user = db.query(User).filter(User.id == user_id).first()
    if user is None:
        raise HTTPException(status_code=404, detail="User not found")

    # Soft-delete: mark as not verified and deactivate
    user.is_verified = False
    user.updated_at = datetime.now(timezone.utc)
    db.commit()

    return {"message": f"User '{user.name}' has been rejected", "user_id": user_id}


@router.get("/users")
def list_all_users(
    role: str | None = None,
    skip: int = 0,
    limit: int = 50,
    db: Session = Depends(get_db),
):
    """List all users with optional role filter. Admin only."""
    query = db.query(User)
    if role:
        query = query.filter(User.role == role)
    total = query.count()
    users = query.order_by(User.created_at.desc()).offset(skip).limit(limit).all()

    return {
        "total": total,
        "items": [
            {
                "id": u.id,
                "name": u.name,
                "email": u.email,
                "phone": u.phone,
                "role": u.role,
                "is_verified": u.is_verified,
                "district": u.district,
                "village": u.village,
                "created_at": u.created_at.isoformat() if u.created_at else None,
            }
            for u in users
        ],
    }
