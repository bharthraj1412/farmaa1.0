from fastapi import APIRouter
from pydantic import BaseModel
import sys

from auth import get_current_user_id
from database import get_db, SessionLocal
from models import User, Crop, Order
from schemas import OrderCreate
from routers.orders_router import create_order

def run_test():
    db = SessionLocal()
    try:
        buyer = db.query(User).filter(User.role == 'buyer').first()
        farmer = db.query(User).filter(User.role == 'farmer').first()
        if not buyer or not farmer:
            print("No users found")
            return
        
        crop = db.query(Crop).filter(Crop.farmer_id == farmer.id).first()
        if not crop:
            print("No crop found")
            return

        print(f"Buyer: {buyer.id}, Farmer: {farmer.id}, Crop: {crop.id}")
        
        # Test creating order explicitly with all fields
        body = OrderCreate(
            crop_id=crop.id,
            quantity_kg=1.0,
            delivery_address="Test Address",
            payment_id="pay_123",
            razorpay_order_id="order_123",
            razorpay_signature="sig_123"
        )
        
        print("Calling create_order...")
        order_out = create_order(body=body, user_id=buyer.id, db=db)
        print("Success! Order ID:", order_out.id)
        
    except Exception as e:
        import traceback
        traceback.print_exc()
        # write to file so we can read it easily
        with open('trace.txt', 'w') as f:
            f.write(traceback.format_exc())
    finally:
        db.close()

if __name__ == '__main__':
    run_test()
