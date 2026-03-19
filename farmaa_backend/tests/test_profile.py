"""Tests for profile update / me endpoints."""

import pytest
from models import User
from auth import create_access_token


def _auth_header(user_id: str, email: str = "test@test.com") -> dict:
    token = create_access_token({"sub": user_id, "email": email, "role": "buyer"})
    return {"Authorization": f"Bearer {token}"}


def test_profile_update_persists_all_fields(client, setup_db):
    """Validates that address, district, company, etc. are saved by PATCH /auth/me."""
    db = setup_db
    user = User(
        id="p1", name="Profile User", email="profile@test.com"
    )
    db.add(user)
    db.commit()

    headers = _auth_header("p1", "profile@test.com")
    resp = client.patch("/auth/me", json={
        "name": "Updated Name",
        "mobile_number": "+919999999999",
        "address": "123 Test Address, Village",
        "district": "Madurai",
        "company_name": "Farmer Coop Ltd",
        "postal_code": "625001"
    }, headers=headers)

    assert resp.status_code == 200

    # Read back to confirm persistence
    get_resp = client.get("/auth/me", headers=headers)
    assert get_resp.status_code == 200
    data = get_resp.json()
    assert data["name"] == "Updated Name"
    assert data["mobile_number"] == "+919999999999"
    assert data["address"] == "123 Test Address, Village"
    assert data["postal_code"] == "625001"


def test_profile_update_duplicate_mobile_rejected(client, setup_db):
    db = setup_db
    u1 = User(id="u1", name="User1", email="u1@test.com", mobile_number="+919876543210")
    u2 = User(id="u2", name="User2", email="u2@test.com")
    db.add_all([u1, u2])
    db.commit()

    headers = _auth_header("u2", "u2@test.com")
    response = client.patch("/auth/me", json={"mobile_number": "+919876543210"}, headers=headers)
    assert response.status_code == 400
    assert "already in use" in response.json()["detail"]
