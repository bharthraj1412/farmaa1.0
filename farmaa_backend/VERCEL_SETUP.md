# Vercel Deployment Setup — Required Environment Variables

The backend is deployed on Vercel as a Python serverless function.  
**Vercel does NOT read `.env` files** — you must set environment variables in the Vercel Dashboard.

## Required Variables

Go to: **Vercel Dashboard → Your Project → Settings → Environment Variables**

Add these (all required for production):

| Variable | Value | Required |
|----------|-------|----------|
| `ENVIRONMENT` | `production` | ✅ (already in vercel.json) |
| `SECRET_KEY` | *(your secret key — any random string)* | ✅ CRITICAL |
| `DATABASE_URL` | *(your Supabase PostgreSQL connection string)* | ✅ CRITICAL |
| `FIREBASE_PROJECT_ID` | `farmaa-bdbe3` | ✅ |
| `FIREBASE_CREDENTIALS_JSON` | *(full Firebase service account JSON — see below)* | ✅ |
| `OPENROUTER_API_KEY` | *(your OpenRouter API key)* | Optional (AI chat) |

## Firebase Credentials JSON

1. Go to **Firebase Console** → Project Settings → Service Accounts
2. Click **Generate new private key** → Download the JSON file
3. Paste the **entire contents** of that JSON as the value of `FIREBASE_CREDENTIALS_JSON` in Vercel

> ⚠️ **IMPORTANT**: The private key inside the JSON must use `\n` (actual newline or single backslash-n), NOT `\\n` (double backslash). Vercel will inject the value as-is.

Example format (replace with your actual values):
```json
{
  "type": "service_account",
  "project_id": "farmaa-bdbe3",
  "private_key_id": "YOUR_KEY_ID",
  "private_key": "-----BEGIN PRIVATE KEY-----\nYOUR_PRIVATE_KEY_HERE\n-----END PRIVATE KEY-----\n",
  "client_email": "firebase-adminsdk-XXXX@farmaa-bdbe3.iam.gserviceaccount.com",
  "client_id": "YOUR_CLIENT_ID",
  "auth_uri": "https://accounts.google.com/o/oauth2/auth",
  "token_uri": "https://oauth2.googleapis.com/token"
}
```

## Database URL Format

Get your connection string from **Supabase Dashboard → Settings → Database → Connection string (URI)**:
```
postgresql://postgres.YOUR_PROJECT_REF:YOUR_PASSWORD@aws-0-REGION.pooler.supabase.com:6543/postgres
```
URL-encode any special characters in your password (e.g., `@` → `%40`, `"` → `%22`).

## After Setting Variables

1. Go to your Vercel project **Deployments** tab
2. Click the **...** menu on the latest deployment
3. Click **Redeploy**
4. Wait for deploy to finish
5. Test: visit `https://farmaa1-0.vercel.app/health` — should return `{"status":"ok"}`

## Database Setup

Make sure you've run the SQL schema in your Supabase SQL Editor.  
The schema file is at: `farmaa_backend/setup_database.sql`
