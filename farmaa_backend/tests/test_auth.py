import pytest
from models import User
from routers.auth_router import get_password_hash

def test_register_creates_user_and_returns_token(client, setup_db):
    db = setup_db
    response = client.post("/auth/register", json={
        "name": "Test User",
        "phone": "9876543210",
        "email": "test@example.com",
        "password": "securepassword123"
    })
    
    assert response.status_code == 200
    data = response.json()
    assert "access_token" in data
    assert data["user"]["name"] == "Test User"
    assert data["user"]["phone"] == "9876543210"
    assert data["user"]["email"] == "test@example.com"
    
    # Verify user saved in DB
    user = db.query(User).filter(User.phone == "9876543210").first()
    assert user is not None
    assert user.password_hash is not None

def test_register_duplicate_email(client, setup_db):
    client.post("/auth/register", json={
        "name": "User 1",
        "email": "duplicate@example.com",
        "password": "password123"
    })
    
    response = client.post("/auth/register", json={
        "name": "User 2",
        "email": "duplicate@example.com",
        "password": "password456"
    })
    
    assert response.status_code == 400
    assert "Email already registered" in response.json()["detail"]

def test_login_success(client, setup_db):
    db = setup_db
    # Seed a user
    user = User(
        name="Login User",
        email="loginuser@example.com",
        password_hash=get_password_hash("mypassword")
    )
    db.add(user)
    db.commit()
    
    response = client.post("/auth/login", json={
        "email_or_phone": "loginuser@example.com",
        "password": "mypassword"
    })
    
    assert response.status_code == 200
    data = response.json()
    assert "access_token" in data
    assert data["user"]["email"] == "loginuser@example.com"

def test_login_invalid_password(client, setup_db):
    db = setup_db
    user = User(
        name="Login User",
        email="loginuser@example.com",
        password_hash=get_password_hash("mypassword")
    )
    db.add(user)
    db.commit()
    
    response = client.post("/auth/login", json={
        "email_or_phone": "loginuser@example.com",
        "password": "wrongpassword"
    })
    
    assert response.status_code == 401
    assert "Invalid credentials" in response.json()["detail"]
