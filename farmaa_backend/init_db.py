import psycopg2

url = "postgresql://postgres.wwtlqasnplvejymsbmvm:jIaHHCoN38pZ2ayQ@aws-1-ap-northeast-2.pooler.supabase.com:6543/postgres"

try:
    conn = psycopg2.connect(url)
    conn.autocommit = True
    cursor = conn.cursor()
    
    with open("supabase_schema.sql", "r", encoding="utf-8") as file:
        sql_script = file.read()
        
    cursor.execute(sql_script)
    print("Database initialized successfully.")
    
except Exception as e:
    print(f"Error: {e}")
finally:
    if 'cursor' in locals():
        cursor.close()
    if 'conn' in locals():
        conn.close()
