# Farmaa: Simple Project Understanding & Algorithms Used

## 1. What is Farmaa? (Simple Understanding)
**Farmaa** is a digital marketplace specifically designed for agriculture. It acts as a bridge between **Farmers** (who grow and sell crops) and **Buyers** (who purchase the crops). 

### How it works:
- **Mobile App (Frontend):** Built with **Flutter**, this is what the users install on their phones. It provides a smooth, fast, and easy-to-use interface.
- **Server (Backend):** Built with **FastAPI (Python)**. It handles all the complex logic, securely processes orders, and serves as the "brain" of the application.
- **Database:** Uses **PostgreSQL (via Supabase)** to safely store all information like user profiles, crop inventory, and order history.

**Key Features:**
- Farmers can list their harvested crops for sale.
- Buyers can browse the market and purchase crops securely.
- An **AI Advisor** is available to answer agriculture-related questions (like weather updates, soil tips, and crop market prices).

---

## 2. Which Algorithms Are Used & Why?

When people hear "AI", they often think of complex Neural Networks or Large Language Models (like ChatGPT). However, Farmaa takes a highly optimized and practical approach. 

### Core Algorithm: Rule-Based Keyword Matching (NLP)
*Found in:* `farmaa_backend/routers/ai_router.py`

When a user asks the AI Advisor a question, the system uses a **Rule-Based Keyword Matching Algorithm**. 

**How it works:**
1. The user sends a question (e.g., *"What is the best way to control pests in wheat?"*).
2. The algorithm converts the text to lowercase and scans it linearly.
3. It checks the text against a predefined dictionary (the `KNOWLEDGE_BASE`) containing specific keywords (e.g., `"pest"`, `"disease"`, `"insect"`).
4. As soon as a keyword match is found, the algorithm returns a highly detailed, pre-written expert response associated with that keyword.

**Why is this Algorithm Used?**
1. **100% Accuracy (No Hallucinations):** In agriculture, giving a farmer the wrong fertilizer ratio or pest management advice can destroy their entire crop. LLMs (like OpenAI) sometimes guess or make up facts. A rule-based algorithm ensures the farmer *only* gets agriculturally vetted, factual advice.
2. **Lightning Fast:** Keyword matching happens in milliseconds. It requires almost zero processing power compared to running a machine learning model.
3. **Completely Free:** It runs locally on the FastAPI server, meaning the project does not have to pay expensive third-party API costs (like OpenAI API fees) for every single chat message.
4. **Offline / Low-Resource Capable:** Because it doesn't need external heavy compute, it runs smoothly even on lower-end hosting servers.

### Secondary Algorithms & Systems

#### A. Cryptographic JWT Verification Algorithm (RSA/SHA-256)
*Found in:* `farmaa_backend/auth.py`
- **What it does:** Instead of the server checking passwords, the Flutter app logs in via Google/Firebase. Firebase gives the app a JWT (JSON Web Token). The Python backend uses Cryptographic Hashing Algorithms to verify the signature of this token to prove the user is who they claim to be without ever seeing their password.
- **Why it's used:** Unmatched security. It offloads password security to Google while keeping the API perfectly stateless and protected.

#### B. ACID Transactional Locking (Database Algorithm)
*Found in:* `farmaa_backend/database.py` and Order creation logic
- **What it does:** Uses standard database transaction mechanisms to ensure data integrity.
- **Why it's used:** If a farmer has 50kg of rice, and two buyers try to buy 50kg at the exact same millisecond, this transactional mechanism queues the operations. It prevents the system from accidentally selling 100kg and ending up in negative stock. 

---
### Summary
Farmaa is intentionally designed to be **lightweight, fast, and highly secure**. Instead of relying on buzzword AI technologies that cost money and make mistakes, it uses highly reliable **Rule-Based Matching** for its AI Advisor, ensuring farmers get instant, free, and perfectly accurate advice every time.
