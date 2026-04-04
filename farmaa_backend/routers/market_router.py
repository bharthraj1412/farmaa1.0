"""Market Prices router – Browse current market rates + WebSocket live updates."""

from fastapi import APIRouter, Depends, Query, WebSocket, WebSocketDisconnect
from sqlalchemy.orm import Session
from typing import List, Optional
from datetime import datetime, timedelta, timezone
import random
import uuid
import asyncio
import json
import logging

from database import get_db
from models import MarketPrice
from schemas import MarketPriceOut
from middleware import sanitize_search_query
from auth import get_current_user_id

logger = logging.getLogger(__name__)

router = APIRouter(prefix="/market", tags=["Market Prices"])


# ── WebSocket connection manager ─────────────────────────────────────────────

class PriceConnectionManager:
    """Manages active WebSocket connections for live price broadcasts."""

    def __init__(self):
        self.active: list[WebSocket] = []

    async def connect(self, ws: WebSocket):
        await ws.accept()
        self.active.append(ws)
        logger.info(f"[WS] Client connected. Total: {len(self.active)}")

    def disconnect(self, ws: WebSocket):
        if ws in self.active:
            self.active.remove(ws)
        logger.info(f"[WS] Client disconnected. Total: {len(self.active)}")

    async def broadcast(self, data: dict):
        """Broadcast a price update to all connected clients."""
        message = json.dumps(data)
        dead = []
        for ws in self.active:
            try:
                await ws.send_text(message)
            except Exception:
                dead.append(ws)
        for ws in dead:
            self.disconnect(ws)


price_manager = PriceConnectionManager()


# ── Demo market price data ───────────────────────────────────────────────────

DEMO_PRICES = [
    {"crop_name": "Rice (Sona Masoori)",     "category": "Rice",    "market_name": "Koyambedu, Chennai",   "base_price": 35.0},
    {"crop_name": "Rice (Ponni)",            "category": "Rice",    "market_name": "Thanjavur Mandi",      "base_price": 32.0},
    {"crop_name": "Rice (Basmati)",          "category": "Rice",    "market_name": "Delhi Wholesale",      "base_price": 55.0},
    {"crop_name": "Wheat (HD-2967)",         "category": "Wheat",   "market_name": "Indore Mandi",         "base_price": 26.0},
    {"crop_name": "Wheat (Lokwan)",          "category": "Wheat",   "market_name": "Pune APMC",            "base_price": 28.0},
    {"crop_name": "Ragi (Finger Millet)",    "category": "Millet",  "market_name": "Mysuru Market",        "base_price": 32.0},
    {"crop_name": "Bajra (Pearl Millet)",    "category": "Millet",  "market_name": "Jodhpur Mandi",        "base_price": 24.0},
    {"crop_name": "Foxtail Millet (Thinai)","category": "Millet",  "market_name": "Salem Market",         "base_price": 45.0},
    {"crop_name": "Little Millet (Samai)",   "category": "Millet",  "market_name": "Erode Market",         "base_price": 48.0},
    {"crop_name": "Jowar (Sorghum)",         "category": "Sorghum", "market_name": "Solapur APMC",         "base_price": 28.0},
    {"crop_name": "Maize (Yellow)",          "category": "Maize",   "market_name": "Davangere Market",     "base_price": 20.0},
    {"crop_name": "Maize (White)",           "category": "Maize",   "market_name": "Karnataka Mandi",      "base_price": 18.0},
    {"crop_name": "Toor Dal",                "category": "Pulses",  "market_name": "Latur APMC",           "base_price": 85.0},
    {"crop_name": "Chana Dal",               "category": "Pulses",  "market_name": "Rajkot Mandi",         "base_price": 62.0},
    {"crop_name": "Moong Dal",               "category": "Pulses",  "market_name": "Indore APMC",          "base_price": 78.0},
    {"crop_name": "Urad Dal",                "category": "Pulses",  "market_name": "Nagpur Mandi",         "base_price": 72.0},
    {"crop_name": "Barley (Feed Grade)",     "category": "Barley",  "market_name": "Jaipur Mandi",         "base_price": 22.0},
]


# ── REST Endpoints ───────────────────────────────────────────────────────────

@router.get("/prices", response_model=List[MarketPriceOut])
def list_market_prices(
    commodity: Optional[str] = Query(None),
    district:  Optional[str] = Query(None),
    category:  Optional[str] = Query(None),
    limit:     int           = Query(50, ge=1, le=200),
    db: Session = Depends(get_db),
):
    """Fetch market prices filtered by commodity, category, or district."""
    query = db.query(MarketPrice)

    if commodity:
        safe_commodity = sanitize_search_query(commodity)
        query = query.filter(MarketPrice.crop_name.ilike(f"%{safe_commodity}%"))
    if category:
        safe_category = sanitize_search_query(category)
        query = query.filter(MarketPrice.category.ilike(f"%{safe_category}%"))
    if district:
        safe_district = sanitize_search_query(district)
        query = query.filter(MarketPrice.market_name.ilike(f"%{safe_district}%"))

    results = query.order_by(MarketPrice.recorded_at.desc()).limit(limit).all()

    if not results:
        return _generate_demo_prices(commodity, district, category)

    return results


@router.get("/prices/latest", response_model=List[MarketPriceOut])
def latest_prices(
    limit: int = Query(20, ge=1, le=100),
    db: Session = Depends(get_db),
):
    """Most recent market price entries – for live price ticker."""
    results = (
        db.query(MarketPrice)
        .order_by(MarketPrice.recorded_at.desc())
        .limit(limit)
        .all()
    )
    if not results:
        return _generate_demo_prices(None, None, None)
    return results


@router.get("/prices/trends")
def get_price_trends(
    crop_name: str = Query(..., min_length=1),
    days: int      = Query(30, ge=7, le=90),
    db: Session    = Depends(get_db),
):
    """Get price trend data for a specific crop over the last N days."""
    safe_name = sanitize_search_query(crop_name)

    from sqlalchemy import func
    cutoff = datetime.now(timezone.utc) - timedelta(days=days)
    results = (
        db.query(
            func.date(MarketPrice.recorded_at).label("date"),
            func.avg(MarketPrice.price_per_kg).label("avg_price"),
            func.min(MarketPrice.price_per_kg).label("min_price"),
            func.max(MarketPrice.price_per_kg).label("max_price"),
        )
        .filter(
            MarketPrice.crop_name.ilike(f"%{safe_name}%"),
            MarketPrice.recorded_at >= cutoff,
        )
        .group_by(func.date(MarketPrice.recorded_at))
        .order_by(func.date(MarketPrice.recorded_at))
        .all()
    )

    if results:
        return {
            "crop_name":  crop_name,
            "period_days": days,
            "data": [
                {
                    "date":      str(r.date),
                    "avg_price": round(float(r.avg_price), 2),
                    "min_price": round(float(r.min_price), 2),
                    "max_price": round(float(r.max_price), 2),
                }
                for r in results
            ],
        }

    return _generate_demo_trends(crop_name, days)


@router.post("/prices/seed")
def seed_market_prices(
    user_id: str   = Depends(get_current_user_id),
    db: Session    = Depends(get_db),
):
    """Seed demo market prices into the database."""
    count = 0
    for item in DEMO_PRICES:
        for i in range(5):
            variation = random.uniform(-0.1, 0.1)
            price     = round(item["base_price"] * (1 + variation), 2)
            entry = MarketPrice(
                id          = str(uuid.uuid4()),
                crop_name   = item["crop_name"],
                category    = item["category"],
                price_per_kg= price,
                market_name = item["market_name"],
                source      = "demo_seed",
                recorded_at = datetime.now(timezone.utc) - timedelta(days=random.randint(0, 30)),
            )
            db.add(entry)
            count += 1

    db.commit()
    return {"message": f"Seeded {count} market price entries", "status": "ok"}


@router.post("/prices/add")
async def add_market_price(
    crop_name:   str,
    category:    str,
    price_per_kg: float,
    market_name: str,
    source:      str = "manual",
    user_id: str   = Depends(get_current_user_id),
    db: Session    = Depends(get_db),
):
    """Add a new market price and broadcast to all WebSocket clients."""
    entry = MarketPrice(
        crop_name    = crop_name,
        category     = category,
        price_per_kg = price_per_kg,
        market_name  = market_name,
        source       = source,
    )
    db.add(entry)
    db.commit()
    db.refresh(entry)

    # Broadcast to all connected WebSocket clients
    await price_manager.broadcast({
        "event":       "price_update",
        "id":          entry.id,
        "crop_name":   entry.crop_name,
        "category":    entry.category,
        "price_per_kg":entry.price_per_kg,
        "market_name": entry.market_name,
        "recorded_at": entry.recorded_at.isoformat(),
    })

    return {"id": entry.id, "status": "added"}


# ── WebSocket Endpoint ───────────────────────────────────────────────────────

@router.websocket("/ws/prices")
async def prices_websocket(websocket: WebSocket, db: Session = Depends(get_db)):
    """
    WebSocket endpoint for live market price updates.

    On connect: sends the 20 most recent prices.
    On any price_manager.broadcast(): pushes the new price to all clients.
    Ping/pong: client may send "ping" → server replies "pong" to keep alive.

    NOTE: This works on Render/Railway/self-hosted.
          Vercel serverless does NOT support long-lived WebSocket connections.
          For Vercel deployments use Supabase Realtime on the client side.
    """
    await price_manager.connect(websocket)
    try:
        # Send snapshot of recent prices immediately on connect
        recent = (
            db.query(MarketPrice)
            .order_by(MarketPrice.recorded_at.desc())
            .limit(20)
            .all()
        )
        snapshot = []
        if recent:
            snapshot = [
                {
                    "id":          p.id,
                    "crop_name":   p.crop_name,
                    "category":    p.category,
                    "price_per_kg":p.price_per_kg,
                    "market_name": p.market_name,
                    "recorded_at": p.recorded_at.isoformat() if p.recorded_at else None,
                }
                for p in recent
            ]
        else:
            snapshot = [
                {
                    "id":           str(uuid.uuid4()),
                    "crop_name":    d["crop_name"],
                    "category":     d["category"],
                    "price_per_kg": round(d["base_price"] * random.uniform(0.95, 1.05), 2),
                    "market_name":  d["market_name"],
                    "recorded_at":  datetime.now(timezone.utc).isoformat(),
                }
                for d in DEMO_PRICES
            ]

        await websocket.send_text(json.dumps({"event": "snapshot", "data": snapshot}))

        while True:
            data = await websocket.receive_text()
            if data.strip() == "ping":
                await websocket.send_text("pong")

    except WebSocketDisconnect:
        price_manager.disconnect(websocket)
    except Exception as e:
        logger.error(f"[WS] Error: {e}")
        price_manager.disconnect(websocket)


# ── Helper Functions ─────────────────────────────────────────────────────────

def _generate_demo_prices(
    commodity: Optional[str],
    district:  Optional[str],
    category:  Optional[str],
) -> list:
    prices = []
    for item in DEMO_PRICES:
        if commodity and commodity.lower() not in item["crop_name"].lower():
            continue
        if category and category.lower() not in item["category"].lower():
            continue
        if district and district.lower() not in item["market_name"].lower():
            continue

        variation = random.uniform(-0.08, 0.08)
        price     = round(item["base_price"] * (1 + variation), 2)

        prices.append(
            MarketPriceOut(
                id          = str(uuid.uuid4()),
                crop_name   = item["crop_name"],
                category    = item["category"],
                price_per_kg= price,
                market_name = item["market_name"],
                source      = "demo",
                recorded_at = datetime.now(timezone.utc),
            )
        )
    return prices


def _generate_demo_trends(crop_name: str, days: int) -> dict:
    base_price = 30.0
    for item in DEMO_PRICES:
        if crop_name.lower() in item["crop_name"].lower():
            base_price = item["base_price"]
            break

    data = []
    for i in range(days):
        date      = datetime.now(timezone.utc) - timedelta(days=days - i)
        variation = random.uniform(-0.05, 0.05)
        trend     = 1 + (i / days) * 0.03
        price     = round(base_price * trend * (1 + variation), 2)
        data.append({
            "date":      date.strftime("%Y-%m-%d"),
            "avg_price": price,
            "min_price": round(price * 0.95, 2),
            "max_price": round(price * 1.05, 2),
        })

    return {
        "crop_name":  crop_name,
        "period_days": days,
        "data":       data,
        "source":     "demo",
    }
