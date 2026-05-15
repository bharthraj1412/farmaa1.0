"""Market Prices router – Comprehensive Indian grain prices across all major cities."""

from fastapi import APIRouter, Depends, Query
from sqlalchemy.orm import Session
from typing import List, Optional
from datetime import datetime, timedelta, timezone
import random
import uuid
import hashlib

from database import get_db
from models import MarketPrice
from schemas import MarketPriceOut
from middleware import sanitize_search_query, require_role
from auth import get_current_user_id

router = APIRouter(prefix="/market", tags=["Market Prices"])

# ── Comprehensive Grain Dataset ───────────────────────────────────────────────
# All prices are in ₹/quintal (100 kg). Realistic 2025 Indian market rates.

GRAINS = {
    # --- Rice varieties ---
    "Rice (Sona Masoori)":   {"category": "Rice",    "base": 3500, "min": 3200, "max": 3900},
    "Rice (Ponni)":          {"category": "Rice",    "base": 3200, "min": 2900, "max": 3600},
    "Rice (Basmati)":        {"category": "Rice",    "base": 5500, "min": 5000, "max": 6200},
    "Rice (IR-64)":          {"category": "Rice",    "base": 2800, "min": 2500, "max": 3200},
    "Rice (Raw)":            {"category": "Rice",    "base": 3000, "min": 2700, "max": 3400},
    "Rice (Boiled)":         {"category": "Rice",    "base": 3100, "min": 2800, "max": 3500},
    # --- Wheat varieties ---
    "Wheat (Lok-1)":         {"category": "Wheat",   "base": 2500, "min": 2200, "max": 2800},
    "Wheat (HD-2967)":       {"category": "Wheat",   "base": 2600, "min": 2300, "max": 2900},
    "Wheat (Lokwan)":        {"category": "Wheat",   "base": 2750, "min": 2500, "max": 3100},
    "Wheat (Sharbati)":      {"category": "Wheat",   "base": 2900, "min": 2600, "max": 3300},
    # --- Millet varieties ---
    "Ragi (Finger Millet)":  {"category": "Millet",  "base": 3200, "min": 2900, "max": 3700},
    "Bajra (Pearl Millet)":  {"category": "Millet",  "base": 2400, "min": 2100, "max": 2800},
    "Jowar (Sorghum)":       {"category": "Millet",  "base": 2800, "min": 2500, "max": 3200},
    "Foxtail Millet":        {"category": "Millet",  "base": 4500, "min": 4000, "max": 5200},
    "Kodo Millet":           {"category": "Millet",  "base": 4200, "min": 3800, "max": 4800},
    "Barnyard Millet":       {"category": "Millet",  "base": 4000, "min": 3600, "max": 4600},
    "Little Millet (Samai)": {"category": "Millet",  "base": 4800, "min": 4200, "max": 5500},
    # --- Maize ---
    "Maize (Yellow)":        {"category": "Maize",   "base": 2000, "min": 1700, "max": 2400},
    "Maize (White)":         {"category": "Maize",   "base": 1900, "min": 1600, "max": 2200},
    "Sweet Corn":            {"category": "Maize",   "base": 2200, "min": 1900, "max": 2600},
    # --- Pulses ---
    "Toor Dal":              {"category": "Pulses",  "base": 8500, "min": 7500, "max": 9500},
    "Chana Dal":             {"category": "Pulses",  "base": 6200, "min": 5500, "max": 7000},
    "Moong Dal":             {"category": "Pulses",  "base": 7800, "min": 7000, "max": 8800},
    "Urad Dal":              {"category": "Pulses",  "base": 7200, "min": 6500, "max": 8200},
    "Masoor Dal":            {"category": "Pulses",  "base": 5800, "min": 5000, "max": 6600},
    "Rajma":                 {"category": "Pulses",  "base": 9000, "min": 8000, "max": 10500},
    "Lobia (Black-eye)":     {"category": "Pulses",  "base": 5500, "min": 4800, "max": 6500},
    # --- Barley ---
    "Barley (Feed Grade)":   {"category": "Barley",  "base": 2200, "min": 1900, "max": 2600},
    "Barley (Malt Grade)":   {"category": "Barley",  "base": 2600, "min": 2300, "max": 3000},
    # --- Oilseeds ---
    "Groundnut":             {"category": "Oilseed", "base": 5500, "min": 5000, "max": 6500},
    "Sunflower":             {"category": "Oilseed", "base": 5000, "min": 4500, "max": 5800},
    "Sesame (Gingelly)":     {"category": "Oilseed", "base": 9000, "min": 8000, "max": 10500},
    "Mustard":               {"category": "Oilseed", "base": 5200, "min": 4700, "max": 6000},
    "Soybean":               {"category": "Oilseed", "base": 4200, "min": 3700, "max": 5000},
}

# Major mandis / APMCs across India (city → state)
MARKETS = {
    # Tamil Nadu
    "Koyambedu APMC, Chennai":    "Tamil Nadu",
    "Thanjavur Mandi":            "Tamil Nadu",
    "Coimbatore APMC":            "Tamil Nadu",
    "Salem Market Yard":          "Tamil Nadu",
    "Madurai APMC":               "Tamil Nadu",
    "Erode Market":               "Tamil Nadu",
    "Tirupur Mandi":              "Tamil Nadu",
    "Tiruchirappalli Mandi":      "Tamil Nadu",
    "Vellore Market":             "Tamil Nadu",
    "Dindigul APMC":              "Tamil Nadu",
    # Maharashtra
    "Pune APMC (Gultekdi)":       "Maharashtra",
    "Mumbai APMC, Vashi":         "Maharashtra",
    "Nagpur Mandi":               "Maharashtra",
    "Nashik APMC":                "Maharashtra",
    "Solapur APMC":               "Maharashtra",
    "Latur APMC":                 "Maharashtra",
    "Aurangabad Market":          "Maharashtra",
    # Karnataka
    "Davangere Market":           "Karnataka",
    "Mysuru Market Yard":         "Karnataka",
    "Hubli APMC":                 "Karnataka",
    "Bengaluru APMC":             "Karnataka",
    "Tumkur Market":              "Karnataka",
    "Dharwad Mandi":              "Karnataka",
    # Andhra Pradesh & Telangana
    "Hyderabad Market":           "Telangana",
    "Warangal Market":            "Telangana",
    "Guntur APMC":                "Andhra Pradesh",
    "Vijaywada Market":           "Andhra Pradesh",
    "Kurnool Mandi":              "Andhra Pradesh",
    # North India
    "Delhi Wholesale Market":     "Delhi",
    "Jaipur Mandi":               "Rajasthan",
    "Jodhpur Mandi":              "Rajasthan",
    "Ajmer Market":               "Rajasthan",
    "Indore Grain Market":        "Madhya Pradesh",
    "Bhopal Mandi":               "Madhya Pradesh",
    "Jabalpur Market":            "Madhya Pradesh",
    "Lucknow Mandi":              "Uttar Pradesh",
    "Agra Grain Market":          "Uttar Pradesh",
    "Varanasi Mandi":             "Uttar Pradesh",
    "Patna Market":               "Bihar",
    "Muzaffarpur Mandi":          "Bihar",
    # West India
    "Ahmedabad APMC":             "Gujarat",
    "Rajkot Mandi":               "Gujarat",
    "Surat Market":               "Gujarat",
    # Punjab & Haryana
    "Amritsar Mandi":             "Punjab",
    "Ludhiana Grain Market":      "Punjab",
    "Ambala Mandi":               "Haryana",
    "Hisar Grain Market":         "Haryana",
}


def _deterministic_price(grain: str, market: str, day_offset: int = 0) -> float:
    """
    Generate a deterministic but realistic price using a seed-based approach.
    Same grain+market+day always returns the same price (no random drift per request).
    """
    grain_data = GRAINS.get(grain, {"base": 3000, "min": 2500, "max": 3500})
    seed_str = f"{grain}|{market}|{day_offset}"
    seed = int(hashlib.md5(seed_str.encode()).hexdigest()[:8], 16)
    rng = random.Random(seed)

    base = grain_data["base"]
    mn = grain_data["min"]
    mx = grain_data["max"]

    # Market premium/discount (some mandis consistently higher/lower)
    market_seed = int(hashlib.md5(market.encode()).hexdigest()[:4], 16)
    market_rng = random.Random(market_seed)
    market_factor = market_rng.uniform(0.93, 1.07)

    # Daily variation
    daily_variation = rng.uniform(-0.05, 0.05)
    price = base * market_factor * (1 + daily_variation)
    return round(max(mn, min(mx, price)), 2)


# ── API Endpoints ─────────────────────────────────────────────────────────────

@router.get("/prices", response_model=List[MarketPriceOut])
def list_market_prices(
    commodity: Optional[str] = Query(None, description="Grain name or category to filter"),
    district: Optional[str] = Query(None, description="City/market name to filter"),
    category: Optional[str] = Query(None, description="Category: Rice/Wheat/Millet/Maize/Pulses/Barley/Oilseed"),
    db: Session = Depends(get_db)
):
    """
    Fetch current market prices.
    Falls back to comprehensive demo data covering all grains × all cities.
    """
    # Try database first
    query = db.query(MarketPrice)
    if commodity:
        safe = sanitize_search_query(commodity)
        query = query.filter(MarketPrice.crop_name.ilike(f"%{safe}%"))
    if category:
        safe = sanitize_search_query(category)
        query = query.filter(MarketPrice.category.ilike(f"%{safe}%"))
    if district:
        safe = sanitize_search_query(district)
        query = query.filter(MarketPrice.market_name.ilike(f"%{safe}%"))

    results = query.order_by(MarketPrice.recorded_at.desc()).limit(100).all()
    if results:
        return results

    # Generate comprehensive demo data
    return _generate_all_prices(commodity, district, category)


@router.get("/prices/categories")
def get_categories():
    """Return all available grain categories."""
    cats = sorted(set(v["category"] for v in GRAINS.values()))
    return {"categories": cats}


@router.get("/prices/grains")
def get_grains(category: Optional[str] = Query(None)):
    """Return all available grain names, optionally filtered by category."""
    grains = [
        {"name": k, "category": v["category"], "base_price": v["base"]}
        for k, v in GRAINS.items()
        if category is None or v["category"].lower() == category.lower()
    ]
    return {"grains": sorted(grains, key=lambda x: (x["category"], x["name"]))}


@router.get("/prices/markets")
def get_markets(state: Optional[str] = Query(None)):
    """Return all available markets/cities."""
    markets = [
        {"name": k, "state": v}
        for k, v in MARKETS.items()
        if state is None or v.lower() == state.lower()
    ]
    return {"markets": sorted(markets, key=lambda x: (x["state"], x["name"]))}


@router.get("/prices/trends")
def get_price_trends(
    crop_name: str = Query(..., min_length=1, description="Grain name"),
    market_name: Optional[str] = Query(None, description="Market/city name"),
    days: int = Query(30, ge=7, le=90),
    db: Session = Depends(get_db)
):
    """
    Get price trend data for a specific crop over the last N days.
    Returns daily prices suitable for charting.
    """
    safe_name = sanitize_search_query(crop_name)
    safe_market = sanitize_search_query(market_name) if market_name else None

    from sqlalchemy import func
    cutoff = datetime.now(timezone.utc) - timedelta(days=days)
    q = db.query(
        func.date(MarketPrice.recorded_at).label("date"),
        func.avg(MarketPrice.price_per_kg).label("avg_price"),
        func.min(MarketPrice.price_per_kg).label("min_price"),
        func.max(MarketPrice.price_per_kg).label("max_price"),
    ).filter(
        MarketPrice.crop_name.ilike(f"%{safe_name}%"),
        MarketPrice.recorded_at >= cutoff,
    )
    if safe_market:
        q = q.filter(MarketPrice.market_name.ilike(f"%{safe_market}%"))

    results = q.group_by(func.date(MarketPrice.recorded_at)) \
                .order_by(func.date(MarketPrice.recorded_at)).all()

    if results:
        # Convert price_per_kg → ₹/quintal (×100)
        return {
            "crop_name": crop_name,
            "market_name": market_name,
            "period_days": days,
            "unit": "INR/quintal",
            "data": [
                {
                    "date": str(r.date),
                    "avg_price": round(float(r.avg_price) * 100, 2),
                    "min_price": round(float(r.min_price) * 100, 2),
                    "max_price": round(float(r.max_price) * 100, 2),
                }
                for r in results
            ],
        }

    return _generate_trend_data(crop_name, market_name or list(MARKETS.keys())[0], days)


@router.get("/prices/summary")
def get_price_summary():
    """
    Return a quick summary of today's prices across all categories.
    Useful for home screen widgets.
    """
    summary = {}
    for category in set(v["category"] for v in GRAINS.values()):
        grains_in_cat = [(k, v) for k, v in GRAINS.items() if v["category"] == category]
        cat_prices = [
            _deterministic_price(g, "Delhi Wholesale Market", 0)
            for g, _ in grains_in_cat
        ]
        summary[category] = {
            "avg_price": round(sum(cat_prices) / len(cat_prices), 2),
            "min_price": round(min(cat_prices), 2),
            "max_price": round(max(cat_prices), 2),
            "grain_count": len(grains_in_cat),
        }
    return {"date": datetime.now(timezone.utc).strftime("%Y-%m-%d"), "summary": summary}


@router.post("/prices/seed", dependencies=[Depends(require_role("admin"))])
def seed_market_prices(
    user_id: str = Depends(get_current_user_id),
    db: Session = Depends(get_db)
):
    """Seed comprehensive market prices into the database."""
    count = 0
    now = datetime.now(timezone.utc)

    for grain_name, grain_data in GRAINS.items():
        for market_name in MARKETS.keys():
            # Seed 30 days of data
            for day in range(30):
                day_offset = 30 - day
                price_per_quintal = _deterministic_price(grain_name, market_name, day_offset)
                price_per_kg = round(price_per_quintal / 100, 4)

                entry = MarketPrice(
                    id=str(uuid.uuid4()),
                    crop_name=grain_name,
                    category=grain_data["category"],
                    price_per_kg=price_per_kg,
                    market_name=market_name,
                    source="seed_data",
                    recorded_at=now - timedelta(days=day_offset),
                )
                db.add(entry)
                count += 1

    db.commit()
    return {
        "message": f"Seeded {count} market price entries",
        "grains": len(GRAINS),
        "markets": len(MARKETS),
        "days": 30,
        "status": "ok",
    }


# ── Helper Functions ──────────────────────────────────────────────────────────

def _generate_all_prices(
    commodity: Optional[str],
    district: Optional[str],
    category: Optional[str],
) -> list:
    """Generate demo price data for all grain × market combinations."""
    results = []
    now = datetime.now(timezone.utc)

    for grain_name, grain_data in GRAINS.items():
        # Apply category filter
        if category and grain_data["category"].lower() != category.lower():
            continue
        # Apply commodity filter
        if commodity and commodity.lower() not in grain_name.lower() \
                and commodity.lower() not in grain_data["category"].lower():
            continue

        for market_name, state in MARKETS.items():
            # Apply district/city filter
            if district and district.lower() not in market_name.lower() \
                    and district.lower() not in state.lower():
                continue

            price_per_quintal = _deterministic_price(grain_name, market_name, 0)
            price_per_kg = round(price_per_quintal / 100, 4)

            results.append(MarketPriceOut(
                id=str(uuid.uuid4()),
                crop_name=grain_name,
                category=grain_data["category"],
                price_per_kg=price_per_kg,
                market_name=market_name,
                source="demo",
                recorded_at=now,
            ))

    # Limit to 200 results to avoid huge payloads
    return results[:200]


def _generate_trend_data(grain: str, market: str, days: int) -> dict:
    """Generate realistic 7–90 day price trend for charting."""
    grain_data = GRAINS.get(grain, {"base": 3000, "min": 2500, "max": 3500})
    data = []
    now = datetime.now(timezone.utc)

    for i in range(days):
        day_offset = days - i
        price = _deterministic_price(grain, market, day_offset)
        date = now - timedelta(days=day_offset)
        data.append({
            "date": date.strftime("%Y-%m-%d"),
            "avg_price": price,
            "min_price": round(price * 0.97, 2),
            "max_price": round(price * 1.03, 2),
        })

    return {
        "crop_name": grain,
        "market_name": market,
        "period_days": days,
        "unit": "INR/quintal",
        "data": data,
        "source": "demo",
    }
