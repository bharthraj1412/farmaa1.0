from sqlalchemy import create_engine
from sqlalchemy.orm import sessionmaker
import os
from database import Base, engine, SessionLocal
from models import Crop

db = SessionLocal()
try:
    crop = db.query(Crop).with_for_update(of=Crop).first()
    print("Success with of=Crop!", crop.id)
except Exception as e:
    print("FAILED with of=Crop:", e)
finally:
    db.close()
