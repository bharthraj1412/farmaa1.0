"""Tests for order flow with race conditions."""

import pytest
from models import User, Crop, Order
from auth import create_access_token


def _auth_header(user_id: str, email: str = "test@test.com", role: str = "buyer") -> dict:
    """Create Authorization header with a backend JWT for test user."""
    token = create_access_token({"sub": user_id, "email": email, "role": role})
    return {"Authorization": f"Bearer {token}"}


# ── Marketplace Visibility Tests ──────────────────────────────


def test_marketplace_shows_all_farmers_crops(client, setup_db):
    """Crops from different farmers must be visible to any buyer."""
    db = setup_db
    f1 = User(id="f1", name="Farmer A", email="fa@test.com", role="farmer")
    f2 = User(id="f2", name="Farmer B", email="fb@test.com", role="farmer")
    db.add_all([f1, f2])
    db.commit()

    c1 = Crop(id="c1", farmer_id="f1", name="Wheat", category="Wheat",
              price_per_kg=25.0, stock_kg=500, is_available=True, status="approved")
    c2 = Crop(id="c2", farmer_id="f2", name="Rice", category="Rice",
              price_per_kg=40.0, stock_kg=300, is_available=True, status="approved")
    c3 = Crop(id="c3", farmer_id="f1", name="Stale Millet", category="Millet",
              price_per_kg=30.0, stock_kg=0, is_available=False, status="sold_out")
    db.add_all([c1, c2, c3])
    db.commit()
    db.close()

    # No auth required for public marketplace listing
    response = client.get("/crops")
    assert response.status_code == 200
    data = response.json()
    assert data["total"] == 2  # Only available crops
    names = [c["name"] for c in data["items"]]
    assert "Wheat" in names
    assert "Rice" in names
    assert "Stale Millet" not in names  # Unavailable crop hidden


# ── Order Creation Tests ──────────────────────────────────────


def test_create_order_decrements_stock(client, setup_db):
    db = setup_db
    farmer = User(id="f1", name="Farmer", email="f@test.com", role="farmer")
    buyer = User(id="b1", name="Buyer", email="b@test.com", role="buyer")
    db.add_all([farmer, buyer])
    db.commit()

    crop = Crop(id="c1", farmer_id="f1", name="Wheat", category="Wheat",
                price_per_kg=25.0, stock_kg=100, min_order_kg=1,
                is_available=True, status="approved")
    db.add(crop)
    db.commit()

    headers = _auth_header("b1", "b@test.com", "buyer")
    response = client.post("/orders/", json={
        "crop_id": "c1",
        "quantity_kg": 30,
    }, headers=headers)

    assert response.status_code == 201
    order = response.json()
    assert order["quantity_kg"] == 30
    assert order["total_amount"] == 750.0  # 30 * 25

    # Verify stock decremented
    db.expire_all()
    updated_crop = db.query(Crop).filter(Crop.id == "c1").first()
    assert updated_crop.stock_kg == 70


def test_create_order_insufficient_stock_rejected(client, setup_db):
    db = setup_db
    farmer = User(id="f1", name="Farmer", email="f@test.com", role="farmer")
    buyer = User(id="b1", name="Buyer", email="b@test.com", role="buyer")
    db.add_all([farmer, buyer])
    db.commit()

    crop = Crop(id="c1", farmer_id="f1", name="Wheat", category="Wheat",
                price_per_kg=25.0, stock_kg=20, min_order_kg=1,
                is_available=True, status="approved")
    db.add(crop)
    db.commit()

    headers = _auth_header("b1", "b@test.com", "buyer")
    response = client.post("/orders/", json={
        "crop_id": "c1",
        "quantity_kg": 50,  # More than available 20
    }, headers=headers)

    assert response.status_code == 400
    assert "Insufficient stock" in response.json()["detail"]


def test_self_purchase_prevented(client, setup_db):
    db = setup_db
    farmer = User(id="f1", name="Farmer", email="f@test.com", role="farmer")
    db.add(farmer)
    db.commit()

    crop = Crop(id="c1", farmer_id="f1", name="Wheat", category="Wheat",
                price_per_kg=25.0, stock_kg=100, min_order_kg=1,
                is_available=True, status="approved")
    db.add(crop)
    db.commit()

    headers = _auth_header("f1", "f@test.com", "farmer")
    response = client.post("/orders/", json={
        "crop_id": "c1",
        "quantity_kg": 10,
    }, headers=headers)

    assert response.status_code == 400
    assert "cannot order your own" in response.json()["detail"]


def test_order_status_transitions(client, setup_db):
    db = setup_db
    farmer = User(id="f1", name="Farmer", email="f@test.com", role="farmer")
    buyer = User(id="b1", name="Buyer", email="b@test.com", role="buyer")
    db.add_all([farmer, buyer])
    db.commit()

    crop = Crop(id="c1", farmer_id="f1", name="Wheat", category="Wheat",
                price_per_kg=25.0, stock_kg=100, min_order_kg=1,
                is_available=True, status="approved")
    db.add(crop)
    db.commit()

    # Create order
    buyer_headers = _auth_header("b1", "b@test.com", "buyer")
    resp = client.post("/orders/", json={"crop_id": "c1", "quantity_kg": 10}, headers=buyer_headers)
    assert resp.status_code == 201
    order_id = resp.json()["id"]

    # Farmer confirms
    farmer_headers = _auth_header("f1", "f@test.com", "farmer")
    resp = client.patch(f"/orders/{order_id}/status", json={"status": "confirmed"}, headers=farmer_headers)
    assert resp.status_code == 200
    assert resp.json()["status"] == "confirmed"

    # Buyer cannot ship (only farmer can)
    resp = client.patch(f"/orders/{order_id}/status", json={"status": "processing"}, headers=buyer_headers)
    assert resp.status_code == 403
