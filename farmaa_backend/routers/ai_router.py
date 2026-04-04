"""AI Advisor router – Real LLM via OpenRouter + farming knowledge fallback."""

import os
import json
import urllib.request
import asyncio
import logging
from fastapi import APIRouter, HTTPException, Depends
from pydantic import BaseModel, Field
from typing import List, Optional
from sqlalchemy.orm import Session

from database import get_db
from auth import get_current_user_id

logger = logging.getLogger(__name__)

router = APIRouter(prefix="/ai", tags=["AI Advisor"])

# ── Config ───────────────────────────────────────────────────────────────────
OPENROUTER_API_KEY = os.getenv("OPENROUTER_API_KEY", "")
OPENROUTER_MODEL = os.getenv("OPENROUTER_MODEL", "openrouter/auto")
OPENROUTER_BASE_URL = os.getenv("OPENROUTER_BASE_URL", "https://openrouter.ai/api/v1")

SYSTEM_PROMPT = """You are Farmaa AI — a helpful, friendly agricultural advisor for Indian farmers and buyers.

Your expertise covers:
- Crop cultivation (rice, wheat, millets, pulses, maize, barley, sorghum)
- Market prices and selling strategies for Indian mandis
- Soil health, fertilizers (NPK recommendations), and organic farming
- Pest and disease management with IPM approaches
- Weather and seasonal farming guidance (Kharif, Rabi, Zaid)
- Government schemes (PM-KISAN, PMFBY, KCC, e-NAM, PM-KUSUM)
- Millet varieties and their health benefits
- Irrigation techniques (drip, canal, rainfed)
- Post-harvest storage and processing

Guidelines:
- Keep answers concise but informative (under 300 words)
- Use emojis and markdown formatting for readability
- Always include actionable advice
- Reference Indian units (hectares, quintals, kg) and currency (₹)
- When discussing prices, note they vary by region and season
- Suggest Farmaa app features when relevant (marketplace, orders)
- If asked about something outside farming, politely redirect to agriculture topics
- Respond in the same language as the user's message (Hindi, Tamil, Telugu, etc.)
"""


class ChatMessage(BaseModel):
    role: str  # 'user' or 'assistant'
    content: str = Field(..., min_length=1, max_length=2000)


class ChatRequest(BaseModel):
    messages: List[ChatMessage] = Field(..., min_length=1, max_length=50)
    context: Optional[dict] = None


class ChatResponse(BaseModel):
    content: str
    suggestions: List[str] = []


class YieldPredictRequest(BaseModel):
    crop: str = Field(..., min_length=1, max_length=50)
    area_hectares: float = Field(..., gt=0, le=10000)
    season: str = Field(default="Kharif")
    soil_type: str = Field(default="Red")
    irrigation: str = Field(default="Drip")


class SustainabilityRequest(BaseModel):
    irrigation: str = Field(default="Drip")
    fertilizer: str = Field(default="Organic")
    crop_rotation: bool = True


# ── Knowledge Base (fallback when API is unavailable) ────────────────────────

KNOWLEDGE_BASE = {
    "price": {
        "keywords": ["price", "rate", "cost", "market", "mandi", "விலை", "दाम", "भाव"],
        "response": (
            "📊 **Current Market Rates (Tamil Nadu region):**\n\n"
            "• Rice (Sona Masoori): ₹32-38/kg\n"
            "• Wheat: ₹24-28/kg\n"
            "• Ragi (Finger Millet): ₹28-35/kg\n"
            "• Bajra (Pearl Millet): ₹22-26/kg\n"
            "• Maize: ₹18-22/kg\n\n"
            "💡 Check the **Market Prices** section in Farmaa for real-time updates!"
        ),
        "suggestions": ["Show price trends", "Best time to sell", "Compare mandis"],
    },
    "yield": {
        "keywords": ["yield", "grow", "plant", "cultivation", "harvest", "விளைச்சல்", "उपज"],
        "response": (
            "🌾 **Yield Optimization Tips:**\n\n"
            "1. **Soil Testing** – Get NPK balance checked every season\n"
            "2. **Certified Seeds** – Use from authorized dealers\n"
            "3. **Irrigation** – Drip saves 40% water vs flood\n"
            "4. **Fertilizer** – Basal dose at sowing, top dress at 21 & 42 DAS\n\n"
            "📊 Expected yields per hectare:\n"
            "Rice: 4-6t | Wheat: 3-5t | Millet: 2-3t"
        ),
        "suggestions": ["Fertilizer guide", "Pest control", "Irrigation schedule"],
    },
    "pest": {
        "keywords": ["pest", "disease", "insect", "fungus", "blight", "spray", "கீடங்கள்", "कीट"],
        "response": (
            "🐛 **Pest Management (IPM):**\n\n"
            "**Rice:** Stem Borer → Trichogramma biocontrol\n"
            "**Wheat:** Rust → Use resistant varieties (HD-2967)\n"
            "**Millets:** Shoot fly → Early sowing + Carbofuran\n\n"
            "🌿 **Best Practices:**\n"
            "1. Pheromone traps for monitoring\n"
            "2. Natural predators (ladybugs, lacewings)\n"
            "3. Crop rotation to break pest cycles\n"
            "4. Chemical sprays only as last resort"
        ),
        "suggestions": ["Organic pest control", "Spray schedule", "Government subsidy"],
    },
    "scheme": {
        "keywords": ["scheme", "subsidy", "government", "pm", "kisan", "insurance", "loan", "योजना", "திட்டம்"],
        "response": (
            "🏛️ **Government Schemes:**\n\n"
            "• **PM-KISAN**: ₹6,000/year in 3 installments\n"
            "• **PMFBY**: Crop insurance at 1.5-2% premium\n"
            "• **KCC**: Farm loans at 4% interest\n"
            "• **PM-KUSUM**: Solar pump subsidy up to 60%\n"
            "• **e-NAM**: Online mandi marketplace\n\n"
            "📱 Apply at pmkisan.gov.in or your nearest CSC"
        ),
        "suggestions": ["PM-KISAN status", "Crop insurance", "KCC application"],
    },
}


def _find_fallback(query: str) -> tuple:
    """Find a knowledge base fallback response."""
    q = query.lower()
    for data in KNOWLEDGE_BASE.values():
        for kw in data["keywords"]:
            if kw in q:
                return data["response"], data["suggestions"]
    return None, None


async def _call_openrouter(messages: List[dict]) -> str:
    """Call OpenRouter API and return the assistant message content."""
    if not OPENROUTER_API_KEY:
        raise ValueError("OPENROUTER_API_KEY not configured")

    url = f"{OPENROUTER_BASE_URL}/chat/completions"
    headers = {
        "Authorization": f"Bearer {OPENROUTER_API_KEY}",
        "Content-Type": "application/json",
        "HTTP-Referer": "https://farmaa.app",
        "X-Title": "Farmaa AI Advisor",
    }
    payload = {
        "model": OPENROUTER_MODEL,
        "messages": [{"role": "system", "content": SYSTEM_PROMPT}] + messages,
        "max_tokens": 800,
        "temperature": 0.7,
    }

    def _sync_call():
        req = urllib.request.Request(
            url, 
            data=json.dumps(payload).encode("utf-8"), 
            headers=headers, 
            method="POST"
        )
        with urllib.request.urlopen(req, timeout=30.0) as response:
            return json.loads(response.read().decode())

    data = await asyncio.to_thread(_sync_call)
    return data["choices"][0]["message"]["content"]


# ── Endpoints ────────────────────────────────────────────────────────────────

@router.post("/chat", response_model=ChatResponse)
async def chat_with_advisor(body: ChatRequest):
    """AI Advisor – real LLM via OpenRouter with farming knowledge fallback."""
    if not body.messages:
        raise HTTPException(status_code=400, detail="No messages provided")

    last_msg = next(
        (m.content for m in reversed(body.messages) if m.role == "user"), ""
    )
    if not last_msg.strip():
        raise HTTPException(status_code=400, detail="Empty message")

    # Try OpenRouter first
    try:
        messages = [{"role": m.role, "content": m.content} for m in body.messages]
        content = await _call_openrouter(messages)
        return ChatResponse(
            content=content,
            suggestions=["Market prices", "Pest control", "Government schemes", "Millet guide"],
        )
    except Exception as e:
        logger.warning(f"[Farmaa AI] OpenRouter call failed: {e}")

    # Fallback to knowledge base
    content, suggestions = _find_fallback(last_msg)
    if content:
        return ChatResponse(content=content, suggestions=suggestions)

    # Default response
    return ChatResponse(
        content=(
            "👋 I'm the **Farmaa AI Advisor**! I can help with:\n\n"
            "🌾 **Market Prices** – Current rates across mandis\n"
            "🌱 **Crop Advice** – Yield, pest control, soil health\n"
            "🌻 **Millets** – Varieties, benefits, growing tips\n"
            "🏛️ **Government Schemes** – PM-KISAN, PMFBY, KCC\n\n"
            "Try asking: *\"What's the price of rice?\"* or *\"How to control pests in wheat?\"*"
        ),
        suggestions=["Market prices", "Crop advice", "Millet guide", "Government schemes"],
    )


@router.post("/yield-predict", response_model=ChatResponse)
async def predict_yield(body: YieldPredictRequest):
    """AI-powered yield prediction using OpenRouter LLM."""
    prompt = (
        f"Predict the crop yield for the following farm:\n"
        f"- Crop: {body.crop}\n"
        f"- Area: {body.area_hectares} hectares\n"
        f"- Season: {body.season}\n"
        f"- Soil Type: {body.soil_type}\n"
        f"- Irrigation: {body.irrigation}\n\n"
        f"Provide:\n"
        f"1. Estimated yield in kg\n"
        f"2. Confidence level (low/medium/high)\n"
        f"3. 3 specific actionable suggestions to maximize yield\n"
        f"4. Revenue estimate at current market rates in ₹\n\n"
        f"Format your response with emojis and markdown. Be specific to Indian agriculture."
    )

    try:
        messages = [{"role": "user", "content": prompt}]
        content = await _call_openrouter(messages)
        return ChatResponse(
            content=content,
            suggestions=["Fertilizer schedule", "Pest prevention", "Best selling time"],
        )
    except Exception as e:
        logger.warning(f"[Farmaa AI] Yield prediction failed: {e}")
        # Fallback calculation
        base_yields = {
            "millet": 2200, "wheat": 3500, "rice": 5000,
            "maize": 4000, "barley": 2800, "sorghum": 2500,
            "pulses": 1500,
        }
        base = base_yields.get(body.crop.lower(), 2500)
        factor = {"Drip": 1.25, "Canal": 1.10, "Rainfed": 0.85}.get(body.irrigation, 1.0)
        predicted = int(base * body.area_hectares * factor)

        return ChatResponse(
            content=(
                f"🌾 **Estimated Yield for {body.crop}**\n\n"
                f"📊 **{predicted:,} kg** ({predicted/1000:.1f} tonnes)\n"
                f"📐 Area: {body.area_hectares} hectares | Season: {body.season}\n"
                f"💧 Irrigation: {body.irrigation} | Soil: {body.soil_type}\n\n"
                f"**Suggestions:**\n"
                f"• Use certified seeds for 10-15% better yield\n"
                f"• Apply balanced NPK fertilizer based on soil test\n"
                f"• Schedule irrigation at critical growth stages\n\n"
                f"_Note: This is an estimate. AI-powered prediction is temporarily unavailable._"
            ),
            suggestions=["Detailed crop guide", "Soil testing", "Market prices"],
        )


@router.post("/sustainability", response_model=ChatResponse)
async def sustainability_score(body: SustainabilityRequest):
    """AI-powered sustainability assessment."""
    prompt = (
        f"Evaluate the sustainability of this farming practice:\n"
        f"- Irrigation: {body.irrigation}\n"
        f"- Fertilizer: {body.fertilizer}\n"
        f"- Crop Rotation: {'Yes' if body.crop_rotation else 'No'}\n\n"
        f"Provide:\n"
        f"1. A sustainability score out of 100\n"
        f"2. Rating: Excellent/Good/Needs Improvement\n"
        f"3. 3 specific tips to improve sustainability\n"
        f"4. Environmental impact summary\n\n"
        f"Format with emojis and markdown. Focus on Indian agriculture context."
    )

    try:
        messages = [{"role": "user", "content": prompt}]
        content = await _call_openrouter(messages)
        return ChatResponse(
            content=content,
            suggestions=["Organic farming", "Water conservation", "Soil health"],
        )
    except Exception as e:
        logger.warning(f"[Farmaa AI] Sustainability check failed: {e}")
        # Fallback
        score = 40
        tips = []
        if body.irrigation == "Drip":
            score += 30
        elif body.irrigation == "Canal":
            score += 15
        else:
            tips.append("💧 Switch to drip irrigation to save 40% water")
        if body.fertilizer == "Organic":
            score += 20
        elif body.fertilizer == "Chemical":
            score += 5
            tips.append("🌿 Use organic compost to improve soil health")
        else:
            score += 12
        if body.crop_rotation:
            score += 10
        else:
            tips.append("♻️ Practice crop rotation to prevent soil depletion")

        score = min(score, 100)
        rating = "Excellent" if score >= 75 else "Good" if score >= 50 else "Needs Improvement"

        return ChatResponse(
            content=(
                f"♻️ **Sustainability Score: {score}/100 — {rating}**\n\n"
                f"💧 Irrigation: {body.irrigation}\n"
                f"🌱 Fertilizer: {body.fertilizer}\n"
                f"🔄 Crop Rotation: {'Yes ✅' if body.crop_rotation else 'No ❌'}\n\n"
                + ("\n".join(f"💡 {t}" for t in tips) if tips else "🎉 Great practices! Keep it up!")
                + "\n\n_Note: AI-powered analysis is temporarily unavailable._"
            ),
            suggestions=["Organic farming guide", "Water-saving tips", "Soil testing"],
        )
