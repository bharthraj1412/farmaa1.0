"""Database initialisation script – reads DATABASE_URL from environment.

Usage:
    export DATABASE_URL="postgresql://..."
    python init_db.py
"""
import os
import sys
from dotenv import load_dotenv

load_dotenv()

url = os.getenv("DATABASE_URL")
if not url:
    print("ERROR: DATABASE_URL environment variable is not set.")
    print("Set it in .env or export it before running this script.")
    sys.exit(1)

# Normalise Render/Heroku postgres:// → postgresql://
if url.startswith("postgres://"):
    url = url.replace("postgres://", "postgresql://", 1)

try:
    import psycopg2

    conn = psycopg2.connect(url)
    conn.autocommit = True
    cursor = conn.cursor()

    schema_path = os.path.join(os.path.dirname(__file__), "supabase_schema.sql")
    with open(schema_path, "r", encoding="utf-8") as f:
        sql_script = f.read()

    cursor.execute(sql_script)
    print("✅ Database initialised successfully.")

except Exception as e:
    print(f"❌ Error: {e}")
    sys.exit(1)
finally:
    if "cursor" in dir():
        cursor.close()  # type: ignore[possibly-undefined]
    if "conn" in dir():
        conn.close()  # type: ignore[possibly-undefined]
