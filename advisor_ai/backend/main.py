# from http import client
import io
import os
import json
import base64
import re as _re
from typing import Optional
import uuid as _uuid
from fastapi import FastAPI, UploadFile, File, Form, HTTPException
from fastapi.middleware.cors import CORSMiddleware
from fastapi.responses import HTMLResponse
from pydantic import BaseModel
import sqlite3
from datetime import date, datetime, timedelta
import re

app = FastAPI(title="Advisor AI Memory Intelligence")

app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)

DB_NAME = "advisor_ai.db"


# =========================
# MODELS
# =========================

class Client(BaseModel):
    name: str
    age: str = ""
    birthday: str = ""
    sex: str = ""
    marital: str = ""
    health: str = ""
    children: str = ""
    concern: str = ""
    personality: str = ""
    risk: str = ""
    email: str = ""
    phone: str = ""



class Event(BaseModel):
    client_id: int
    date: str
    time: str
    purpose: str = ""


class MeetingUpdate(BaseModel):
    client_id: int
    title: str = ""
    meeting_date: str
    notes: str = ""
    concern: str = ""
    personality: str = ""
    risk: str = ""
    health: str = ""
    children: str = ""
    follow_up: str = ""
    interest_level: str = "Maybe"

class CompletedAction(BaseModel):
    action_id: str
    client_id: int
    action_type: str = ""
    message: str = ""


class CopilotRequest(BaseModel):
    client_id: int
    notes: str


class SummarizeRequest(BaseModel):
    notes: str


class Expense(BaseModel):
    category: str
    description: str = ""
    amount: float
    expense_date: str
    client_id: Optional[int] = None


class Referral(BaseModel):
    client_id: Optional[int] = None
    client_name: str = ""
    partner_name: str
    partner_type: str = ""
    direction: str = "referral_out"
    status: str = "Pending"
    notes: str = ""


class ReferralStatusUpdate(BaseModel):
    status: str


EXPENSE_CATEGORIES = [
    "Travel and Transportation",
    "Client Entertainment and Relationship Building",
    "Operational Expenses",
    "Client Service",
    "Professional Development",
    "Business Development & Marketing",
]

REFERRAL_STATUSES = [
    "Pending",
    "In Progress",
    "Closed-Won",
    "Closed-Lost",
]


# =========================
# DATABASE
# =========================

def get_conn():
    conn = sqlite3.connect(DB_NAME)
    conn.row_factory = sqlite3.Row
    return conn


def init_db():
    conn = get_conn()
    cursor = conn.cursor()

    cursor.execute("""
    CREATE TABLE IF NOT EXISTS clients (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        name TEXT,
        age TEXT,
        birthday TEXT,
        sex TEXT,
        marital TEXT,
        health TEXT,
        children TEXT,
        concern TEXT,
        personality TEXT,
        risk TEXT
    )
    """)

    cursor.execute("""
    CREATE TABLE IF NOT EXISTS events (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        client_id INTEGER,
        date TEXT,
        time TEXT,
        purpose TEXT,
        FOREIGN KEY(client_id) REFERENCES clients(id)
    )
    """)

    cursor.execute("""
    CREATE TABLE IF NOT EXISTS meeting_updates (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        client_id INTEGER,
        title TEXT,
        meeting_date TEXT,
        notes TEXT,
        summary TEXT,
        sentiment TEXT,
        concern TEXT,
        personality TEXT,
        risk TEXT,
        health TEXT,
        children TEXT,
        follow_up TEXT,
        follow_up_date TEXT,
        interest_level TEXT,
        relationship_score INTEGER,
        follow_up_message TEXT,
        created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
        FOREIGN KEY(client_id) REFERENCES clients(id)
    )
    """)

    cursor.execute("""
    CREATE TABLE IF NOT EXISTS memories (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        client_id INTEGER,
        memory_type TEXT,
        content TEXT,
        confidence INTEGER,
        created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
        FOREIGN KEY(client_id) REFERENCES clients(id)
    )
    """)

    cursor.execute("""
    CREATE TABLE IF NOT EXISTS opportunities (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        client_id INTEGER,
        opportunity_type TEXT,
        reason TEXT,
        confidence INTEGER,
        suggested_action TEXT,
        created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
        FOREIGN KEY(client_id) REFERENCES clients(id)
    )
    """)

    cursor.execute("""
    CREATE TABLE IF NOT EXISTS expenses (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        category TEXT,
        description TEXT,
        amount REAL,
        expense_date TEXT,
        client_id INTEGER,
        created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
        FOREIGN KEY(client_id) REFERENCES clients(id)
    )
    """)

    cursor.execute("""
    CREATE TABLE IF NOT EXISTS referrals (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        client_id INTEGER,
        client_name TEXT,
        partner_name TEXT,
        partner_type TEXT,
        direction TEXT,
        status TEXT,
        notes TEXT,
        created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
        FOREIGN KEY(client_id) REFERENCES clients(id)
    )
    """)

    cursor.execute("""
    CREATE TABLE IF NOT EXISTS prospects (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        session_id TEXT UNIQUE,
        name TEXT DEFAULT '',
        age TEXT DEFAULT '',
        income TEXT DEFAULT '',
        marital TEXT DEFAULT '',
        children TEXT DEFAULT '',
        health TEXT DEFAULT '',
        goals TEXT DEFAULT '',
        risk TEXT DEFAULT '',
        language TEXT DEFAULT 'English',
        interest_score INTEGER DEFAULT 0,
        status TEXT DEFAULT 'new',
        recommended_products TEXT DEFAULT '[]',
        conversation_summary TEXT DEFAULT '',
        meeting_request TEXT DEFAULT '',
        created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
        updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
    )
    """)

    cursor.execute("""
    CREATE TABLE IF NOT EXISTS chat_messages (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        session_id TEXT,
        role TEXT,
        content TEXT,
        message_type TEXT DEFAULT 'text',
        created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
    )
    """)

    cursor.execute("""
    CREATE TABLE IF NOT EXISTS prospect_meetings (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        prospect_id INTEGER,
        session_id TEXT,
        slot TEXT,
        status TEXT DEFAULT 'pending',
        advisor_response TEXT DEFAULT '',
        prospect_name TEXT DEFAULT '',
        prospect_goals TEXT DEFAULT '',
        interest_score INTEGER DEFAULT 0,
        recommended_product TEXT DEFAULT '',
        created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
        updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
    )
    """)

    cursor.execute("""
    CREATE TABLE IF NOT EXISTS completed_actions (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        action_id TEXT UNIQUE,
        client_id INTEGER,
        action_type TEXT,
        message TEXT,
        completed_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
    )
    """)

    # Migrate: add email/phone if not present
    existing = {r[1] for r in cursor.execute("PRAGMA table_info(clients)").fetchall()}
    if "email" not in existing:
        cursor.execute("ALTER TABLE clients ADD COLUMN email TEXT DEFAULT ''")
    if "phone" not in existing:
        cursor.execute("ALTER TABLE clients ADD COLUMN phone TEXT DEFAULT ''")

    p_existing = {r[1] for r in cursor.execute("PRAGMA table_info(prospects)").fetchall()}
    if "meeting_slot" not in p_existing:
        cursor.execute("ALTER TABLE prospects ADD COLUMN meeting_slot TEXT DEFAULT ''")
    if "voice_transcript" not in p_existing:
        cursor.execute("ALTER TABLE prospects ADD COLUMN voice_transcript TEXT DEFAULT ''")
    if "ai_summary" not in p_existing:
        cursor.execute("ALTER TABLE prospects ADD COLUMN ai_summary TEXT DEFAULT ''")

    count = cursor.execute("SELECT COUNT(*) AS total FROM clients").fetchone()["total"]

    if count == 0:
        cursor.executemany("""
        INSERT INTO clients (
            name, age, birthday, sex, marital, health,
            children, concern, personality, risk
        )
        VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
        """, [
            (
                "John Tan", "45", "1981-06-28", "Male", "Married",
                "Good", "2 children", "Retirement planning",
                "Analytical, risk-averse", "Medium"
            ),
            (
                "Mei Ling", "36", "1990-07-04", "Female", "Married",
                "Healthy", "1 child", "Education planning",
                "Family-oriented", "Low"
            ),
            (
                "Raj Kumar", "52", "1974-11-12", "Male", "Married",
                "Diabetes", "No", "Medical coverage",
                "Careful, compares options", "High"
            ),
        ])

        today = date.today().isoformat()
        cursor.executemany("""
        INSERT INTO events (client_id, date, time, purpose)
        VALUES (?, ?, ?, ?)
        """, [
            (1, today, "09:30", "Retirement review"),
            (2, today, "14:00", "Education fund discussion"),
        ])

    conn.commit()
    conn.close()


@app.on_event("startup")
def startup():
    init_db()


#####################################################
# Dashboard
#####################################################
# Generate the dashboard action card and whatsapp reminder
@app.get("/dashboard/messages")
def get_dashboard_messages():
    conn = get_conn()
    # Load all the client and scheduled events
    clients = conn.execute("SELECT * FROM clients").fetchall()
    events = conn.execute("""
        SELECT events.*, clients.name
        FROM events
        JOIN clients ON clients.id = events.client_id
    """).fetchall()

    today = date.today()

    messages = []

    for row in clients:
        # Enrich client with AI insights, relationship score, meeting history etc.
        client = enrich_client(conn, row)

        message_types = []
        # Birthday reminder if today is client's birthday
        birthday = client.get("birthday", "")
        if birthday:
            try:
                bday = datetime.strptime(birthday, "%d/%m/%Y")
                if bday.day == today.day and bday.month == today.month:
                    message_types.append("birthday")
            except:
                pass

        # Trigger re-engagement reminders for inactive clients
        days_since = client.get("days_since_last_meeting") or 0
        if days_since >= 180:
            message_types.append("long_silence")

        # Trigger renewal reminder when renewal is due soon
        renewal = client.get("renewal_date", "")
        if renewal:
            try:
                renew = datetime.strptime(renewal, "%Y-%m-%d").date()
                if (renew - today).days <= 7:
                    message_types.append("renewal_reminder")
            except:
                pass

        # Trigger meeting reminder if today is meeeting
        todays_event = None
        for e in events:
            if (
                e["client_id"] == client["id"]
                and e["date"] == today.isoformat()
            ):
                message_types.append("meeting_reminder")
                todays_event = dict(e)
                break

        # Create the action card if at least one trigger exists
        if message_types:
            messages.append({
                "client_id": client["id"],
                "client_name": client["name"],
                "phone": client.get("phone", ""),
                "message_types": message_types,
                "days_since_last_meeting": client.get("days_since_last_meeting"),
                "latest_meeting_date": client.get("latest_meeting_date"),
                "message": generate_smart_message(
                    client,
                    message_types,
                    todays_event,
                )
            })

    conn.close()
    return messages

# To mark dashbaord action as completed
@app.post("/completed-actions")
def complete_action(action: CompletedAction):
    conn = get_conn()

    conn.execute("""
    INSERT OR REPLACE INTO completed_actions (
        action_id, client_id, action_type, message, completed_at
    )
    VALUES (?, ?, ?, ?, CURRENT_TIMESTAMP)
    """, (
        action.action_id,
        action.client_id,
        action.action_type,
        action.message,
    ))

    conn.commit()
    conn.close()

    return {"message": "Action completed"}

# To unmark dashboard action as incomplete
@app.delete("/completed-actions/{action_id}")
def uncomplete_action(action_id: str):
    conn = get_conn()

    conn.execute(
        "DELETE FROM completed_actions WHERE action_id=?",
        (action_id,),
    )

    conn.commit()
    conn.close()

    return {"message": "Action uncompleted"}


# To get the completed actions
@app.get("/completed-actions")
def get_completed_actions():
    conn = get_conn()

    rows = conn.execute("""
    SELECT *
    FROM completed_actions
    """).fetchall()

    conn.close()
    return [dict(row) for row in rows]


# =========================
# HELPERS
# =========================

def parse_date(value):
    if not value:
        return None

    for fmt in ("%Y-%m-%d", "%d/%m/%Y", "%m/%d/%Y"):
        try:
            return datetime.strptime(value.strip(), fmt).date()
        except Exception:
            pass

    return None


def days_since(value):
    d = parse_date(value)
    if not d:
        return None
    return (date.today() - d).days


def days_until_birthday(value):
    b = parse_date(value)
    if not b:
        return None

    today = date.today()

    try:
        next_bday = b.replace(year=today.year)
    except ValueError:
        next_bday = b.replace(year=today.year, day=28)

    if next_bday < today:
        try:
            next_bday = next_bday.replace(year=today.year + 1)
        except ValueError:
            next_bday = next_bday.replace(year=today.year + 1, day=28)

    return (next_bday - today).days


def get_latest_meeting(conn, client_id):
    return conn.execute("""
        SELECT *
        FROM meeting_updates
        WHERE client_id=?
        ORDER BY meeting_date DESC, id DESC
        LIMIT 1
    """, (client_id,)).fetchone()


def compute_follow_up_date(meeting_date, interest_level):
    d = parse_date(meeting_date) or date.today()

    if interest_level == "Interested":
        days = 3
    elif interest_level == "Maybe":
        days = 7
    else:
        days = 30

    return (d + timedelta(days=days)).isoformat()


def has(text, words):
    return any(word in text for word in words)



def generate_smart_message(client, message_types, event=None):
    name = (client.get("name") or "there").strip()

    # Remove duplicates while keeping order
    message_types = list(dict.fromkeys(message_types))

    has_birthday = "birthday" in message_types
    has_meeting = "meeting_reminder" in message_types
    has_renewal = "renewal_reminder" in message_types
    has_long_silence = "long_silence" in message_types
    has_post_meeting = "post_meeting_followup" in message_types

    parts = []

    if has_birthday:
        parts.append(
            "wishing you a very happy birthday! 🎉 "
            "May the year ahead bring you good health, happiness and success."
        )

    if has_meeting:
        time = (event.get("time", "") if event else "").strip()
        purpose = (event.get("purpose", "") if event else "").strip()

        if purpose:
            meeting_text = f"just a friendly reminder that we have {purpose} scheduled today"
        else:
            meeting_text = "just a friendly reminder that we have a meeting scheduled today"

        if time:
            meeting_text += f" at {time}"

        meeting_text += "."

        parts.append(meeting_text)

    if has_post_meeting:
        concern = client.get("concern", "your financial planning")
        parts.append(
            f"thank you for meeting with me today. Based on our discussion regarding {concern.lower()}, "
            "I will prepare the relevant recommendations and follow up with you shortly."
        )

    if has_renewal:
        renewal_date = client.get("renewal_date", "")
        parts.append(
            f"your policy renewal is coming up"
            f"{' on ' + renewal_date if renewal_date else ''}. "
            "If you would like to review your coverage before renewal, feel free to let me know."
        )

    if has_long_silence:
        parts.append(
            "it has been some time since our last catch-up, so I wanted to check in "
            "to see if there have been any changes in your goals or circumstances."
        )

    if not parts:
        parts.append(
            "I hope you are doing well. Just checking in to see if there is anything I can assist you with."
        )

    # If multiple events happen together, combine naturally
    if len(parts) == 1:
        message_body = parts[0]
    else:
        message_body = parts[0] + " Also, " + " Also, ".join(parts[1:])

    message = f"Hi {name}, {message_body}"

    if has_meeting:
        message += " Looking forward to speaking with you."
    elif has_post_meeting:
        message += " Please let me know if any questions come to mind in the meantime."
    else:
        message += " Let me know if I can support you in any way."

    return message
# =========================
# GEMINI SETUP
# =========================

GEMINI_API_KEY = os.environ.get("GEMINI_API_KEY", "")
_GEMINI_MODEL = "gemini-2.0-flash"

_gemini_client = None

def get_gemini_client():
    global _gemini_client
    if not GEMINI_API_KEY:
        return None
    if _gemini_client is None:
        from google import genai
        _gemini_client = genai.Client(api_key=GEMINI_API_KEY)
    return _gemini_client


GEMINI_SYSTEM_PROMPT = """You are an AI assistant for a financial advisor.
Analyse the meeting notes provided and return ONLY a valid JSON object with exactly these fields:

{
  "summary": "2-3 sentence summary of the meeting",
  "sentiment": "Positive" or "Neutral" or "Concerned",
  "interest_level": "Interested" or "Maybe" or "Not interested",
  "risk": "High" or "Medium" or "Low",
  "concern": "comma-separated list of main financial concerns detected",
  "personality": "comma-separated list of personality traits detected",
  "follow_up": "semicolon-separated list of specific action items for the advisor",
  "suggested_policies": ["policy name 1", "policy name 2"],
  "memories": [
    {"memory_type": "financial_concern", "content": "what to remember about this client", "confidence": 90}
  ],
  "opportunities": [
    {"opportunity_type": "Retirement Planning", "reason": "why this is relevant", "confidence": 88, "suggested_action": "specific next step"}
  ],
  "follow_up_message": "a warm professional WhatsApp follow-up message to send to the client after the meeting"
}

Rules:
- memory_type must be one of: financial_concern, health_context, family_context, financial_preference, legacy_context, personality, relationship_context, general
- confidence is an integer 0-100
- Return ONLY the JSON object, no markdown, no explanation"""


def _parse_gemini_json(text: str) -> Optional[dict]:
    try:
        return json.loads(text)
    except Exception:
        pass
    match = _re.search(r"```(?:json)?\s*([\s\S]*?)```", text)
    if match:
        try:
            return json.loads(match.group(1).strip())
        except Exception:
            pass
    return None


def _fill_defaults(result: dict) -> dict:
    result.setdefault("summary", "")
    result.setdefault("sentiment", "Neutral")
    result.setdefault("interest_level", "Maybe")
    result.setdefault("risk", "Medium")
    result.setdefault("concern", "General financial planning")
    result.setdefault("personality", "Needs further discovery")
    result.setdefault("follow_up", "Schedule next discovery meeting")
    result.setdefault("suggested_policies", ["General life insurance review"])
    result.setdefault("memories", [])
    result.setdefault("opportunities", [])
    result.setdefault(
        "follow_up_message",
        "Hi, thank you for your time today. I will follow up with a suitable financial review plan.",
    )
    return result


def _gemini_err(e: Exception) -> str:
    err = str(e)
    if "429" in err or "quota" in err.lower() or "RESOURCE_EXHAUSTED" in err:
        import re
        m = re.search(r"retry after (\d+\s*\w+)", err, re.IGNORECASE)
        wait = m.group(1) if m else "a few minutes"
        return f"Gemini quota reached. Please wait {wait} and try again."
    return err


def analyze_with_gemini(text: str) -> dict:
    client = get_gemini_client()
    if client is None:
        return analyze_notes(text)
    try:
        from google.genai import types
        response = client.models.generate_content(
            model=_GEMINI_MODEL,
            contents=GEMINI_SYSTEM_PROMPT + "\n\nMeeting notes:\n" + text,
            config=types.GenerateContentConfig(temperature=0.1),
        )
        result = _parse_gemini_json(response.text)
        if result:
            return _fill_defaults(result)
    except Exception as e:
        print(f"[Gemini] text analysis error: {e} — falling back to keyword analysis")
    return analyze_notes(text)


def analyze_image_with_gemini(image_bytes: bytes, mime_type: str) -> dict:
    client = get_gemini_client()
    if client is None:
        return {"error": "Image analysis requires a Gemini API key. Set GEMINI_API_KEY and restart the server."}
    try:
        from google.genai import types
        image_part = types.Part.from_bytes(data=image_bytes, mime_type=mime_type or "image/jpeg")
        prompt = (
            "This is a handwritten or photographed advisor meeting note. "
            "First extract ALL visible text from the image exactly as written, "
            "then analyse it as meeting notes.\n\n"
            + GEMINI_SYSTEM_PROMPT
            + "\n\nReturn the JSON. Also include an extra field "
            "\"extracted_text\" with the raw text you read from the image."
        )
        response = client.models.generate_content(
            model=_GEMINI_MODEL,
            contents=[image_part, prompt],
            config=types.GenerateContentConfig(temperature=0.1),
        )
        result = _parse_gemini_json(response.text)
        if result:
            result.setdefault("extracted_text", "[Extracted from image]")
            return _fill_defaults(result)
        return {"error": "Gemini could not parse the image content."}
    except Exception as e:
        return {"error": _gemini_err(e)}


def _transcribe_audio(audio_bytes: bytes, mime_type: str) -> str:
    """
    Convert audio to WAV using bundled ffmpeg (direct subprocess, no pydub PATH issue),
    then transcribe with Google Web Speech API. No API key, no quota.
    """
    import tempfile, pathlib, subprocess, speech_recognition as sr
    import imageio_ffmpeg

    _ffmpeg = imageio_ffmpeg.get_ffmpeg_exe()

    _EXT_MAP = {
        "audio/mpeg": ".mp3", "audio/mp3": ".mp3",
        "audio/wav":  ".wav", "audio/x-wav": ".wav",
        "audio/m4a":  ".m4a", "audio/mp4":  ".m4a",
        "audio/webm": ".webm","audio/ogg":  ".ogg",
        "audio/aac":  ".aac", "audio/flac": ".flac",
    }
    ext = _EXT_MAP.get(mime_type, ".mp3")

    tmp_src = None
    tmp_wav = None
    try:
        with tempfile.NamedTemporaryFile(suffix=ext, delete=False) as f:
            f.write(audio_bytes)
            tmp_src = f.name

        tmp_wav = tmp_src + ".wav"

        # Call ffmpeg directly with full path — no PATH dependency, no pydub
        result = subprocess.run(
            [_ffmpeg, "-y", "-i", tmp_src, "-ar", "16000", "-ac", "1", "-f", "wav", tmp_wav],
            capture_output=True,
        )
        if result.returncode != 0:
            raise RuntimeError(result.stderr.decode(errors="ignore")[-500:])

        recognizer = sr.Recognizer()
        with sr.AudioFile(tmp_wav) as source:
            audio_data = recognizer.record(source)

        # Try Chinese first, fall back to English
        try:
            return recognizer.recognize_google(audio_data, language="zh-CN")
        except sr.UnknownValueError:
            return recognizer.recognize_google(audio_data, language="en-US")

    finally:
        for p in [tmp_src, tmp_wav]:
            if p:
                try:
                    pathlib.Path(p).unlink()
                except Exception:
                    pass


def analyze_audio_with_gemini(audio_bytes: bytes, mime_type: str) -> dict:
    """
    Transcribe audio locally (Google Web Speech, no API key, no quota),
    then analyse the transcript text with Gemini.
    """
    try:
        transcript = _transcribe_audio(audio_bytes, mime_type)
    except Exception as e:
        return {"error": f"Audio transcription failed: {e}"}

    if not transcript or not transcript.strip():
        return {"error": "Could not understand the audio. Please speak clearly or try a different recording."}

    # Now analyse the transcript as plain text — uses almost no Gemini quota
    result = analyze_with_gemini(transcript)
    result["extracted_text"] = transcript
    return result


_VOICE_EXTRACT_PROMPT = """You are a financial advisor's AI assistant. A customer sent a voice note. Extract their financial profile from the transcript below.

Return ONLY valid JSON (no markdown fences, no extra text):
{
  "name": "Full name if mentioned, else empty string",
  "age": "Age as string e.g. '20', else empty string",
  "marital": "Single/Married/Divorced/Widowed, else empty string",
  "children": "e.g. '2 children' or 'No children', else empty string",
  "income": "Monthly income e.g. 'RM4,000', else empty string",
  "health": "Excellent/Good/Managing a condition, else empty string",
  "goals": "Primary financial goal e.g. 'Education savings', else empty string",
  "risk": "Conservative/Balanced/Growth-oriented, else empty string",
  "confidence": 85,
  "opportunity": "Brief opportunity title e.g. 'Education Savings Opportunity'",
  "opportunity_reason": "One sentence explaining the opportunity",
  "ai_summary": "2-3 sentence paragraph about this prospect written for the financial advisor"
}

Set confidence 0-100 based on how complete and clear the information is.
Leave fields as empty string if not mentioned."""


def _extract_voice_profile(transcript: str, prospect: dict) -> dict:
    """Use Gemini to extract structured profile from a voice transcript, with rule-based fallback."""
    gemini = get_gemini_client()
    if gemini:
        try:
            from google.genai import types as _gt
            resp = gemini.models.generate_content(
                model=_GEMINI_MODEL,
                contents=f"{_VOICE_EXTRACT_PROMPT}\n\nTranscript:\n{transcript}",
                config=_gt.GenerateContentConfig(temperature=0.1),
            )
            raw = resp.text.strip()
            fenced = _re.search(r'```(?:json)?\s*([\s\S]*?)```', raw)
            if fenced:
                raw = fenced.group(1)
            json_m = _re.search(r'\{[\s\S]*\}', raw)
            if json_m:
                return json.loads(json_m.group())
        except Exception:
            pass

    # Rule-based fallback
    extracted = _extract_profile_fallback(transcript, prospect)
    filled = sum(1 for f in ["name", "age", "income", "marital", "children", "goals", "risk"] if extracted.get(f))
    confidence = min(95, max(30, filled * 14))
    return {**extracted, "confidence": confidence, "opportunity": "", "opportunity_reason": "", "ai_summary": ""}


# =========================
# AI ANALYSIS (keyword fallback)
# =========================

def analyze_notes(notes):
    text = (notes or "").lower()

    memories = []
    opportunities = []
    concerns = set()
    traits = set()
    policies = set()
    followups = set()

    sentiment = "Neutral"
    interest_level = "Maybe"
    risk = "Medium"

    if has(text, ["worried", "concern", "scared", "afraid", "stress", "anxious"]):
        sentiment = "Concerned"

    if has(text, ["happy", "positive", "comfortable", "confident", "trust"]):
        sentiment = "Positive"

    if has(text, ["interested", "keen", "agree", "proceed", "next step", "buy"]):
        interest_level = "Interested"

    if has(text, ["not interested", "reject", "decline", "too expensive", "no budget"]):
        interest_level = "Not interested"

    def add_memory(memory_type, content, confidence):
        memories.append({
            "memory_type": memory_type,
            "content": content,
            "confidence": confidence,
        })

    def add_opportunity(opportunity_type, reason, confidence, suggested_action):
        opportunities.append({
            "opportunity_type": opportunity_type,
            "reason": reason,
            "confidence": confidence,
            "suggested_action": suggested_action,
        })

    if has(text, ["retirement", "retire", "pension"]):
        concerns.add("Retirement planning")
        policies.add("Retirement income plan")
        followups.add("Prepare retirement cashflow projection")
        add_memory("financial_concern", "Client mentioned retirement planning concern.", 92)
        add_opportunity(
            "Retirement Planning",
            "Client discussed retirement or pension needs.",
            94,
            "Prepare retirement cashflow projection."
        )

    if has(text, ["medical", "hospital", "health", "illness", "surgery", "diabetes", "cancer"]):
        concerns.add("Healthcare cost protection")
        policies.add("Medical / critical illness plan")
        followups.add("Review medical coverage gap")
        add_memory("health_context", "Client mentioned health or medical-related concern.", 91)
        add_opportunity(
            "Medical / Critical Illness Coverage",
            "Health risk or medical cost was mentioned.",
            93,
            "Review medical and critical illness coverage gap."
        )

    if has(text, ["child", "children", "son", "daughter", "education", "school", "university"]):
        concerns.add("Children education planning")
        policies.add("Education savings plan")
        followups.add("Calculate education funding target")
        add_memory("family_context", "Client mentioned children or education responsibility.", 90)
        add_opportunity(
            "Education Planning",
            "Client has education-related financial responsibility.",
            91,
            "Calculate education funding target."
        )

    if has(text, ["investment", "return", "portfolio", "market"]):
        concerns.add("Investment planning")
        policies.add("Investment-linked policy")
        followups.add("Explain risk-return profile")
        add_memory("financial_preference", "Client discussed investment or portfolio interest.", 87)
        add_opportunity(
            "Investment Planning",
            "Client showed interest in investment growth.",
            88,
            "Explain risk-return options clearly."
        )

    if has(text, ["will", "estate", "legacy", "inheritance"]):
        concerns.add("Estate planning")
        policies.add("Estate planning solution")
        followups.add("Discuss beneficiary and estate goals")
        add_memory("legacy_context", "Client mentioned legacy or estate planning.", 89)
        add_opportunity(
            "Estate Planning",
            "Client discussed inheritance or legacy topic.",
            90,
            "Discuss beneficiary and estate goals."
        )

    if has(text, ["safe", "stable", "guaranteed", "conservative", "low risk"]):
        traits.add("Risk-averse")
        add_memory("personality", "Client appears risk-averse and prefers stability.", 86)

    if has(text, ["compare", "details", "research", "analyse", "analyze", "think first"]):
        traits.add("Analytical")
        add_memory("personality", "Client is analytical and needs detailed explanation.", 87)

    if has(text, ["family", "wife", "husband", "spouse", "parents", "children"]):
        traits.add("Family-oriented")
        add_memory("relationship_context", "Client values family context in financial decisions.", 84)

    if has(text, ["diabetes", "cancer", "stroke", "heart attack", "critical"]):
        risk = "High"

    if not concerns:
        concerns.add("General financial planning")

    if not traits:
        traits.add("Needs further discovery")

    if not policies:
        policies.add("General life insurance review")

    if not followups:
        followups.add("Schedule next discovery meeting")

    if not memories:
        add_memory("general", "Client meeting notes captured. More discovery required.", 60)

    if not opportunities:
        add_opportunity(
            "General Review",
            "No specific opportunity detected yet.",
            65,
            "Schedule discovery follow-up."
        )

    short_notes = " ".join((notes or "").split())
    if len(short_notes) > 180:
        short_notes = short_notes[:180] + "..."

    summary = (
        f"Client appeared {sentiment.lower()} with engagement level '{interest_level}'. "
        f"Detected opportunity areas: {', '.join(sorted(concerns))}. "
        f"Notes: {short_notes}"
    )

    follow_up_message = generate_follow_up_message(opportunities)

    return {
        "summary": summary,
        "sentiment": sentiment,
        "interest_level": interest_level,
        "risk": risk,
        "concern": ", ".join(sorted(concerns)),
        "personality": ", ".join(sorted(traits)),
        "follow_up": "; ".join(sorted(followups)),
        "suggested_policies": sorted(policies),
        "memories": memories,
        "opportunities": opportunities,
        "follow_up_message": follow_up_message,
    }


def generate_follow_up_message(opportunities):
    if not opportunities:
        return "Hi, thank you for your time today. I will follow up with a suitable financial review plan."

    top = opportunities[0]

    return (
        f"Hi, thank you for sharing with me today. Based on our discussion, "
        f"I think it would be useful for us to look deeper into {top['opportunity_type'].lower()}. "
        f"I’ll prepare some options and we can review them together in our next follow-up."
    )


def calculate_relationship_score(conn, client_id):
    updates = conn.execute("""
        SELECT meeting_date, interest_level, sentiment, follow_up_date
        FROM meeting_updates
        WHERE client_id=?
        ORDER BY meeting_date DESC, id DESC
    """, (client_id,)).fetchall()

    if not updates:
        return 40

    latest = updates[0]

    # 1. Recency: max 25
    d_ago = days_since(latest["meeting_date"])

    if d_ago is None:
        recency_score = 5
    elif d_ago <= 14:
        recency_score = 25
    elif d_ago <= 45:
        recency_score = 18
    elif d_ago <= 90:
        recency_score = 10
    else:
        recency_score = 3

    # 2. Meeting frequency: max 20
    frequency_score = min(len(updates) * 5, 20)

    # 3. Interest level: max 25
    interest_score = {
        "Interested": 25,
        "Maybe": 15,
        "Not interested": 5,
    }.get(latest["interest_level"], 15)

    # 4. Sentiment: max 15
    sentiment_score = {
        "Positive": 15,
        "Neutral": 10,
        "Concerned": 6,
    }.get(latest["sentiment"], 10)

    # 5. Follow-up discipline: max 15
    today = date.today().isoformat()
    follow_up_date = latest["follow_up_date"]

    if not follow_up_date:
        follow_up_score = 8
    elif follow_up_date >= today:
        follow_up_score = 15
    else:
        follow_up_score = 5

    total = (
        recency_score
        + frequency_score
        + interest_score
        + sentiment_score
        + follow_up_score
    )

    return max(0, min(100, total))


def calculate_health_score(conn, client_id):
    updates = conn.execute("""
        SELECT meeting_date, interest_level, sentiment
        FROM meeting_updates
        WHERE client_id=?
        ORDER BY meeting_date DESC, id DESC
    """, (client_id,)).fetchall()

    if not updates:
        return 45

    latest = updates[0]
    d_ago = days_since(latest["meeting_date"])

    if d_ago is None:
        recency = 10
    elif d_ago <= 14:
        recency = 35
    elif d_ago <= 45:
        recency = 25
    elif d_ago <= 90:
        recency = 15
    else:
        recency = 5

    interest_score = {
        "Interested": 35,
        "Maybe": 20,
        "Not interested": 5,
    }.get(latest["interest_level"], 20)

    sentiment_score = {
        "Positive": 15,
        "Neutral": 8,
        "Concerned": 5,
    }.get(latest["sentiment"], 8)

    frequency_score = min(len(updates) * 5, 15)

    return max(0, min(100, recency + interest_score + sentiment_score + frequency_score))


def suggest_policies(client):
    suggestions = []

    age_text = str(client.get("age") or "")
    age_digits = re.sub(r"[^0-9]", "", age_text)
    age = int(age_digits) if age_digits else None

    marital = str(client.get("marital") or "").lower()
    children = str(client.get("children") or "").lower()
    health = str(client.get("health") or "").lower()
    concern = str(client.get("concern") or "").lower()
    risk = str(client.get("risk") or "").lower()

    if children and children not in ["no", "none", "0", "n/a"]:
        suggestions.append("Education savings plan")

    if marital == "married":
        suggestions.append("Family protection plan")

    if age is not None and age >= 50:
        suggestions.append("Retirement income plan")

    if health and health not in ["good", "healthy", "none", "no", "n/a"]:
        suggestions.append("Medical / critical illness plan")

    if "retirement" in concern:
        suggestions.append("Retirement / pension plan")

    if "investment" in concern or "high" in risk:
        suggestions.append("Investment-linked policy")

    if not suggestions:
        suggestions.append("General life insurance review")

    return list(dict.fromkeys(suggestions))


def enrich_client(conn, row):
    client = dict(row)
    client["relationship_score"] = calculate_relationship_score(conn, client["id"])
    client["health_score"] = client["relationship_score"]
    client["suggested_policies"] = suggest_policies(client)
    client["birthday_in_days"] = days_until_birthday(client.get("birthday"))

    latest = get_latest_meeting(conn, client["id"])

    if latest:
        client["latest_summary"] = latest["summary"]
        client["latest_interest_level"] = latest["interest_level"]
        client["latest_sentiment"] = latest["sentiment"]
        client["recommended_action"] = latest["follow_up"]
        client["follow_up_message"] = latest["follow_up_message"]
    else:
        client["latest_summary"] = ""
        client["latest_interest_level"] = "No meeting yet"
        client["latest_sentiment"] = "No meeting yet"
        client["recommended_action"] = f"Follow up on {client.get('concern') or 'client goals'}"
        client["follow_up_message"] = ""

    memories = conn.execute("""
        SELECT memory_type, content, confidence, created_at
        FROM memories
        WHERE client_id=?
        ORDER BY id DESC
        LIMIT 8
    """, (client["id"],)).fetchall()

    opportunities = conn.execute("""
        SELECT opportunity_type, reason, confidence, suggested_action, created_at
        FROM opportunities
        WHERE client_id=?
        ORDER BY confidence DESC, id DESC
        LIMIT 5
    """, (client["id"],)).fetchall()

    client["memories"] = [dict(m) for m in memories]
    client["opportunities"] = [dict(o) for o in opportunities]

    return client


# =========================
# CLIENTS
# =========================

@app.post("/clients")
def add_client(client: Client):
    conn = get_conn()
    cursor = conn.cursor()

    cursor.execute("""
    INSERT INTO clients (
        name, age, birthday, sex, marital, health,
        children, concern, personality, risk
    )
    VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
    """, (
        client.name, client.age, client.birthday, client.sex, client.marital,
        client.health, client.children, client.concern, client.personality, client.risk,
    ))

    conn.commit()
    conn.close()

    return {"message": "Client added successfully"}


@app.get("/clients")
def get_clients():
    conn = get_conn()
    rows = conn.execute("SELECT * FROM clients ORDER BY name").fetchall()
    clients = [enrich_client(conn, row) for row in rows]
    conn.close()
    return clients


@app.get("/clients/{client_id}")
def get_client(client_id: int):
    conn = get_conn()

    row = conn.execute("SELECT * FROM clients WHERE id=?", (client_id,)).fetchone()

    if not row:
        conn.close()
        return {"error": "Client not found"}

    client = enrich_client(conn, row)

    history = conn.execute("""
        SELECT *
        FROM meeting_updates
        WHERE client_id=?
        ORDER BY meeting_date DESC, id DESC
    """, (client_id,)).fetchall()

    client["meeting_history"] = [dict(h) for h in history]

    conn.close()
    return client


@app.put("/clients/{client_id}")
def update_client(client_id: int, client: Client):
    conn = get_conn()

    conn.execute("""
    UPDATE clients
    SET name=?, phone=?, age=?, birthday=?, sex=?, marital=?, health=?,
        children=?, concern=?, personality=?, risk=?
    WHERE id=?
    """, (
        client.name, client.phone, client.age, client.birthday, client.sex, client.marital,
        client.health, client.children, client.concern, client.personality,
        client.risk, client_id,
    ))

    conn.commit()
    conn.close()

    return {"message": "Client updated successfully"}


# =========================
# EVENTS
# =========================

@app.post("/events")
def add_event(event: Event):
    conn = get_conn()

    conn.execute("""
    INSERT INTO events (client_id, date, time, purpose)
    VALUES (?, ?, ?, ?)
    """, (event.client_id, event.date, event.time, event.purpose))

    conn.commit()
    conn.close()

    return {"message": "Event added successfully"}


@app.get("/events")
def get_events():
    conn = get_conn()

    rows = conn.execute("""
    SELECT
        events.id,
        events.client_id,
        events.date,
        events.time,
        events.purpose,
        clients.name,
        clients.birthday,
        clients.concern,
        clients.personality,
        clients.risk
    FROM events
    JOIN clients ON events.client_id = clients.id
    ORDER BY events.date, events.time
    """).fetchall()

    events = [dict(row) for row in rows]

    conn.close()
    return events

@app.delete("/events/{event_id}")
def delete_event(event_id: int):
    conn = get_conn()

    conn.execute(
        "DELETE FROM events WHERE id=?",
        (event_id,)
    )

    conn.commit()
    conn.close()

    return {"message": "Event deleted successfully"}

# =========================
# AI COPILOT + MEMORY
# =========================

@app.post("/ai/copilot")
def ai_copilot(request: CopilotRequest):
    conn = get_conn()

    client = conn.execute(
        "SELECT * FROM clients WHERE id=?",
        (request.client_id,),
    ).fetchone()

    conn.close()

    if not client:
        return {"error": "Client not found"}

    return analyze_with_gemini(request.notes)


@app.post("/summarize")
def summarize(request: SummarizeRequest):
    return analyze_with_gemini(request.notes)


_IMAGE_EXTS = (".jpg", ".jpeg", ".png", ".webp", ".heic", ".bmp", ".gif")
_AUDIO_EXTS = (".mp3", ".wav", ".m4a", ".webm", ".ogg", ".aac", ".flac")


@app.post("/process-upload")
async def process_upload(
    client_id: int = Form(...),
    file: UploadFile = File(...),
):
    content_type = (file.content_type or "").lower()
    filename = (file.filename or "").lower()
    raw = await file.read()

    # IMAGE
    is_image = "image/" in content_type or any(filename.endswith(e) for e in _IMAGE_EXTS)
    if is_image:
        effective_mime = content_type if content_type.startswith("image/") else "image/jpeg"
        return analyze_image_with_gemini(raw, effective_mime)

    # AUDIO
    is_audio = "audio/" in content_type or any(filename.endswith(e) for e in _AUDIO_EXTS)
    if is_audio:
        effective_mime = content_type if content_type.startswith("audio/") else "audio/mp3"
        return analyze_audio_with_gemini(raw, effective_mime)

    # PDF
    if "pdf" in content_type or filename.endswith(".pdf"):
        try:
            from pypdf import PdfReader
            reader = PdfReader(io.BytesIO(raw))
            text = "".join((page.extract_text() or "") + "\n" for page in reader.pages)
        except Exception as e:
            return {"error": f"Could not read PDF: {e}"}
        text = text.strip()
        if not text:
            return {"error": "No text could be extracted from this PDF."}
        result = analyze_with_gemini(text)
        result["extracted_text"] = text
        return result

    # Plain text / markdown
    text = raw.decode("utf-8", errors="ignore").strip()
    if not text:
        return {"error": "No text could be extracted from the uploaded file."}
    result = analyze_with_gemini(text)
    result["extracted_text"] = text
    return result


@app.post("/meeting-updates")
def save_meeting_update(update: MeetingUpdate):
    conn = get_conn()

    client = conn.execute(
        "SELECT * FROM clients WHERE id=?",
        (update.client_id,),
    ).fetchone()

    if not client:
        conn.close()
        return {"error": "Client not found"}

    analysis = analyze_with_gemini(update.notes)

    concern = update.concern or analysis["concern"]
    personality = update.personality or analysis["personality"]
    risk = update.risk or analysis["risk"]
    health = update.health or client["health"]
    children = update.children or client["children"]
    follow_up = update.follow_up or analysis["follow_up"]
    interest_level = update.interest_level or analysis["interest_level"]
    follow_up_date = compute_follow_up_date(update.meeting_date, interest_level)

    cursor = conn.cursor()

    for memory in analysis["memories"]:
        cursor.execute("""
        INSERT INTO memories (client_id, memory_type, content, confidence)
        VALUES (?, ?, ?, ?)
        """, (
            update.client_id,
            memory["memory_type"],
            memory["content"],
            memory["confidence"],
        ))

    for opportunity in analysis["opportunities"]:
        cursor.execute("""
        INSERT INTO opportunities (
            client_id, opportunity_type, reason, confidence, suggested_action
        )
        VALUES (?, ?, ?, ?, ?)
        """, (
            update.client_id,
            opportunity["opportunity_type"],
            opportunity["reason"],
            opportunity["confidence"],
            opportunity["suggested_action"],
        ))

    cursor.execute("""
    INSERT INTO meeting_updates (
        client_id, title, meeting_date, notes, summary, sentiment,
        concern, personality, risk, health, children,
        follow_up, follow_up_date, interest_level,
        relationship_score, follow_up_message
    )
    VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
    """, (
        update.client_id,
        update.title,
        update.meeting_date,
        update.notes,
        analysis["summary"],
        analysis["sentiment"],
        concern,
        personality,
        risk,
        health,
        children,
        follow_up,
        follow_up_date,
        interest_level,
        0,
        analysis["follow_up_message"],
    ))

    conn.execute("""
    UPDATE clients
    SET concern=?, personality=?, risk=?, health=?, children=?
    WHERE id=?
    """, (
        concern,
        personality,
        risk,
        health,
        children,
        update.client_id,
    ))

    conn.commit()

    health_score = calculate_health_score(conn, update.client_id)

    conn.execute("""
    UPDATE meeting_updates
    SET relationship_score=?
    WHERE id=(
        SELECT id FROM meeting_updates
        WHERE client_id=?
        ORDER BY id DESC
        LIMIT 1
    )
    """, (health_score, update.client_id))

    conn.commit()
    conn.close()

    return {
        "message": "Meeting update saved and AI memory updated",
        "summary": analysis["summary"],
        "sentiment": analysis["sentiment"],
        "interest_level": interest_level,
        "follow_up": follow_up,
        "follow_up_date": follow_up_date,
        "relationship_score": health_score,
        "health_score": health_score,
        "suggested_policies": analysis["suggested_policies"],
        "memories": analysis["memories"],
        "opportunities": analysis["opportunities"],
        "follow_up_message": analysis["follow_up_message"],
    }


@app.get("/meeting-updates/{client_id}")
def get_meeting_updates(client_id: int):
    conn = get_conn()

    rows = conn.execute("""
        SELECT *
        FROM meeting_updates
        WHERE client_id=?
        ORDER BY meeting_date DESC, id DESC
    """, (client_id,)).fetchall()

    conn.close()
    return [dict(row) for row in rows]


@app.get("/ai/memory/{client_id}")
def ai_memory(client_id: int):
    conn = get_conn()

    row = conn.execute("SELECT * FROM clients WHERE id=?", (client_id,)).fetchone()

    if not row:
        conn.close()
        return {"error": "Client not found"}

    client = enrich_client(conn, row)

    conn.close()
    return client


@app.get("/ai/opportunities/{client_id}")
def ai_opportunities(client_id: int):
    conn = get_conn()

    rows = conn.execute("""
    SELECT *
    FROM opportunities
    WHERE client_id=?
    ORDER BY confidence DESC, id DESC
    """, (client_id,)).fetchall()

    conn.close()
    return [dict(row) for row in rows]


@app.get("/ai/relationship-health")
def relationship_health():
    conn = get_conn()

    rows = conn.execute("SELECT * FROM clients ORDER BY name").fetchall()

    result = []

    for row in rows:
        client = enrich_client(conn, row)
        score = client["relationship_score"]

        if score >= 80:
            status = "Strong"
        elif score >= 55:
            status = "Warm"
        else:
            status = "At Risk"

        result.append({
            "client_id": client["id"],
            "name": client["name"],
            "score": score,
            "status": status,
            "latest_sentiment": client["latest_sentiment"],
            "latest_interest_level": client["latest_interest_level"],
            "recommended_action": client["recommended_action"],
        })

    conn.close()
    return result


# =========================
# AI BRIEFING
# =========================

@app.get("/ai/briefing")
def ai_briefing():
    today = date.today().isoformat()
    conn = get_conn()

    rows = conn.execute("""
    SELECT
        events.id AS event_id,
        events.client_id,
        events.date,
        events.time,
        events.purpose,
        clients.*
    FROM events
    JOIN clients ON clients.id = events.client_id
    WHERE events.date=?
    ORDER BY events.time
    """, (today,)).fetchall()

    clients = []

    for row in rows:
        client = enrich_client(conn, row)
        opportunities = client["opportunities"]

        if opportunities:
            top = opportunities[0]
            opening = (
                f"Open with: 'Last time you mentioned "
                f"{top['opportunity_type'].lower()}. Would you like to review that today?'"
            )
            top_opportunity = top["opportunity_type"]
            action = top["suggested_action"]
        else:
            opening = "Open by checking in and asking what has changed since the last meeting."
            top_opportunity = "Discovery"
            action = "Ask discovery questions."

        clients.append({
            "client_id": row["client_id"],
            "name": row["name"],
            "time": row["time"],
            "purpose": row["purpose"],
            "relationship_score": client["relationship_score"],
            "latest_summary": client["latest_summary"],
            "opening_suggestion": opening,
            "top_opportunity": top_opportunity,
            "recommended_action": action,
            "suggested_policies": client["suggested_policies"],
            "birthday_in_days": client["birthday_in_days"],
        })

    conn.close()

    return {
        "date": today,
        "meeting_count": len(clients),
        "clients": clients,
    }


# Old briefing compatability endpoint for legacy frontend

@app.get("/briefing/summary")
def briefing_summary():
    today = date.today().isoformat()
    conn = get_conn()

    meetings_today = conn.execute(
        "SELECT COUNT(*) AS total FROM events WHERE date=?",
        (today,),
    ).fetchone()["total"]

    all_clients = conn.execute("SELECT * FROM clients").fetchall()

    follow_ups_due = 0
    birthdays_this_week = 0

    for client in all_clients:
        birthday_days = days_until_birthday(client["birthday"])

        if birthday_days is not None and birthday_days <= 7:
            birthdays_this_week += 1

        latest = get_latest_meeting(conn, client["id"])

        if latest and latest["follow_up_date"] and latest["follow_up_date"] <= today:
            follow_ups_due += 1

    conn.close()

    return {
        "date": today,
        "meetings_today": meetings_today,
        "follow_ups_due": follow_ups_due,
        "birthdays_this_week": birthdays_this_week,
    }


@app.get("/briefing/clients")
def briefing_clients():
    briefing = ai_briefing()
    return briefing["clients"]


# =========================
# EXPENSES
# =========================

@app.get("/expenses/categories")
def get_expense_categories():
    return EXPENSE_CATEGORIES


@app.post("/expenses")
def add_expense(expense: Expense):
    conn = get_conn()

    conn.execute("""
    INSERT INTO expenses (
        category, description, amount, expense_date, client_id
    )
    VALUES (?, ?, ?, ?, ?)
    """, (
        expense.category,
        expense.description,
        expense.amount,
        expense.expense_date,
        expense.client_id,
    ))

    conn.commit()
    conn.close()

    return {"message": "Expense added successfully"}


@app.get("/expenses")
def get_expenses():
    conn = get_conn()

    rows = conn.execute("""
    SELECT
        expenses.*,
        clients.name AS client_name
    FROM expenses
    LEFT JOIN clients ON clients.id = expenses.client_id
    ORDER BY expenses.expense_date DESC, expenses.id DESC
    """).fetchall()

    conn.close()
    return [dict(row) for row in rows]


@app.get("/expenses/summary")
def expenses_summary():
    conn = get_conn()

    rows = conn.execute("""
    SELECT category, SUM(amount) AS total, COUNT(*) AS count
    FROM expenses
    GROUP BY category
    """).fetchall()

    summary = {
        category: {"total": 0, "count": 0}
        for category in EXPENSE_CATEGORIES
    }

    for row in rows:
        summary[row["category"]] = {
            "total": row["total"] or 0,
            "count": row["count"] or 0,
        }

    grand_total = sum(item["total"] for item in summary.values())

    conn.close()

    return {
        "grand_total": grand_total,
        "by_category": summary,
    }


# =========================
# REFERRALS
# =========================

@app.post("/referrals")
def add_referral(referral: Referral):
    conn = get_conn()

    conn.execute("""
    INSERT INTO referrals (
        client_id, client_name, partner_name, partner_type,
        direction, status, notes
    )
    VALUES (?, ?, ?, ?, ?, ?, ?)
    """, (
        referral.client_id,
        referral.client_name,
        referral.partner_name,
        referral.partner_type,
        referral.direction,
        referral.status,
        referral.notes,
    ))

    conn.commit()
    conn.close()

    return {"message": "Referral added successfully"}


@app.get("/referrals")
def get_referrals():
    conn = get_conn()

    rows = conn.execute("""
    SELECT
        referrals.*,
        clients.name AS linked_client_name
    FROM referrals
    LEFT JOIN clients ON clients.id = referrals.client_id
    ORDER BY referrals.id DESC
    """).fetchall()

    conn.close()
    return [dict(row) for row in rows]


@app.put("/referrals/{referral_id}")
def update_referral_status(referral_id: int, update: ReferralStatusUpdate):
    conn = get_conn()

    conn.execute("""
    UPDATE referrals
    SET status=?
    WHERE id=?
    """, (update.status, referral_id))

    conn.commit()
    conn.close()

    return {"message": "Referral updated successfully"}


@app.get("/referrals/summary")
def referrals_summary():
    conn = get_conn()

    rows = conn.execute("""
    SELECT
        partner_name,
        partner_type,
        COUNT(*) AS total,
        SUM(CASE WHEN status='Closed-Won' THEN 1 ELSE 0 END) AS closed_won
    FROM referrals
    GROUP BY partner_name, partner_type
    ORDER BY total DESC
    """).fetchall()

    result = []

    for row in rows:
        total = row["total"] or 0
        closed_won = row["closed_won"] or 0

        result.append({
            "partner_name": row["partner_name"],
            "partner_type": row["partner_type"],
            "total": total,
            "closed_won": closed_won,
            "conversion_rate": round((closed_won / total) * 100, 1) if total else 0,
        })

    conn.close()
    return result



# ─── Financial Coverage Analysis ─────────────────────────────────────────────

_COVERAGE_PROMPT = """You are a financial advisor assistant. Analyze the client profile and meeting notes below.
Determine if the advisor has COVERED each of these 4 financial planning categories with this client.
A category is "covered" if there is evidence it has been discussed, a policy exists, or action has been taken.

Categories:
1. cashflow_management - budgeting, income, expenses, debt, emergency fund, cash flow analysis
2. savings_investment - savings plans, unit trust, stocks, bonds, EPF/KWSP top-up, investment portfolio
3. retirement_planning - retirement age target, retirement fund, pension, passive income plan
4. estate_planning - will, nomination, trust, beneficiary, asset distribution

Respond ONLY with valid JSON in this exact format:
{
  "cashflow_management": {"covered": true, "note": "one sentence why"},
  "savings_investment": {"covered": false, "note": "one sentence why"},
  "retirement_planning": {"covered": false, "note": "one sentence why"},
  "estate_planning": {"covered": false, "note": "one sentence why"},
  "priority_actions": ["action 1", "action 2", "action 3"]
}"""


@app.get("/clients/{client_id}/coverage")
def get_coverage(client_id: int):
    conn = get_conn()
    client = conn.execute("SELECT * FROM clients WHERE id=?", (client_id,)).fetchone()
    if not client:
        conn.close()
        raise HTTPException(status_code=404, detail="Client not found")
    client = dict(client)

    meetings = conn.execute(
        "SELECT title, meeting_date, summary, notes FROM meeting_updates WHERE client_id=? ORDER BY meeting_date DESC LIMIT 5",
        (client_id,)
    ).fetchall()
    meetings = [dict(m) for m in meetings]
    conn.close()

    context = (
        f"Client: {client['name']}, Age {client.get('age','')}, "
        f"{client.get('sex','')}, {client.get('marital','')}\n"
        f"Concern: {client.get('concern','')}\n"
        f"Health: {client.get('health','')}\n"
        f"Risk level: {client.get('risk','')}\n"
        f"Children: {client.get('children','')}\n"
    )
    for m in meetings:
        context += (
            f"\nMeeting ({m['meeting_date']}): {m['title']}\n"
            f"Summary: {m['summary']}\n"
            f"Notes: {(m['notes'] or '')[:500]}\n"
        )

    gemini = get_gemini_client()
    if gemini:
        try:
            from google.genai import types
            resp = gemini.models.generate_content(
                model=_GEMINI_MODEL,
                contents=_COVERAGE_PROMPT + "\n\nClient Data:\n" + context,
                config=types.GenerateContentConfig(temperature=0.1),
            )
            raw = resp.text.strip()
            if raw.startswith("```"):
                raw = raw.split("```")[1]
                if raw.startswith("json"):
                    raw = raw[4:]
            return json.loads(raw.strip())
        except Exception:
            pass

    all_text = context.lower()
    def kw(words):
        return any(w in all_text for w in words)
    return {
        "cashflow_management": {"covered": kw(["cash","budget","expense","income","debt","emergency"]), "note": "Based on keyword scan of meeting notes."},
        "savings_investment": {"covered": kw(["saving","invest","unit trust","epf","kwsp","portfolio","stock"]), "note": "Based on keyword scan of meeting notes."},
        "retirement_planning": {"covered": kw(["retire","pension","passive income"]), "note": "Based on keyword scan of meeting notes."},
        "estate_planning": {"covered": kw(["will","trust","nomination","beneficiary","estate"]), "note": "Based on keyword scan of meeting notes."},
        "priority_actions": ["Review uncovered categories with client", "Schedule follow-up meeting", "Prepare product proposals for gaps"],
    }


def _table_exists(conn, table_name: str) -> bool:
    return conn.execute(
        "SELECT name FROM sqlite_master WHERE type='table' AND name=?", (table_name,)
    ).fetchone() is not None


# ─── Client PDF Report ────────────────────────────────────────────────────────

@app.get("/clients/{client_id}/report-pdf")
def get_client_report_pdf(client_id: int):
    from fastapi.responses import Response
    from fpdf import FPDF
    from datetime import date as _date

    conn = get_conn()
    client = conn.execute("SELECT * FROM clients WHERE id=?", (client_id,)).fetchone()
    if not client:
        conn.close()
        raise HTTPException(status_code=404, detail="Client not found")
    client = dict(client)

    meetings = conn.execute(
        "SELECT title, meeting_date, summary FROM meeting_updates WHERE client_id=? ORDER BY meeting_date DESC LIMIT 3",
        (client_id,)
    ).fetchall()
    meetings = [dict(m) for m in meetings]

    opps = []
    if _table_exists(conn, "opportunities"):
        opps = [dict(o) for o in conn.execute(
            "SELECT opportunity_type, reason, suggested_action FROM opportunities WHERE client_id=? ORDER BY id DESC LIMIT 3",
            (client_id,)
        ).fetchall()]

    conn.close()

    try:
        import requests as _req
        cov_resp = _req.get(f"http://localhost:8000/clients/{client_id}/coverage", timeout=20)
        coverage = cov_resp.json() if cov_resp.status_code == 200 else {}
    except Exception:
        coverage = {}

    def _latin(text: str) -> str:
        return (text or "").replace("—", "-").replace("–", "-").replace(
            "‘", "'").replace("’", "'").replace(
            "“", '"').replace("”", '"').replace(
            "•", "-").replace("…", "...").encode(
            "latin-1", errors="replace").decode("latin-1")

    def safe_write(pdf, line_h, text, max_chars=90):
        text = _latin((text or "").replace("\r", "").strip())
        for para in text.split("\n"):
            para = para.strip()
            while len(para) > max_chars:
                pdf.cell(0, line_h, para[:max_chars], ln=True)
                para = para[max_chars:]
            pdf.cell(0, line_h, para, ln=True)

    pdf = FPDF()
    pdf.add_page()
    pdf.set_margins(15, 15, 15)

    # Header bar
    pdf.set_fill_color(79, 70, 229)
    pdf.rect(0, 0, 210, 28, "F")
    pdf.set_font("Helvetica", "B", 18)
    pdf.set_text_color(255, 255, 255)
    pdf.set_y(8)
    pdf.cell(0, 10, "Client Financial Profile Report", align="C", ln=True)
    pdf.set_font("Helvetica", "", 10)
    pdf.cell(0, 6, f"Generated: {_date.today().strftime('%d %B %Y')}", align="C", ln=True)
    pdf.set_text_color(0, 0, 0)
    pdf.ln(8)

    # Client name
    pdf.set_font("Helvetica", "B", 14)
    pdf.cell(0, 8, _latin(client["name"]), ln=True)
    pdf.set_font("Helvetica", "", 10)

    info = [
        ("Age", client.get("age", "N/A")),
        ("Gender", client.get("sex", "N/A")),
        ("Marital Status", client.get("marital", "N/A")),
        ("Birthday", client.get("birthday", "N/A")),
        ("Health", client.get("health", "N/A")),
        ("Children", client.get("children", "N/A")),
        ("Risk Level", client.get("risk", "N/A")),
        ("Relationship Score", str(client.get("relationship_score", "N/A"))),
    ]
    for i in range(0, len(info), 2):
        pdf.cell(90, 7, _latin(f"{info[i][0]}: {info[i][1]}"))
        if i + 1 < len(info):
            pdf.cell(0, 7, _latin(f"{info[i+1][0]}: {info[i+1][1]}"), ln=True)
        else:
            pdf.ln()

    if client.get("concern"):
        pdf.ln(2)
        pdf.set_font("Helvetica", "B", 10)
        pdf.cell(0, 7, "Major Concern:", ln=True)
        pdf.set_font("Helvetica", "", 10)
        safe_write(pdf, 6, client["concern"])

    pdf.ln(5)

    # Coverage table
    pdf.set_font("Helvetica", "B", 12)
    pdf.set_fill_color(243, 244, 246)
    pdf.cell(0, 8, "Financial Planning Coverage", ln=True, fill=True)
    pdf.ln(2)

    cats = [
        ("cashflow_management", "Cashflow Management"),
        ("savings_investment", "Savings & Investment Management"),
        ("retirement_planning", "Retirement Planning"),
        ("estate_planning", "Estate Planning"),
    ]

    # Table header
    pdf.set_font("Helvetica", "B", 9)
    pdf.set_fill_color(79, 70, 229)
    pdf.set_text_color(255, 255, 255)
    pdf.cell(75, 7, "Category", border=1, fill=True)
    pdf.cell(28, 7, "Status", border=1, fill=True)
    pdf.cell(0, 7, "Note", border=1, fill=True, ln=True)
    pdf.set_text_color(0, 0, 0)
    pdf.set_font("Helvetica", "", 9)

    for key, label in cats:
        cat_data = coverage.get(key, {})
        is_covered = cat_data.get("covered", False)
        note = _latin((cat_data.get("note") or "-")[:65])
        status_text = "Covered" if is_covered else "Not Covered"
        pdf.cell(75, 7, label, border=1)
        if is_covered:
            pdf.set_fill_color(220, 252, 231)
        else:
            pdf.set_fill_color(254, 226, 226)
        pdf.cell(28, 7, status_text, border=1, fill=True)
        pdf.set_fill_color(255, 255, 255)
        pdf.cell(0, 7, note, border=1, ln=True)

    if coverage.get("priority_actions"):
        pdf.ln(3)
        pdf.set_font("Helvetica", "B", 10)
        pdf.cell(0, 7, "Priority Actions for Advisor:", ln=True)
        pdf.set_font("Helvetica", "", 9)
        for action in coverage["priority_actions"]:
            pdf.cell(5)
            pdf.cell(0, 6, _latin(f"- {action}"), ln=True)

    # AI Opportunities
    if opps:
        pdf.ln(5)
        pdf.set_font("Helvetica", "B", 12)
        pdf.set_fill_color(243, 244, 246)
        pdf.cell(0, 8, "AI-Detected Opportunities", ln=True, fill=True)
        pdf.ln(2)
        for o in opps:
            pdf.set_font("Helvetica", "B", 9)
            pdf.cell(0, 6, _latin(o.get("opportunity_type", "")), ln=True)
            pdf.set_font("Helvetica", "", 9)
            safe_write(pdf, 5, f"Reason: {o.get('reason','')}")
            safe_write(pdf, 5, f"Action: {o.get('suggested_action','')}")
            pdf.ln(2)

    # Recent meetings
    if meetings:
        pdf.ln(2)
        pdf.set_font("Helvetica", "B", 12)
        pdf.set_fill_color(243, 244, 246)
        pdf.cell(0, 8, "Recent Meeting Summaries", ln=True, fill=True)
        pdf.ln(2)
        for m in meetings:
            pdf.set_font("Helvetica", "B", 9)
            pdf.cell(0, 6, _latin(f"{m.get('title','Untitled')}  |  {m.get('meeting_date','')}"), ln=True)
            pdf.set_font("Helvetica", "", 9)
            summary = (m.get("summary") or "No summary.")[:500]
            safe_write(pdf, 5, summary)
            pdf.ln(2)

    # Footer
    pdf.set_y(-18)
    pdf.set_font("Helvetica", "I", 8)
    pdf.set_text_color(150, 150, 150)
    pdf.cell(0, 6, "Confidential - Generated by Advisor AI", align="C")

    pdf_bytes = bytes(pdf.output())
    return Response(
        content=pdf_bytes,
        media_type="application/pdf",
        headers={"Content-Disposition": f"attachment; filename={client['name'].replace(' ','_')}_report.pdf"},
    )


# ═══════════════════════════════════════════════════════════════════════════════
# AI ADVISOR CLONE  —  Customer Self-Service Chat
# ═══════════════════════════════════════════════════════════════════════════════

class ChatMsgRequest(BaseModel):
    message: str
    language: Optional[str] = None  # "English" | "Malay" | "Chinese"


class BookMeetingRequest(BaseModel):
    slot: Optional[str] = None
    action: str = "book"  # book | callback | later | decline


# ── Product catalogue (rule-based, zero paid API) ──────────────────────────────

_PRODUCTS = [
    # ── RETIREMENT ────────────────────────────────────────────────────────────
    {"id": "retirement", "name": "Retirement Savings Plan", "emoji": "🌅",
     "category": "Retirement",
     "keywords": ["retire", "retirement", "pension", "passive income", "old age", "future", "65", "60"],
     "description": "Builds a sustainable income stream for your retirement years.",
     "detail": "Provides guaranteed monthly payouts post-retirement with capital protection and loyalty bonuses. Best started before age 50 to maximise compound growth.",
     "age_min": 20, "age_max": 60},

    # ── CASHFLOW ──────────────────────────────────────────────────────────────
    {"id": "family_protection", "name": "Family Protection Plan", "emoji": "🛡️",
     "category": "Cashflow",
     "keywords": ["family", "protection", "life", "dependent", "income", "replace", "spouse", "wife", "husband", "breadwinner"],
     "description": "Replaces lost income and protects your family's cashflow.",
     "detail": "Covers income replacement if you are unable to work due to illness, accident, or death. Ensures your family maintains their lifestyle without financial strain.",
     "age_min": 18, "age_max": 65},

    {"id": "medical", "name": "Medical & Critical Illness Plan", "emoji": "🏥",
     "category": "Cashflow",
     "keywords": ["medical", "health", "hospital", "illness", "sick", "cancer", "surgery", "treatment", "managing"],
     "description": "Covers medical bills so health emergencies never disrupt your cashflow.",
     "detail": "Covers hospitalisation, surgery, and 36 critical illnesses. Cashless admission at panel hospitals. Prevents medical costs from wiping out savings.",
     "age_min": 18, "age_max": 65},

    # ── SAVINGS & INVESTMENT ──────────────────────────────────────────────────
    {"id": "education_savings", "name": "Education Savings Plan", "emoji": "🎓",
     "category": "Savings & Investment",
     "keywords": ["education", "school", "university", "study", "children", "child", "kids", "tuition", "future"],
     "description": "Grows savings specifically for your children's future education.",
     "detail": "Guaranteed maturity value with bonus allocation. Flexible premium payment. Designed for parents with children aged 0–18. Funds earmarked for university fees.",
     "age_min": 18, "age_max": 55},

    {"id": "investment", "name": "Investment Growth Plan", "emoji": "📈",
     "category": "Savings & Investment",
     "keywords": ["invest", "grow", "wealth", "return", "profit", "savings", "growth", "fund", "stocks", "unit trust"],
     "description": "Maximises wealth through diversified investment strategies.",
     "detail": "Unit-linked investment plan targeting 5–8% annual returns. Suits balanced to growth-oriented investors. Mix of equities, bonds, and REITs for diversification.",
     "age_min": 21, "age_max": 60},

    # ── ESTATE ────────────────────────────────────────────────────────────────
    {"id": "legacy", "name": "Legacy & Estate Plan", "emoji": "🏛️",
     "category": "Estate",
     "keywords": ["legacy", "estate", "inheritance", "will", "trust", "asset", "wealth transfer", "property"],
     "description": "Ensures your assets are distributed according to your wishes.",
     "detail": "Combines life coverage with estate planning tools to avoid probate delays. Guarantees seamless wealth transfer to beneficiaries with minimal legal complications.",
     "age_min": 30, "age_max": 70},

    {"id": "takaful", "name": "Takaful Legacy Plan", "emoji": "🌙",
     "category": "Estate",
     "keywords": ["takaful", "islamic", "syariah", "muslim", "halal", "legacy", "hibah", "faraidh"],
     "description": "Shariah-compliant wealth distribution and legacy protection.",
     "detail": "Life protection with hibah (gift) distribution ensuring smooth asset transfer per Islamic principles. Covers faraid compliance and waqf options.",
     "age_min": 18, "age_max": 65},
]


def _score_products(prospect: dict) -> list:
    text = " ".join([
        str(prospect.get("goals", "")),
        str(prospect.get("concern", "")),
        str(prospect.get("health", "")),
        str(prospect.get("conversation_summary", "")),
        str(prospect.get("risk", "")),
    ]).lower()

    try:
        age = int(str(prospect.get("age", 0) or 0))
    except Exception:
        age = 30

    marital = str(prospect.get("marital", "")).lower()
    has_children = bool(prospect.get("children") and prospect["children"].lower() not in ("no children", "none", "0"))
    is_islamic = any(w in text for w in ["takaful", "halal", "muslim", "islam", "syariah", "hibah"])
    health = str(prospect.get("health", "")).lower()
    risk = str(prospect.get("risk", "")).lower()

    results = []
    for p in _PRODUCTS:
        # Skip products outside the prospect's age range
        age_min = p.get("age_min", 18)
        age_max = p.get("age_max", 70)
        if age and not (age_min <= age <= age_max):
            continue

        score = sum(10 for kw in p["keywords"] if kw in text)
        why_parts = []

        pid = p["id"]

        # Education savings
        if pid == "education_savings":
            if has_children:
                score += 45
                why_parts.append(f"You have children — securing their education fund is a priority")
            if age <= 40:
                score += 10
                why_parts.append(f"Starting at age {age} gives maximum time for the fund to grow")

        # Family protection / cashflow
        if pid == "family_protection":
            if marital == "married":
                score += 30
                why_parts.append("As a married individual your family depends on your income")
            if has_children:
                score += 20
                why_parts.append("Your children need income protection if anything happens to you")

        # Medical
        if pid == "medical":
            score += 15  # Everyone needs medical cover
            if "managing" in health or "condition" in health:
                score += 25
                why_parts.append("Your current health condition makes comprehensive medical cover essential")
            elif age >= 40:
                score += 10
                why_parts.append(f"At {age}, medical cover becomes increasingly important")
            if not why_parts:
                why_parts.append("Medical emergencies can deplete savings — this protects your cashflow")

        # Retirement
        if pid == "retirement":
            if age >= 40:
                score += 30
                why_parts.append(f"At {age}, building retirement income now is critical")
            elif age >= 30:
                score += 20
                why_parts.append(f"Starting at {age} gives your fund 30+ years of compound growth")
            if "retirement" in text:
                score += 25
                why_parts.append("Retirement is one of your stated financial goals")

        # Investment growth
        if pid == "investment":
            if "growth" in risk or "balanced" in risk or "invest" in text:
                score += 20
                why_parts.append("Matches your risk appetite and wealth-building goals")
            if age <= 45:
                score += 15
                why_parts.append(f"At {age} you have time to ride market cycles for strong returns")

        # Legacy & estate
        if pid == "legacy":
            if age >= 35:
                score += 20
                why_parts.append("Estate planning ensures your assets reach your intended beneficiaries")
            if marital == "married" or has_children:
                score += 15
                why_parts.append("With a family, having a clear succession plan is essential")

        # Takaful — only surface if relevant
        if pid == "takaful":
            if not is_islamic:
                continue
            score += 50
            why_parts.append("Shariah-compliant plan aligns with your Islamic finance preferences")

        if score > 0:
            why_text = ". ".join(why_parts) if why_parts else p["description"]
            results.append({**p, "match_pct": min(98, 50 + score), "why": why_text})

    results.sort(key=lambda x: x["match_pct"], reverse=True)
    return results[:4]  # Up to 4 recommendations across all categories


def _calc_interest_score(prospect: dict, msg_count: int) -> int:
    fields = ["name", "age", "income", "marital", "children", "goals", "risk"]
    filled = sum(1 for f in fields if prospect.get(f, ""))
    profile_score = int((filled / len(fields)) * 40)
    engagement_score = min(30, msg_count * 3)
    meeting_bonus = 30 if prospect.get("meeting_request") else 0
    return min(99, profile_score + engagement_score + meeting_bonus)


# ── Gemini-powered conversation engine ────────────────────────────────────────
_CLONE_SYSTEM = """You are an AI assistant for a professional financial advisor. You are warm, friendly and conversational.

Your goals:
1. Greet the customer warmly and introduce yourself as the advisor's AI assistant
2. Collect their profile naturally ONE question at a time — never ask multiple questions together
3. Gather these fields IN ORDER: name → age → marital status → children → monthly income → health → financial goals → risk appetite
4. IMPORTANT: Check the Profile context below. Do NOT re-ask any field already collected. Move to the NEXT missing field.
5. After collecting 5+ data points offer to show suitable product options
6. Offer to schedule a meeting with the advisor once you have a good picture

LANGUAGE: Detect the customer's language and always reply in that SAME language.
Supported: English, Bahasa Malaysia, Mandarin Chinese.

ALWAYS respond with valid JSON only (no markdown fences, no extra text):
{
  "reply": "Your warm 2-3 sentence response. Acknowledge what was shared, then ask the ONE next missing question.",
  "extracted": {
    "name": "only if mentioned in the latest message",
    "age": "only if mentioned in the latest message",
    "income": "only if mentioned in the latest message",
    "marital": "only if mentioned (Single/Married/Divorced/Widowed)",
    "children": "only if mentioned (e.g. '2 children', 'No children')",
    "health": "only if mentioned",
    "goals": "only if mentioned",
    "risk": "only if mentioned (Low/Medium/High)"
  },
  "suggestion_chips": ["Option A", "Option B"],
  "phase": "greeting or profiling or recommending or scheduling or complete",
  "language": "English or Malay or Chinese",
  "ready_for_recommendations": false,
  "offer_schedule": false
}

SUGGESTION CHIPS — include 2-4 short clickable options matching the question just asked:
- Asking marital status → ["Single", "Married", "Divorced", "Widowed"]
- Asking about children → ["No children", "1 child", "2 children", "3+ children"]
- Asking about risk → ["Conservative", "Balanced", "Growth-oriented"]
- Asking about health → ["Excellent", "Good", "Managing a condition"]
- Asking about income → ["< RM3,000", "RM3,000-5,000", "RM5,000-10,000", "> RM10,000"]
- Asking about goals → ["Family protection", "Education savings", "Retirement", "Investment growth"]
- For open text answers (name, age) → use [] (empty array)

Only include fields in "extracted" that were ACTUALLY mentioned in the latest user message.
Set ready_for_recommendations=true when you have name+age+goals+2 more fields.
Set offer_schedule=true after giving recommendations."""


def _extract_profile_fallback(message: str, prospect: dict) -> dict:
    """Rule-based profile extraction when Gemini is unavailable."""
    text = message.lower()
    extracted = {}

    if not prospect.get("name"):
        nm = _re.search(
            r"(?:my\s+(?:full\s+)?name(?:'?s)?\s+is|i(?:'?m| am)|nama saya|saya dipanggil)\s+([A-Za-z][a-zA-Z ]{1,40})",
            message, _re.IGNORECASE
        )
        if nm:
            extracted["name"] = nm.group(1).strip().title()
        else:
            _NON_NAMES = {
                "single","married","divorced","widowed",
                "yes","no","ok","okay","nope","yep","yeah","yea",
                "hi","hello","hey","good","fine","sure","thanks","thank","great",
                "conservative","balanced","excellent","managing",
                "education","retirement","investment","protection","planning","savings",
                "skip","next","stop","none","not","dont",
            }
            _words = message.strip().split()
            if (1 <= len(_words) <= 5 and
                    all(_re.match(r'^[A-Za-z]+$', w) for w in _words) and
                    len(message.strip()) <= 50 and
                    not any(w.lower() in _NON_NAMES for w in _words)):
                extracted["name"] = message.strip().title()

    if not prospect.get("age"):
        age_m = _re.search(r"\b(\d{1,2})\s*(?:years?\s*old|y/?o|tahun)\b", text)
        if age_m:
            extracted["age"] = age_m.group(1)
        else:
            age_m2 = _re.search(r"\bi(?:'m| am)\s+(\d{2})\b", text)
            if age_m2:
                extracted["age"] = age_m2.group(1)

    if not prospect.get("marital"):
        if any(w in text for w in ["married", "kahwin", "dah kahwin", "i am married"]):
            extracted["marital"] = "Married"
        elif "single" in text:
            extracted["marital"] = "Single"
        elif any(w in text for w in ["divorced", "cerai"]):
            extracted["marital"] = "Divorced"
        elif any(w in text for w in ["widowed", "widow", "widower"]):
            extracted["marital"] = "Widowed"

    if not prospect.get("children"):
        ch_m = _re.search(
            r"\b(no|zero|one|two|three|four|1|2|3|4)\s+(?:child(?:ren)?|kid[s]?|anak)\b", text
        )
        if ch_m:
            n = ch_m.group(1)
            n = {"one":"1","two":"2","three":"3","four":"4","no":"0","zero":"0"}.get(n, n)
            extracted["children"] = "No children" if n == "0" else f"{n} children"
        elif any(w in text for w in ["no children", "no kids", "childless", "tiada anak"]):
            extracted["children"] = "No children"

    if not prospect.get("goals"):
        goals = []
        if any(w in text for w in ["education", "university", "school", "study", "tuition"]):
            goals.append("education savings")
        if any(w in text for w in ["protection", "protect", "family secure", "secure my family"]):
            goals.append("family protection")
        if any(w in text for w in ["retire", "retirement", "pension"]):
            goals.append("retirement planning")
        if any(w in text for w in ["invest", "wealth", "grow my money", "unit trust"]):
            goals.append("investment growth")
        if goals:
            extracted["goals"] = ", ".join(goals)

    if not prospect.get("income"):
        inc_m = _re.search(r"rm\s*(\d[\d,]*)", text, _re.IGNORECASE)
        if inc_m:
            extracted["income"] = f"RM{inc_m.group(1)}"
        elif "< rm3" in text or "below 3000" in text or "rm3,000" in text:
            extracted["income"] = "< RM3,000"
        elif "rm5,000" in text or "rm 5000" in text:
            extracted["income"] = "RM5,000-10,000"
        elif "> rm10" in text or "above 10000" in text:
            extracted["income"] = "> RM10,000"

    if not prospect.get("health"):
        if any(w in text for w in ["excellent", "very healthy", "fit"]):
            extracted["health"] = "Excellent"
        elif any(w in text for w in ["good health", "healthy", "fine", "ok"]):
            extracted["health"] = "Good"
        elif any(w in text for w in ["condition", "diabetes", "cancer", "illness", "sick", "hospital"]):
            extracted["health"] = "Managing a condition"

    if not prospect.get("risk"):
        if any(w in text for w in ["conservative", "safe", "low risk", "stable", "guaranteed"]):
            extracted["risk"] = "Low"
        elif any(w in text for w in ["balanced", "moderate", "medium"]):
            extracted["risk"] = "Medium"
        elif any(w in text for w in ["growth", "aggressive", "high risk", "high return"]):
            extracted["risk"] = "High"

    return extracted


def _next_question(prospect: dict) -> tuple:
    """Returns (question, chips) for the next uncollected profile field."""
    order = [
        ("name",    "May I know your full name?", []),
        ("age",     "How old are you?", []),
        ("marital", "What is your marital status?",
         ["Single", "Married", "Divorced", "Widowed"]),
        ("children","Do you have any children?",
         ["No children", "1 child", "2 children", "3+ children"]),
        ("income",  "What is your approximate monthly income?",
         ["< RM3,000", "RM3,000-5,000", "RM5,000-10,000", "> RM10,000"]),
        ("health",  "How would you describe your current health?",
         ["Excellent", "Good", "Managing a condition"]),
        ("goals",   "What are your main financial goals?",
         ["Family protection", "Education savings", "Retirement planning", "Investment growth"]),
        ("risk",    "What is your risk appetite for investments?",
         ["Conservative", "Balanced", "Growth-oriented"]),
    ]
    for field, question, chips in order:
        if not prospect.get(field):
            return question, chips
    return "Thank you! I now have a good picture of your needs. Let me find the best options for you.", []


def _run_clone_ai(session_id: str, user_message: str, conn, forced_language: Optional[str] = None) -> dict:
    history = conn.execute(
        "SELECT role, content FROM chat_messages WHERE session_id=? ORDER BY id ASC LIMIT 20",
        (session_id,)
    ).fetchall()

    prospect = conn.execute("SELECT * FROM prospects WHERE session_id=?", (session_id,)).fetchone()
    prospect_dict = dict(prospect) if prospect else {}
    msg_count = sum(1 for h in history if h["role"] == "user")

    profile_fields = ["name", "age", "income", "marital", "children", "health", "goals", "risk"]
    profile_context = ""
    collected = {k: prospect_dict.get(k, "") for k in profile_fields if prospect_dict.get(k, "")}
    if collected:
        profile_context = f"\n\nProfile collected so far: {json.dumps(collected)}"

    # Inject forced language so Gemini always replies in the customer's chosen language
    _LANG_MAP = {"Malay": "Bahasa Malaysia (Malay)", "Chinese": "Mandarin Chinese", "English": "English"}
    if forced_language and forced_language in _LANG_MAP:
        lang_label = _LANG_MAP[forced_language]
        profile_context += (
            f"\n\nMANDATORY LANGUAGE OVERRIDE: The customer has selected {lang_label}. "
            f"You MUST reply ONLY in {lang_label} for this entire conversation. "
            f"Do not switch to any other language regardless of what the customer writes."
        )

    # If products have already been recommended, tell Gemini to stop profiling
    _already_recommended = bool(
        prospect_dict.get("recommended_products") and
        prospect_dict.get("recommended_products") not in ("[]", "", None)
    )
    if _already_recommended:
        profile_context += (
            "\n\nSTATUS: Products have already been recommended to this customer. "
            "Do NOT ask any more profile questions. "
            "Focus on scheduling a meeting with the advisor. "
            "Set phase='scheduling', ready_for_recommendations=false, offer_schedule=true."
        )

    conversation = ""
    for h in list(history)[-12:]:
        label = "Customer" if h["role"] == "user" else "Assistant"
        conversation += f"{label}: {h['content']}\n"
    if user_message:
        conversation += f"Customer: {user_message}\n"

    full_prompt = f"{_CLONE_SYSTEM}{profile_context}\n\nConversation:\n{conversation}Assistant:"

    gemini = get_gemini_client()
    ai_text = None
    if gemini:
        try:
            from google.genai import types as _gtypes
            resp = gemini.models.generate_content(
                model=_GEMINI_MODEL,
                contents=full_prompt,
                config=_gtypes.GenerateContentConfig(temperature=0.6),
            )
            ai_text = resp.text.strip()
        except Exception:
            pass

    ai_data: dict = {}
    if ai_text:
        try:
            raw = ai_text
            fenced = _re.search(r'```(?:json)?\s*([\s\S]*?)```', raw)
            if fenced:
                raw = fenced.group(1)
            json_m = _re.search(r'\{[\s\S]*\}', raw)
            ai_data = json.loads(json_m.group() if json_m else raw.strip())
        except Exception:
            ai_data = {"reply": ai_text, "extracted": {}, "phase": "profiling", "suggestion_chips": []}

    _FALLBACK_GREETINGS = {
        "Malay": (
            "Hai! Saya adalah pembantu AI untuk penasihat kewangan anda. "
            "Saya di sini untuk membantu memahami matlamat kewangan anda dan mencari penyelesaian terbaik untuk anda. "
            "Boleh saya mulakan dengan bertanya nama anda?"
        ),
        "Chinese": (
            "你好！我是您财务顾问的AI助手。"
            "我在这里帮助了解您的财务目标，为您找到最合适的解决方案。"
            "请问您的姓名是？"
        ),
        "English": (
            "Hello! I'm the AI assistant for your financial advisor. "
            "I'm here to help understand your financial goals and find the right solutions for you. "
            "May I start by asking your name?"
        ),
    }

    if not ai_data:
        if not user_message:
            greeting_lang = forced_language if forced_language in _FALLBACK_GREETINGS else "English"
            ai_data = {
                "reply": _FALLBACK_GREETINGS[greeting_lang],
                "extracted": {}, "phase": "greeting", "suggestion_chips": [],
                "ready_for_recommendations": False, "offer_schedule": False,
            }
        else:
            extracted_fb = _extract_profile_fallback(user_message, prospect_dict)
            merged = {**prospect_dict, **extracted_fb}
            next_q, chips = _next_question(merged)
            ack = "Thank you for sharing that! " if extracted_fb else ""
            filled = sum(1 for f in ["name","age","income","marital","children","goals","risk"] if merged.get(f))
            ai_data = {
                "reply": ack + next_q,
                "extracted": extracted_fb,
                "phase": "profiling",
                "suggestion_chips": chips,
                "ready_for_recommendations": filled >= 5,
                "offer_schedule": False,
            }

    reply = ai_data.get("reply", "")
    chips = ai_data.get("suggestion_chips") or []
    extracted = {k: v for k, v in (ai_data.get("extracted") or {}).items() if v}

    # Fallback name extraction in case Gemini missed it
    if user_message and not prospect_dict.get("name") and "name" not in extracted:
        nm = _re.search(
            r"(?:my\s+(?:full\s+)?name(?:'?s)?\s+is|i(?:'?m| am)|nama saya|saya dipanggil)\s+([A-Za-z][a-zA-Z ]{1,40})",
            user_message, _re.IGNORECASE
        )
        if nm:
            extracted["name"] = nm.group(1).strip().title()
        else:
            _NON_NAMES = {
                "single","married","divorced","widowed",
                "yes","no","ok","okay","nope","yep","yeah","yea",
                "hi","hello","hey","good","fine","sure","thanks","thank","great",
                "conservative","balanced","excellent","managing",
                "education","retirement","investment","protection","planning","savings",
                "skip","next","stop","none","not","dont",
            }
            _words = user_message.strip().split()
            if (1 <= len(_words) <= 5 and
                    all(_re.match(r'^[A-Za-z]+$', w) for w in _words) and
                    len(user_message.strip()) <= 50 and
                    not any(w.lower() in _NON_NAMES for w in _words)):
                extracted["name"] = user_message.strip().title()

    if extracted and prospect:
        set_clause = ", ".join(f"{k}=?" for k in extracted)
        vals = list(extracted.values())
        merged = {**prospect_dict, **extracted}
        new_score = _calc_interest_score(merged, msg_count + 1)
        vals += [new_score, session_id]
        conn.execute(
            f"UPDATE prospects SET {set_clause}, interest_score=?, updated_at=CURRENT_TIMESTAMP WHERE session_id=?",
            vals
        )
        prospect_dict.update(extracted)
    elif prospect:
        new_score = _calc_interest_score(prospect_dict, msg_count + 1)
        conn.execute(
            "UPDATE prospects SET interest_score=?, updated_at=CURRENT_TIMESTAMP WHERE session_id=?",
            (new_score, session_id)
        )

    if user_message:
        conn.execute("INSERT INTO chat_messages (session_id, role, content) VALUES (?,?,?)",
                     (session_id, "user", user_message))
    conn.execute("INSERT INTO chat_messages (session_id, role, content) VALUES (?,?,?)",
                 (session_id, "assistant", reply))

    products = []
    if _already_recommended:
        # Products were shown in a previous turn — pass them again so the
        # frontend can re-render if needed, but don't trigger showMeetingRequest again
        try:
            products = json.loads(prospect_dict.get("recommended_products") or "[]")
        except Exception:
            products = []
    elif ai_data.get("ready_for_recommendations"):
        conn.execute(
            "UPDATE prospects SET status='qualified', updated_at=CURRENT_TIMESTAMP WHERE session_id=?",
            (session_id,)
        )
        products = _score_products(prospect_dict)
        if products:
            conn.execute(
                "UPDATE prospects SET recommended_products=?, updated_at=CURRENT_TIMESTAMP WHERE session_id=?",
                (json.dumps(products), session_id)
            )
            # Replace whatever Gemini said (often still a profile question) with
            # a clean recommendation intro so no profile question leaks through.
            reply = (
                "Based on everything you've shared, I've found some financial solutions "
                "that could be a great fit for you! Here are my top recommendations:"
            )

    if ai_data.get("offer_schedule") or "schedule" in user_message.lower() or "meeting" in user_message.lower():
        conn.execute(
            "UPDATE prospects SET meeting_request='requested', status='meeting_requested', updated_at=CURRENT_TIMESTAMP WHERE session_id=?",
            (session_id,)
        )

    conn.commit()
    # Don't send products on subsequent turns — the frontend already displayed them
    # and would re-trigger showMeetingRequest if products are non-empty.
    products_for_response = [] if _already_recommended else products
    return {"reply": reply, "products": products_for_response, "offer_schedule": ai_data.get("offer_schedule", False),
            "profile_updated": bool(extracted), "phase": ai_data.get("phase", "profiling"),
            "suggestion_chips": chips}


_MEETING_SLOTS = [
    {"id": "mon_2pm",  "label": "Monday",    "time": "2:00 PM",  "display": "Monday 2:00 PM"},
    {"id": "tue_10am", "label": "Tuesday",   "time": "10:00 AM", "display": "Tuesday 10:00 AM"},
    {"id": "wed_4pm",  "label": "Wednesday", "time": "4:00 PM",  "display": "Wednesday 4:00 PM"},
]


# ── Chat HTML (served at /chat — no static files needed) ──────────────────────

_CHAT_HTML = """<!DOCTYPE html>
<html lang="en">
<head>
<meta charset="UTF-8">
<meta name="viewport" content="width=device-width,initial-scale=1">
<title>Advisor AI Assistant</title>
<style>
*{margin:0;padding:0;box-sizing:border-box}
body{font-family:-apple-system,BlinkMacSystemFont,'Segoe UI',sans-serif;background:#e5ddd5}
.app{max-width:480px;margin:0 auto;height:100dvh;display:flex;flex-direction:column;background:#fff;position:relative}
.header{background:linear-gradient(135deg,#4F46E5 0%,#7C3AED 100%);padding:14px 18px;color:#fff;display:flex;align-items:center;gap:12px;flex-shrink:0;box-shadow:0 2px 8px rgba(0,0,0,.2)}
.avatar{width:42px;height:42px;background:rgba(255,255,255,.2);border-radius:50%;display:flex;align-items:center;justify-content:center;font-size:20px;flex-shrink:0}
.hinfo h3{font-size:15px;font-weight:700}
.hinfo p{font-size:11px;opacity:.85;margin-top:1px}
.dot{width:7px;height:7px;background:#4ade80;border-radius:50%;display:inline-block;margin-right:4px;animation:pulse 2s infinite}
.msgs{flex:1;overflow-y:auto;padding:14px 12px;display:flex;flex-direction:column;gap:6px;background:#e5ddd5}
.msg{max-width:78%;padding:9px 13px;border-radius:18px;font-size:14px;line-height:1.5;word-break:break-word;animation:pop .15s ease}
.msg.ai{background:#fff;border-bottom-left-radius:3px;align-self:flex-start;box-shadow:0 1px 2px rgba(0,0,0,.12)}
.msg.user{background:#dcf8c6;border-bottom-right-radius:3px;align-self:flex-end;box-shadow:0 1px 2px rgba(0,0,0,.12)}
.msg .ts{font-size:10px;color:#999;margin-top:4px;text-align:right}
.msg.ai .ts{text-align:left}
.typing-wrap{align-self:flex-start}
.typing{background:#fff;padding:12px 16px;border-radius:18px;border-bottom-left-radius:3px;display:flex;gap:4px;align-items:center;box-shadow:0 1px 2px rgba(0,0,0,.12)}
.typing span{width:7px;height:7px;background:#b0b0b0;border-radius:50%;animation:bounce 1.2s infinite}
.typing span:nth-child(2){animation-delay:.2s}
.typing span:nth-child(3){animation-delay:.4s}
.cards-wrap{align-self:flex-start;width:92%;display:flex;flex-direction:column;gap:8px;animation:pop .2s ease}
.prod-card{background:#fff;border-radius:14px;padding:12px 14px;box-shadow:0 2px 8px rgba(0,0,0,.1);border-left:4px solid #4F46E5}
.prod-card .badge{float:right;background:#dcfce7;color:#15803d;font-size:10px;font-weight:700;padding:2px 8px;border-radius:20px;margin-left:8px}
.prod-card .cat-badge{display:inline-block;font-size:9px;font-weight:700;padding:2px 7px;border-radius:10px;margin-bottom:5px;letter-spacing:.4px;text-transform:uppercase}
.cat-Retirement{background:#fef3c7;color:#92400e}
.cat-Cashflow{background:#fee2e2;color:#991b1b}
.cat-Savings{background:#e0f2fe;color:#075985}
.cat-Investment{background:#e0f2fe;color:#075985}
.cat-Estate{background:#f3e8ff;color:#6b21a8}
.prod-card h4{font-size:13px;font-weight:700;color:#1f2937;margin-bottom:3px}
.prod-card .prod-desc{font-size:11px;color:#6b7280;clear:both;margin-bottom:4px}
.prod-card .prod-detail{font-size:11px;color:#374151;background:#f9fafb;border-radius:8px;padding:6px 8px;margin-top:5px;line-height:1.5}
.prod-card .prod-why{font-size:11px;color:#4F46E5;margin-top:5px;font-style:italic}
.prq-card{align-self:flex-start;width:92%;background:#fff;border-radius:16px;padding:14px;margin:4px 0;box-shadow:0 2px 8px rgba(0,0,0,.1);animation:pop .2s ease;border-left:4px solid #10b981}
.prq-title{font-size:13px;font-weight:700;color:#1f2937;margin-bottom:3px}
.prq-sub{font-size:11px;color:#6b7280;margin-bottom:10px}
.prq-fields{display:grid;grid-template-columns:1fr 1fr;gap:5px;margin-bottom:10px}
.prq-field{display:flex;align-items:center;gap:6px;font-size:12px;color:#374151;background:#f9fafb;border-radius:8px;padding:6px 8px}
.prq-plans{background:#eef2ff;border-radius:10px;padding:8px 10px}
.prq-plans-title{font-size:11px;color:#4338ca;font-weight:700;margin-bottom:5px}
.prq-plan-items{display:flex;flex-wrap:wrap;gap:5px}
.prq-plan{font-size:11px;background:#fff;border-radius:12px;padding:3px 9px;color:#4338ca;font-weight:500}
.sched-btn{align-self:flex-start;background:linear-gradient(135deg,#4F46E5,#7C3AED);color:#fff;border:none;border-radius:14px;padding:11px 18px;font-size:13px;font-weight:700;cursor:pointer;margin:4px 0;box-shadow:0 3px 12px rgba(79,70,229,.35);transition:opacity .2s}
.sched-btn:disabled{opacity:.5;cursor:default}
.input-area{padding:10px 12px;background:#f0f0f0;display:flex;gap:8px;align-items:flex-end;flex-shrink:0;border-top:1px solid #ddd}
textarea{flex:1;border:none;border-radius:22px;padding:9px 16px;font-size:14px;resize:none;outline:none;max-height:110px;font-family:inherit;background:#fff;line-height:1.4}
.btn-send{width:42px;height:42px;background:#4F46E5;border:none;border-radius:50%;cursor:pointer;display:flex;align-items:center;justify-content:center;flex-shrink:0;transition:background .15s}
.btn-send:hover{background:#4338ca}
.btn-send svg{fill:#fff;width:19px;height:19px}
.btn-attach{width:42px;height:42px;background:#fff;border:none;border-radius:50%;cursor:pointer;display:flex;align-items:center;justify-content:center;font-size:20px;flex-shrink:0;box-shadow:0 1px 3px rgba(0,0,0,.15)}
.menu{position:absolute;bottom:70px;left:12px;background:#fff;border-radius:16px;box-shadow:0 8px 28px rgba(0,0,0,.18);padding:6px;display:none;z-index:10}
.menu.open{display:block}
.mitem{display:flex;align-items:center;gap:12px;padding:10px 14px;border-radius:10px;cursor:pointer;font-size:13px;font-weight:500}
.mitem:hover{background:#f9fafb}
.micon{width:38px;height:38px;border-radius:50%;display:flex;align-items:center;justify-content:center;font-size:17px;flex-shrink:0}
.lang-bar{display:flex;gap:6px;padding:6px 12px;background:#f9f9f9;border-bottom:1px solid #eee;flex-shrink:0}
.lang-btn{border:1px solid #d1d5db;background:#fff;border-radius:20px;padding:3px 10px;font-size:11px;cursor:pointer;transition:all .15s;font-weight:500}
.lang-btn.active{background:#4F46E5;color:#fff;border-color:#4F46E5}
.chips-wrap{display:flex;flex-wrap:wrap;gap:6px;padding:2px 0 6px 0;align-self:flex-start;max-width:92%;animation:pop .2s ease}
.chip-btn{border:1.5px solid #4F46E5;color:#4F46E5;background:#fff;border-radius:20px;padding:6px 14px;font-size:12px;font-weight:600;cursor:pointer;transition:all .15s;white-space:nowrap;box-shadow:0 1px 3px rgba(0,0,0,.08)}
.chip-btn:hover{background:#4F46E5;color:#fff}
.slots-wrap{align-self:flex-start;width:90%;background:#fff;border-radius:16px;padding:14px;margin:4px 0;box-shadow:0 2px 8px rgba(0,0,0,.1);animation:pop .2s ease}
.slot-btn{display:flex;align-items:center;gap:10px;width:100%;border:1.5px solid #e5e7eb;background:#fff;border-radius:12px;padding:10px 14px;font-size:13px;cursor:pointer;margin-bottom:8px;transition:all .15s;text-align:left}
.slot-btn:hover{border-color:#4F46E5;background:#eef2ff;color:#4F46E5}
.slot-icon{font-size:16px;flex-shrink:0}
.slot-alt{display:flex;gap:6px;margin-top:2px}
.slot-alt button{flex:1;border:1px solid #e5e7eb;background:#f9fafb;border-radius:10px;padding:7px 4px;font-size:11px;cursor:pointer;transition:all .15s;color:#374151;font-weight:500}
.slot-alt button:hover{border-color:#4F46E5;color:#4F46E5;background:#eef2ff}
.voice-card{align-self:flex-start;width:94%;background:#fff;border-radius:16px;padding:14px;margin:4px 0;box-shadow:0 2px 8px rgba(0,0,0,.1);animation:pop .2s ease;border-left:4px solid #4F46E5}
.voice-header{display:flex;align-items:center;gap:10px;margin-bottom:10px}
.voice-icon{font-size:24px;flex-shrink:0}
.voice-title{font-size:14px;font-weight:700;color:#1f2937}
.voice-conf{font-size:12px;color:#4F46E5;font-weight:600;margin-top:2px}
.voice-transcript{background:#f9fafb;border-radius:10px;padding:10px;font-size:12px;color:#4b5563;font-style:italic;margin:8px 0;line-height:1.5;border-left:3px solid #d1d5db}
.voice-opp{background:#eef2ff;border-radius:10px;padding:10px;font-size:12px;color:#4338ca;margin:8px 0;line-height:1.6}
.voice-fields{display:grid;grid-template-columns:1fr 1fr;gap:6px;margin:8px 0}
.voice-field{background:#f9fafb;border-radius:8px;padding:7px 10px}
.vf-label{font-size:10px;color:#9ca3af;display:block;margin-bottom:2px;text-transform:uppercase;letter-spacing:.4px}
.vf-value{font-size:12px;color:#1f2937;font-weight:600}
.voice-summary{background:#f0fdf4;border-radius:10px;padding:10px;font-size:12px;color:#166534;margin-top:8px;line-height:1.6}
@keyframes pop{from{opacity:0;transform:scale(.95)}to{opacity:1;transform:scale(1)}}
@keyframes bounce{0%,80%,100%{transform:scale(.55);opacity:.4}40%{transform:scale(1);opacity:1}}
@keyframes pulse{0%,100%{opacity:1}50%{opacity:.4}}
</style>
</head>
<body>
<div class="app">
  <div class="header">
    <div class="avatar">🤖</div>
    <div class="hinfo">
      <h3>Advisor AI Assistant</h3>
      <p><span class="dot"></span>Online · Available 24/7</p>
    </div>
  </div>
  <div class="lang-bar">
    <span style="font-size:11px;color:#6b7280;align-self:center;margin-right:2px">Language:</span>
    <button class="lang-btn active" onclick="setLang('English',this)">EN</button>
    <button class="lang-btn" onclick="setLang('Malay',this)">BM</button>
    <button class="lang-btn" onclick="setLang('Chinese',this)">中文</button>
  </div>
  <div class="msgs" id="msgs"></div>
  <div class="menu" id="menu">
    <div class="mitem" onclick="pick('voice')">
      <div class="micon" style="background:#fee2e2">🎤</div>
      <div><div>Voice Note</div><div style="font-size:11px;color:#9ca3af">Send a voice recording</div></div>
    </div>
    <div class="mitem" onclick="pick('pdf')">
      <div class="micon" style="background:#fef3c7">📄</div>
      <div><div>PDF Document</div><div style="font-size:11px;color:#9ca3af">Financial documents</div></div>
    </div>
  </div>
  <input type="file" id="filePick" style="display:none">
  <div class="input-area">
    <button class="btn-attach" onclick="toggleMenu()" title="Attach file">📎</button>
    <textarea id="inp" placeholder="Type a message..." rows="1"
      onkeydown="if(event.key==='Enter'&&!event.shiftKey){event.preventDefault();send()}"
      oninput="this.style.height='auto';this.style.height=Math.min(this.scrollHeight,110)+'px'"></textarea>
    <button class="btn-send" onclick="send()">
      <svg viewBox="0 0 24 24"><path d="M2 21l21-9L2 3v7l15 2-15 2z"/></svg>
    </button>
  </div>
</div>
<script>
const BASE=location.origin;
let sid=null,upType=null,forceLang=null,_meetingShown=false;

async function init(){
  const r=await fetch(BASE+'/chat/session',{method:'POST'});
  const d=await r.json();
  sid=d.session_id;
  await callAI('');
}

function ts(){return new Date().toLocaleTimeString([],{hour:'2-digit',minute:'2-digit'})}

function addMsg(role,html,isHtml=false){
  const c=document.getElementById('msgs');
  const d=document.createElement('div');
  d.className='msg '+role;
  d.innerHTML=(isHtml?html:escHtml(html))+`<div class="ts">${ts()}</div>`;
  c.appendChild(d);
  c.scrollTop=c.scrollHeight;
}

function escHtml(t){return t.replace(/&/g,'&amp;').replace(/</g,'&lt;').replace(/>/g,'&gt;').replace(/\\n/g,'<br>')}

function showTyping(){
  const c=document.getElementById('msgs');
  const d=document.createElement('div');
  d.className='typing-wrap';d.id='typing';
  d.innerHTML='<div class="typing"><span></span><span></span><span></span></div>';
  c.appendChild(d);c.scrollTop=c.scrollHeight;
}
function rmTyping(){document.getElementById('typing')?.remove()}

function removeChips(){document.getElementById('quick-chips')?.remove()}

function showChips(chips){
  if(!chips||!chips.length)return;
  removeChips();
  const c=document.getElementById('msgs');
  const w=document.createElement('div');
  w.className='chips-wrap';w.id='quick-chips';
  chips.forEach(chip=>{
    const btn=document.createElement('button');
    btn.className='chip-btn';btn.textContent=chip;
    btn.onclick=()=>{removeChips();callAI(chip);};
    w.appendChild(btn);
  });
  c.appendChild(w);c.scrollTop=c.scrollHeight;
}

function showProfileCard(){
  document.getElementById('prq-card')?.remove();
  const c=document.getElementById('msgs');
  const w=document.createElement('div');
  w.className='prq-card';w.id='prq-card';
  w.innerHTML=
    `<div class="prq-title">📋 Information I'll Need</div>`+
    `<div class="prq-sub">Share via 🎤 voice note · 📄 PDF · or 💬 type your answers</div>`+
    `<div class="prq-fields">`+
      `<div class="prq-field">👤 Full Name</div>`+
      `<div class="prq-field">🎂 Age</div>`+
      `<div class="prq-field">💍 Marital Status</div>`+
      `<div class="prq-field">👨‍👩‍👧 No. of Children</div>`+
      `<div class="prq-field">💰 Monthly Income (RM)</div>`+
      `<div class="prq-field">❤️ Health Status</div>`+
      `<div class="prq-field">🎯 Financial Goals</div>`+
      `<div class="prq-field">📊 Risk Appetite</div>`+
    `</div>`+
    `<div class="prq-plans">`+
      `<div class="prq-plans-title">Financial Planning Categories</div>`+
      `<div class="prq-plan-items">`+
        `<span class="prq-plan">🌅 Retirement</span>`+
        `<span class="prq-plan">💵 Cashflow</span>`+
        `<span class="prq-plan">📈 Savings &amp; Investment</span>`+
        `<span class="prq-plan">🏛️ Estate</span>`+
      `</div>`+
    `</div>`;
  c.appendChild(w);c.scrollTop=c.scrollHeight;
}

async function callAI(msg){
  if(msg){addMsg('user',msg);removeChips();}
  showTyping();
  try{
    const body={message:msg};
    if(forceLang)body.language=forceLang;
    const r=await fetch(`${BASE}/chat/${sid}/message`,{method:'POST',headers:{'Content-Type':'application/json'},body:JSON.stringify(body)});
    const d=await r.json();
    rmTyping();
    if(d.reply)addMsg('ai',d.reply);
    if(!msg)setTimeout(showProfileCard,300);  // Show requirements card after initial greeting
    if(d.suggestion_chips&&d.suggestion_chips.length)setTimeout(()=>showChips(d.suggestion_chips),200);
    if(d.products&&d.products.length){setTimeout(()=>showProducts(d.products),350);setTimeout(()=>showMeetingRequest(),1400);}
  }catch(e){rmTyping();addMsg('ai','Sorry, something went wrong. Please try again.');}
}

function showProducts(prods){
  const c=document.getElementById('msgs');
  const w=document.createElement('div');
  w.className='cards-wrap';
  prods.forEach(p=>{
    const el=document.createElement('div');
    el.className='prod-card';
    const catKey=(p.category||'').split(/[\s&]/)[0];
    el.innerHTML=
      `<span class="badge">${p.match_pct}% Match</span>`+
      `<span class="cat-badge cat-${catKey}">${p.category||''}</span>`+
      `<h4>${p.emoji} ${p.name}</h4>`+
      `<div class="prod-desc">${p.description}</div>`+
      (p.detail?`<div class="prod-detail">ℹ️ ${p.detail}</div>`:'')+
      (p.why?`<div class="prod-why">💡 ${p.why}</div>`:'');
    w.appendChild(el);
  });
  c.appendChild(w);c.scrollTop=c.scrollHeight;
}

function showMeetingRequest(){
  if(_meetingShown)return;_meetingShown=true;
  setTimeout(()=>{
    addMsg('ai','Would you like to speak with your advisor to discuss these recommendations in more detail? Pick a convenient slot below:');
    setTimeout(()=>{
      const c=document.getElementById('msgs');
      const w=document.createElement('div');
      w.className='slots-wrap';w.id='meeting-slots';
      w.innerHTML=`<div style="font-size:11px;color:#6b7280;font-weight:700;margin-bottom:10px;letter-spacing:.5px">AVAILABLE MEETING SLOTS</div>
<button class="slot-btn" onclick="selectSlot('Monday 2:00 PM','book')"><span class="slot-icon">📅</span><div><div style="font-weight:700">Monday</div><div style="font-size:11px;color:#6b7280">2:00 PM</div></div></button>
<button class="slot-btn" onclick="selectSlot('Tuesday 10:00 AM','book')"><span class="slot-icon">📅</span><div><div style="font-weight:700">Tuesday</div><div style="font-size:11px;color:#6b7280">10:00 AM</div></div></button>
<button class="slot-btn" onclick="selectSlot('Wednesday 4:00 PM','book')"><span class="slot-icon">📅</span><div><div style="font-weight:700">Wednesday</div><div style="font-size:11px;color:#6b7280">4:00 PM</div></div></button>
<div class="slot-alt"><button onclick="selectSlot(null,'callback')">📞 Request Callback</button><button onclick="selectSlot(null,'later')">🕐 Contact Me Later</button><button onclick="selectSlot(null,'decline')">✕ No Thanks</button></div>`;
      c.appendChild(w);c.scrollTop=c.scrollHeight;
    },400);
  },600);
}

async function selectSlot(slot,action){
  document.getElementById('meeting-slots')?.remove();
  const label=slot||(action==='callback'?'Request Callback':action==='later'?'Contact Me Later':'No Thanks');
  addMsg('user',label);showTyping();
  try{
    const r=await fetch(`${BASE}/chat/${sid}/book-meeting`,{method:'POST',headers:{'Content-Type':'application/json'},body:JSON.stringify({slot,action})});
    const d=await r.json();rmTyping();
    addMsg('ai',d.message||'Thank you!');
  }catch(e){rmTyping();addMsg('ai','Sorry, something went wrong. Please try again.');}
}

function send(){
  const inp=document.getElementById('inp');
  const msg=inp.value.trim();
  if(!msg||!sid)return;
  inp.value='';inp.style.height='auto';
  removeChips();
  callAI(msg);
}

function setLang(lang,btn){
  forceLang=lang;
  document.querySelectorAll('.lang-btn').forEach(b=>b.classList.remove('active'));
  btn.classList.add('active');
  // No user messages yet — clear chat and re-greet in chosen language
  if(!document.querySelector('.msg.user')&&sid){
    document.getElementById('msgs').innerHTML='';
    callAI('');
  }
}

function toggleMenu(){document.getElementById('menu').classList.toggle('open')}

function pick(type){
  upType=type;
  const f=document.getElementById('filePick');
  f.accept=type==='voice'?'audio/*':type==='image'?'image/*':'.pdf';
  f.click();
  document.getElementById('menu').classList.remove('open');
}

function showVoiceCard(d){
  const vp=d.voice_profile||{};
  const conf=vp.confidence||0;
  const fields=[
    ['Name',vp.name],['Age',vp.age],['Marital',vp.marital],
    ['Children',vp.children],['Income',vp.income],
    ['Goal',vp.goals],['Health',vp.health],['Risk',vp.risk]
  ].filter(([,v])=>v&&v.trim());
  const confColor=conf>=80?'#16a34a':conf>=50?'#d97706':'#dc2626';
  const c=document.getElementById('msgs');
  const w=document.createElement('div');
  w.className='voice-card';
  w.innerHTML=
    `<div class="voice-header">
      <span class="voice-icon">🎙️</span>
      <div>
        <div class="voice-title">Voice Note Processed</div>
        <div class="voice-conf" style="color:${confColor}">AI Confidence: ${conf}%</div>
      </div>
    </div>`+
    (d.transcript?`<div class="voice-transcript">"${d.transcript}"</div>`:'')+
    (vp.opportunity?`<div class="voice-opp"><b>✨ ${vp.opportunity}</b>${vp.opportunity_reason?'<br><span style="font-weight:400">'+vp.opportunity_reason+'</span>':''}</div>`:'')+
    (fields.length?`<div class="voice-fields">${fields.map(([k,v])=>`<div class="voice-field"><span class="vf-label">${k}</span><span class="vf-value">${v}</span></div>`).join('')}</div>`:'')+
    (vp.ai_summary?`<div class="voice-summary"><b>📋 Prospect Summary</b><br>${vp.ai_summary}</div>`:'');
  c.appendChild(w);c.scrollTop=c.scrollHeight;
}

document.getElementById('filePick').onchange=async function(e){
  const file=e.target.files[0];if(!file)return;
  const isVoice=upType==='voice';
  addMsg('user',isVoice?`🎤 ${file.name}`:`📎 ${file.name}`);showTyping();
  const fd=new FormData();fd.append('file',file);fd.append('type',upType);
  try{
    const r=await fetch(`${BASE}/chat/${sid}/upload`,{method:'POST',body:fd});
    const d=await r.json();rmTyping();
    if(isVoice&&d.voice_profile){
      showVoiceCard(d);
    } else {
      if(d.reply)addMsg('ai',d.reply);
    }
    if(d.products&&d.products.length){
      setTimeout(()=>showProducts(d.products),isVoice?900:350);
      setTimeout(()=>showMeetingRequest(),isVoice?2200:1400);
    }
  }catch(e){rmTyping();addMsg('ai','Sorry, I could not process that file.');}
  e.target.value='';
};

document.addEventListener('click',e=>{
  if(!e.target.closest('.btn-attach')&&!e.target.closest('.menu'))
    document.getElementById('menu').classList.remove('open');
});

init();
</script>
</body>
</html>"""


# ── Chat endpoints ─────────────────────────────────────────────────────────────

@app.get("/chat", response_class=HTMLResponse)
def chat_page():
    return HTMLResponse(content=_CHAT_HTML)


@app.post("/chat/session")
def create_chat_session():
    session_id = str(_uuid.uuid4())
    conn = get_conn()
    conn.execute("INSERT INTO prospects (session_id, status) VALUES (?, 'new')", (session_id,))
    conn.commit()
    conn.close()
    return {"session_id": session_id}


@app.post("/chat/{session_id}/message")
def chat_message(session_id: str, req: ChatMsgRequest):
    conn = get_conn()
    if not conn.execute("SELECT id FROM prospects WHERE session_id=?", (session_id,)).fetchone():
        conn.close()
        raise HTTPException(status_code=404, detail="Session not found")
    result = _run_clone_ai(session_id, req.message, conn, forced_language=req.language)
    conn.close()
    return result


@app.post("/chat/{session_id}/upload")
async def chat_upload(session_id: str, file: UploadFile = File(...), type: str = Form("image")):
    conn = get_conn()
    if not conn.execute("SELECT id FROM prospects WHERE session_id=?", (session_id,)).fetchone():
        conn.close()
        raise HTTPException(status_code=404, detail="Session not found")

    content = await file.read()
    extracted_text = ""

    if type == "pdf":
        try:
            import pypdf
            reader = pypdf.PdfReader(io.BytesIO(content))
            extracted_text = "\n".join(page.extract_text() or "" for page in reader.pages[:5])
        except Exception:
            pass

    elif type == "image":
        gemini = get_gemini_client()
        if gemini:
            try:
                from google.genai import types as _vt
                mime = file.content_type or "image/jpeg"
                resp = gemini.models.generate_content(
                    model=_GEMINI_MODEL,
                    contents=[
                        _vt.Part.from_bytes(data=content, mime_type=mime),
                        "Extract all text and personal/financial information visible in this image."
                    ]
                )
                extracted_text = resp.text.strip()
            except Exception:
                pass

    elif type == "voice":
        mime = file.content_type or "audio/mp3"
        try:
            extracted_text = _transcribe_audio(content, mime)
        except Exception as e:
            extracted_text = ""

    # ── Voice: full pipeline (extract profile → products → summary) ──────────
    if type == "voice":
        if not extracted_text:
            conn.close()
            return {
                "reply": "I received your voice note but couldn't make out the audio clearly. Please try again in a quieter environment, or type your details instead.",
                "products": [], "offer_schedule": False,
            }

        prospect_row = conn.execute("SELECT * FROM prospects WHERE session_id=?", (session_id,)).fetchone()
        prospect_dict = dict(prospect_row) if prospect_row else {}

        voice_profile = _extract_voice_profile(extracted_text, prospect_dict)

        # Update prospect with extracted fields (only fill missing ones)
        update_fields = {}
        for field in ["name", "age", "marital", "children", "income", "health", "goals", "risk"]:
            val = voice_profile.get(field, "")
            if val and not prospect_dict.get(field):
                update_fields[field] = val

        merged = {**prospect_dict, **update_fields}
        score = _calc_interest_score(merged, 1)
        ai_summary_text = voice_profile.get("ai_summary", "")

        if update_fields:
            set_clause = ", ".join(f"{k}=?" for k in update_fields)
            vals = list(update_fields.values()) + [score, extracted_text, ai_summary_text, session_id]
            conn.execute(
                f"UPDATE prospects SET {set_clause}, interest_score=?, voice_transcript=?, ai_summary=?, updated_at=CURRENT_TIMESTAMP WHERE session_id=?",
                vals,
            )
        else:
            conn.execute(
                "UPDATE prospects SET interest_score=?, voice_transcript=?, ai_summary=?, updated_at=CURRENT_TIMESTAMP WHERE session_id=?",
                (score, extracted_text, ai_summary_text, session_id),
            )

        products = _score_products(merged)
        if products:
            conn.execute(
                "UPDATE prospects SET recommended_products=?, status='qualified', updated_at=CURRENT_TIMESTAMP WHERE session_id=?",
                (json.dumps(products), session_id),
            )

        ai_reply = (
            f"I've processed your voice note! Here's what I understood — check the profile summary below. "
            f"I've automatically filled in your details and found some tailored product recommendations for you."
        )
        conn.execute(
            "INSERT INTO chat_messages (session_id, role, content) VALUES (?,?,?)",
            (session_id, "user", f"[VOICE NOTE] {extracted_text[:400]}"),
        )
        conn.execute(
            "INSERT INTO chat_messages (session_id, role, content) VALUES (?,?,?)",
            (session_id, "assistant", ai_reply),
        )
        conn.commit()
        conn.close()
        return {
            "reply": ai_reply,
            "products": products,
            "offer_schedule": False,
            "voice_profile": voice_profile,
            "transcript": extracted_text,
        }

    # ── Non-voice uploads ────────────────────────────────────────────────────
    if extracted_text:
        synthetic_msg = f"[{type.upper()}] {extracted_text[:600]}"
        result = _run_clone_ai(session_id, synthetic_msg, conn)
    else:
        result = {"reply": f"I received your {type}, but had trouble reading it. Could you describe the key points in text?",
                  "products": [], "offer_schedule": False}

    conn.close()
    return result


@app.get("/chat/slots")
def get_meeting_slots():
    return _MEETING_SLOTS


@app.post("/chat/{session_id}/book-meeting")
def book_meeting(session_id: str, req: BookMeetingRequest):
    conn = get_conn()
    prospect = conn.execute(
        "SELECT * FROM prospects WHERE session_id=?", (session_id,)
    ).fetchone()
    if not prospect:
        conn.close()
        raise HTTPException(status_code=404, detail="Session not found")
    p = dict(prospect)

    if req.action == "decline":
        conn.commit()
        conn.close()
        return {"ok": True, "message": "No problem at all! If you ever change your mind, our advisor is always available. Have a great day!"}

    if req.action == "later":
        conn.execute(
            "UPDATE prospects SET meeting_request='contact_later', updated_at=CURRENT_TIMESTAMP WHERE session_id=?",
            (session_id,),
        )
        conn.commit()
        conn.close()
        return {"ok": True, "message": "Of course! We will reach out to you at a convenient time. Feel free to come back anytime if you have questions."}

    slot_text = req.slot if req.action == "book" else "Callback Requested"
    products = []
    try:
        products = json.loads(p.get("recommended_products") or "[]")
    except Exception:
        pass
    top_product = products[0]["name"] if products else "General Financial Review"

    conn.execute(
        "UPDATE prospects SET meeting_slot=?, meeting_request='requested', status='meeting_requested', updated_at=CURRENT_TIMESTAMP WHERE session_id=?",
        (slot_text, session_id),
    )
    conn.execute(
        """INSERT INTO prospect_meetings
           (prospect_id, session_id, slot, status, prospect_name, prospect_goals, interest_score, recommended_product)
           VALUES (?, ?, ?, 'pending', ?, ?, ?, ?)""",
        (
            p["id"], session_id, slot_text,
            p.get("name") or "Unknown",
            p.get("goals") or "",
            p.get("interest_score") or 0,
            top_product,
        ),
    )
    conn.commit()
    conn.close()

    if req.action == "callback":
        msg = "A callback request has been sent to your advisor. They will contact you shortly to arrange a convenient time!"
    else:
        msg = f"Your meeting request for {slot_text} has been sent to your advisor. You will receive a confirmation soon!"
    return {"ok": True, "message": msg}


@app.get("/prospect-meetings")
def list_prospect_meetings():
    conn = get_conn()
    rows = conn.execute(
        "SELECT * FROM prospect_meetings ORDER BY created_at DESC"
    ).fetchall()
    conn.close()
    return [dict(r) for r in rows]


@app.put("/prospect-meetings/{meeting_id}/respond")
def respond_to_meeting(meeting_id: int, payload: dict):
    response = payload.get("response", "")
    new_status = {"confirmed": "confirmed", "declined": "declined"}.get(response, "pending")
    conn = get_conn()
    conn.execute(
        "UPDATE prospect_meetings SET advisor_response=?, status=?, updated_at=CURRENT_TIMESTAMP WHERE id=?",
        (response, new_status, meeting_id),
    )
    if response == "confirmed":
        row = conn.execute(
            "SELECT session_id FROM prospect_meetings WHERE id=?", (meeting_id,)
        ).fetchone()
        if row:
            conn.execute(
                "UPDATE prospects SET status='meeting_requested', updated_at=CURRENT_TIMESTAMP WHERE session_id=?",
                (row["session_id"],),
            )
    conn.commit()
    conn.close()
    return {"ok": True}


# ── Prospect management (advisor dashboard) ───────────────────────────────────

@app.get("/prospects")
def list_prospects():
    conn = get_conn()
    rows = conn.execute("SELECT * FROM prospects ORDER BY updated_at DESC").fetchall()
    conn.close()
    result = []
    for r in rows:
        d = dict(r)
        try:
            d["recommended_products"] = json.loads(d.get("recommended_products") or "[]")
        except Exception:
            d["recommended_products"] = []
        result.append(d)
    return result


@app.get("/prospects/{prospect_id}")
def get_prospect(prospect_id: int):
    conn = get_conn()
    row = conn.execute("SELECT * FROM prospects WHERE id=?", (prospect_id,)).fetchone()
    if not row:
        conn.close()
        raise HTTPException(status_code=404, detail="Prospect not found")
    d = dict(row)
    try:
        d["recommended_products"] = json.loads(d.get("recommended_products") or "[]")
    except Exception:
        d["recommended_products"] = []
    msgs = conn.execute(
        "SELECT role, content, message_type, created_at FROM chat_messages WHERE session_id=? ORDER BY id ASC",
        (d["session_id"],)
    ).fetchall()
    d["messages"] = [dict(m) for m in msgs]
    conn.close()
    return d


@app.put("/prospects/{prospect_id}/status")
def update_prospect_status(prospect_id: int, payload: dict):
    conn = get_conn()
    conn.execute(
        "UPDATE prospects SET status=?, updated_at=CURRENT_TIMESTAMP WHERE id=?",
        (payload.get("status", ""), prospect_id)
    )
    conn.commit()
    conn.close()
    return {"ok": True}


@app.post("/prospects/{prospect_id}/convert")
def convert_prospect(prospect_id: int):
    conn = get_conn()
    p = conn.execute("SELECT * FROM prospects WHERE id=?", (prospect_id,)).fetchone()
    if not p:
        conn.close()
        raise HTTPException(status_code=404, detail="Prospect not found")
    p = dict(p)
    result = conn.execute(
        "INSERT INTO clients (name, age, marital, children, health, concern, risk, personality) VALUES (?,?,?,?,?,?,?,?)",
        (p.get("name") or "Unknown", p.get("age") or "", p.get("marital") or "",
         p.get("children") or "", p.get("health") or "", p.get("goals") or "",
         p.get("risk") or "Medium", "Via AI Advisor Clone")
    )
    new_id = result.lastrowid
    conn.execute(
        "UPDATE prospects SET status='converted', updated_at=CURRENT_TIMESTAMP WHERE id=?",
        (prospect_id,)
    )
    conn.commit()
    conn.close()
    return {"ok": True, "client_id": new_id}
