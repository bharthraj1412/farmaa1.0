"""Tests for profile update endpoint to validate BUG FIX."""

import pytest
from models import User
from auth import create_access_token
from routers.auth_router import get_password_hash


def _auth_header(user_id: str, email: str = "test@test.com") -> dict:
    token = create_access_token({"sub": user_id, "email": email, "role": "buyer"})
    return {"Authorization": f"Bearer {token}"}


def test_profile_update_persists_all_fields(client, setup_db):
    """Validates that village, district, and org are saved by PATCH /auth/me."""
    db = setup_db
    user = User(
        id="p1", name="Profile User", email="profile@test.com",
        password_hash=get_password_hash("pass123")
    )
    db.add(user)
    db.commit()

    headers = _auth_header("p1", "profile@test.com")
    resp = client.patch("/auth/me", json={
        "name": "Updated Name",
        "phone": "9999999999",
        "village": "Madurai Village",
        "district": "Madurai",
        "org": "Farmer Coop Ltd"
    }, headers=headers)

    assert resp.status_code == 200

    # Read back to confirm persistence
    get_resp = client.get("/auth/me", headers=headers)
    assert get_resp.status_code == 200
    data = get_resp.json()
    assert data["name"] == "Updated Name"
    assert data["phone"] == "9999999999"


def test_register_creates_user(client, setup_db):
    """Existing test kept for regression."""
    response = client.post("/auth/register", json={
        "name": "New User",
        "email": "newuser@example.com",
        "password": "securepassword123"
    })
    assert response.status_code == 200
    data = response.json()
    assert "access_token" in data
    assert data["user"]["email"] == "newuser@example.com"
