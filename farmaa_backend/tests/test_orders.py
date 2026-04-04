"""Tests for order flow with race conditions and profile checks."""

import pytest
from models import User, Crop, Order
from auth import create_access_token


def _auth_header(user_id: str, email: str = "test@test.com", role: str = "buyer") -> dict:
    token = create_access_token({"sub": user_id, "email": email, "role": role})
    return {"Authorization": f"Bearer {token}"}


def _make_farmer(db, id="f1", email="f@test.com"):
    u = User(
        id=id, name="Farmer", email=email, role="farmer",
        mobile_number=f"+9190000{id[-1:]}0001",
        district="Salem", profile_completed=True,
    )
    db.add(u)
    return u


def _make_buyer(db, id="b1", email="b@test.com"):
    u = User(
        id=id, name="Buyer", email=email, role="buyer",
        mobile_number=f"+9199999{id[-1:]}0001",
        district="Chennai", profile_completed=True,
    )
    db.add(u)
    return u


def _make_crop(db, id="c1", farmer_id="f1", stock_kg=100, min_order_kg=1):
    c = Crop(
        id=id, farmer_id=farmer_id, name="Wheat", category="Wheat",
        price_per_kg=25.0, stock_kg=stock_kg, min_order_kg=min_order_kg,
        is_available=True, is_active=True, status="approved",
    )
    db.add(c)
    return c


# ── Marketplace Visibility ────────────────────────────────────────────────────

def test_marketplace_shows_all_farmers_crops(client, setup_db):
    db = setup_db
    f1 = _make_farmer(db, "f1", "fa@test.com")
    f2 = _make_farmer(db, "f2", "fb@test.com")
    db.commit()

    c1 = Crop(id="c1", farmer_id="f1", name="Wheat", category="Wheat",
              price_per_kg=25.0, stock_kg=500, is_available=True, status="approved")
    c2 = Crop(id="c2", farmer_id="f2", name="Rice", category="Rice",
              price_per_kg=40.0, stock_kg=300, is_available=True, status="approved")
    c3 = Crop(id="c3", farmer_id="f1", name="Stale Millet", category="Millet",
              price_per_kg=30.0, stock_kg=0, is_available=False, status="sold_out")
    db.add_all([c1, c2, c3])
    db.commit()

    response = client.get("/crops")
    assert response.status_code == 200
    data = response.json()
    assert data["total"] == 2
    names = [c["name"] for c in data["items"]]
    assert "Wheat" in names
    assert "Rice" in names
    assert "Stale Millet" not in names


def test_profile_update_persists_village_district_org(client, setup_db):
    """Profile update via PATCH /auth/me persists address fields."""
    db = setup_db
    user = User(id="p1", name="Test Farmer", email="pf@test.com",
                mobile_number="+919123456789", district="Salem", profile_completed=True)
    db.add(user)
    db.commit()

    headers = _auth_header("p1", "pf@test.com")
    resp = client.patch("/auth/me", json={
        "name":         "Updated Farmer",
        "address":      "123 Main Street, Salem",
        "district":     "Salem",
        "company_name": "Coop Ltd",
        "postal_code":  "636001",
    }, headers=headers)
    assert resp.status_code == 200
    data = resp.json()
    assert data["address"] == "123 Main Street, Salem"
    assert data["company_name"] == "Coop Ltd"


def test_profile_update_duplicate_phone_rejected(client, setup_db):
    db = setup_db
    u1 = User(id="u1", name="User1", email="u1@test.com",
              mobile_number="+919876543210", profile_completed=True)
    u2 = User(id="u2", name="User2", email="u2@test.com", profile_completed=True)
    db.add_all([u1, u2])
    db.commit()

    headers = _auth_header("u2", "u2@test.com")
    resp = client.patch("/auth/me", json={"mobile_number": "+919876543210"}, headers=headers)
    assert resp.status_code == 400
    assert "already in use" in resp.json()["detail"]


# ── Order Creation ────────────────────────────────────────────────────────────

def test_create_order_decrements_stock(client, setup_db):
    db = setup_db
    _make_farmer(db)
    _make_buyer(db)
    db.commit()
    _make_crop(db, stock_kg=100, min_order_kg=1)
    db.commit()

    headers = _auth_header("b1", "b@test.com", "buyer")
    response = client.post("/orders/", json={"crop_id": "c1", "quantity_kg": 30}, headers=headers)

    assert response.status_code == 201
    order = response.json()
    assert order["quantity_kg"] == 30
    assert order["total_amount"] == 750.0   # 30 × 25

    db.expire_all()
    updated_crop = db.query(Crop).filter(Crop.id == "c1").first()
    assert updated_crop.stock_kg == 70


def test_create_order_insufficient_stock_rejected(client, setup_db):
    db = setup_db
    _make_farmer(db)
    _make_buyer(db)
    db.commit()
    _make_crop(db, stock_kg=20, min_order_kg=1)
    db.commit()

    headers = _auth_header("b1", "b@test.com", "buyer")
    response = client.post("/orders/", json={"crop_id": "c1", "quantity_kg": 50}, headers=headers)

    assert response.status_code == 400
    assert "Insufficient stock" in response.json()["detail"]


def test_self_purchase_prevented(client, setup_db):
    db = setup_db
    _make_farmer(db)
    db.commit()
    _make_crop(db, min_order_kg=1)
    db.commit()

    headers = _auth_header("f1", "f@test.com", "farmer")
    response = client.post("/orders/", json={"crop_id": "c1", "quantity_kg": 10}, headers=headers)

    assert response.status_code == 400
    assert "cannot order your own" in response.json()["detail"]


def test_profile_incomplete_order_rejected(client, setup_db):
    """Buyer without profile_completed should not be able to place orders."""
    db = setup_db
    _make_farmer(db)
    # Buyer without profile_completed
    buyer = User(id="b1", name="Buyer", email="b@test.com", role="buyer",
                 profile_completed=False)
    db.add(buyer)
    db.commit()
    _make_crop(db, min_order_kg=1)
    db.commit()

    headers = _auth_header("b1", "b@test.com", "buyer")
    response = client.post("/orders/", json={"crop_id": "c1", "quantity_kg": 10}, headers=headers)

    assert response.status_code == 400
    assert "profile" in response.json()["detail"].lower()


def test_order_status_transitions(client, setup_db):
    db = setup_db
    _make_farmer(db)
    _make_buyer(db)
    db.commit()
    _make_crop(db, stock_kg=100, min_order_kg=1)
    db.commit()

    # Create order
    buyer_headers  = _auth_header("b1", "b@test.com", "buyer")
    farmer_headers = _auth_header("f1", "f@test.com", "farmer")

    resp = client.post("/orders/", json={"crop_id": "c1", "quantity_kg": 10}, headers=buyer_headers)
    assert resp.status_code == 201
    order_id = resp.json()["id"]

    # Farmer confirms
    resp = client.patch(f"/orders/{order_id}/status", json={"status": "confirmed"}, headers=farmer_headers)
    assert resp.status_code == 200
    assert resp.json()["status"] == "confirmed"

    # Buyer cannot ship (only farmer can)
    resp = client.patch(f"/orders/{order_id}/status", json={"status": "processing"}, headers=buyer_headers)
    assert resp.status_code == 403
