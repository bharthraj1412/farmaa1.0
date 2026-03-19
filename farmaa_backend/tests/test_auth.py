import pytest
from unittest.mock import patch
from models import User
from auth import create_access_token

# Mock Firebase token verification to return a developer placeholder
@pytest.fixture
def mock_firebase_verify():
    with patch("routers.auth_router.verify_firebase_id_token") as mock_verify:
        yield mock_verify

def test_google_auth_creates_new_user(client, setup_db, mock_firebase_verify):
    db = setup_db
    # Mock the return value of Firebase token verification
    mock_firebase_verify.return_value = {
        "uid": "fb_uid_123",
        "sub": "google_sub_123",
        "email": "test@google.com",
        "name": "Test Google User",
        "picture": "http://photo.url",
        "email_verified": True
    }
    
    response = client.post("/auth/google", json={
        "google_id_token": "fake_token",
        "email": "test@google.com",
        "name": "Test Google User"
    })
    
    assert response.status_code == 200
    data = response.json()
    assert "access_token" in data
    assert data["user"]["email"] == "test@google.com"
    assert data["user"]["name"] == "Test Google User"
    assert data["profile_completed"] is False
    
    # Verify user saved in DB
    user = db.query(User).filter(User.email == "test@google.com").first()
    assert user is not None
    assert user.google_id == "google_sub_123"

def test_google_auth_existing_user(client, setup_db, mock_firebase_verify):
    db = setup_db
    # Seed an existing user
    existing_user = User(
        email="test@google.com",
        name="Test Google User",
        google_id="google_sub_123",
        profile_completed=True
    )
    db.add(existing_user)
    db.commit()

    mock_firebase_verify.return_value = {
        "uid": "fb_uid_123",
        "sub": "google_sub_123",
        "email": "test@google.com",
        "name": "Test Google User",
        "email_verified": True
    }
    
    response = client.post("/auth/google", json={
        "google_id_token": "fake_token",
        "email": "test@google.com",
        "name": "Test Google User"
    })
    
    assert response.status_code == 200
    data = response.json()
    assert data["profile_completed"] is True

def test_google_auth_email_mismatch(client, mock_firebase_verify):
    mock_firebase_verify.return_value = {
        "uid": "fb_uid_123",
        "sub": "google_sub_123",
        "email": "actual@google.com",
    }
    
    response = client.post("/auth/google", json={
        "google_id_token": "fake_token",
        "email": "fake@google.com",
        "name": "Hacker"
    })
    
    assert response.status_code == 400
    assert "Email mismatch" in response.json()["detail"]

def test_complete_profile(client, setup_db):
    db = setup_db
    # Create an incomplete user
    user = User(
        id="u1",
        email="test@google.com",
        name="Test User",
        profile_completed=False
    )
    db.add(user)
    db.commit()

    # Generate token
    token = create_access_token({"sub": "u1", "email": "test@google.com", "role": "buyer"})
    headers = {"Authorization": f"Bearer {token}"}

    response = client.post("/auth/complete-profile", json={
        "name": "Updated Name",
        "mobile_number": "+919876543210",
        "district": "Chennai",
        "postal_code": "600001",
        "address": "123 Main Street"
    }, headers=headers)
    
    assert response.status_code == 200
    data = response.json()
    assert data["name"] == "Updated Name"
    assert data["mobile_number"] == "+919876543210"
    assert data["postal_code"] == "600001"
    assert data["profile_completed"] is True
