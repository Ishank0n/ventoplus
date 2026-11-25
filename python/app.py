"""Breathe API: Google sign-in, breathing techniques, users, sessions, band readings.

Run:  python app.py      (reads settings from .env)

Required in .env (never hardcode these):
    GOOGLE_WEB_CLIENT_ID=xxxx.apps.googleusercontent.com   (the WEB client ID)
    JWT_SECRET=<python -c "import secrets; print(secrets.token_urlsafe(64))">
    ADMIN_API_KEY=<random string, only for technique admin endpoints>
    + your existing DB settings used by db.py
Optional: HOST (default 0.0.0.0), PORT (default 5001), CORS_ORIGINS, SESSIONS_PER_STAGE

Install:
    pip install flask python-dotenv pymysql google-auth requests PyJWT

Security notes
  * Every query is parameterized. The only f-string SQL pieces are fixed,
    whitelisted column names or placeholder lists, never user input.
  * Users are exposed only by a random UUID (public_id), never the auto-increment id.
  * Sign-in is Google -> /auth/google -> our own access + refresh tokens.
  * Every /api/users/<user_id>/... route requires a valid access token AND
    <user_id> must be the signed-in user, so nobody can read another user's data.
  * Technique admin endpoints and POST /api/users need X-Admin-Key (ADMIN_API_KEY).
  * Debug mode is always off: Flask's debugger lets anyone on the network run code.
"""
import hashlib
import hmac
import json
import logging
import math
import os
import re
import secrets
import uuid
from datetime import datetime, timedelta, timezone
from decimal import Decimal
from functools import wraps

from dotenv import load_dotenv

load_dotenv()  # must run before anything reads os.environ (including db.py)

import jwt  # noqa: E402
import pymysql  # noqa: E402
from flask import Flask, Blueprint, g, jsonify, request  # noqa: E402
from google.auth.transport import requests as google_requests  # noqa: E402
from google.oauth2 import id_token  # noqa: E402
from werkzeug.exceptions import HTTPException  # noqa: E402

from db import get_connection  # noqa: E402

log = logging.getLogger("breathe-api")
logging.basicConfig(level=logging.INFO)


# --------------------------------------------------------------------------
# Config (fails fast at startup if anything is missing)
# --------------------------------------------------------------------------
def _required_env(name: str) -> str:
    value = os.environ.get(name, "").strip()
    if not value:
        raise RuntimeError(f"{name} is missing from .env")
    return value


GOOGLE_WEB_CLIENT_ID = _required_env("GOOGLE_WEB_CLIENT_ID")
JWT_SECRET = _required_env("JWT_SECRET")
if len(JWT_SECRET) < 32:
    raise RuntimeError("JWT_SECRET is too short; generate one with secrets.token_urlsafe(64)")

ACCESS_TTL = timedelta(minutes=15)
REFRESH_DAYS = 30
_google_request = google_requests.Request()  # reused so Google's certs get cached

SESSIONS_PER_STAGE = int(os.environ.get("SESSIONS_PER_STAGE", "10"))
PLANT_STAGES = ("collected", "grown", "flourishing")
PHASE_TYPES = ("inhale", "hold_in", "exhale", "hold_out")
SESSION_STATUSES = ("in_progress", "completed", "abandoned")
MAX_SESSION_SEC = 4 * 60 * 60
MAX_READINGS_PER_REQUEST = 200
MAX_SENSOR_FIELDS = 20
SLUG_RE = re.compile(r"^[a-z0-9]+(?:-[a-z0-9]+)*$")
EMAIL_RE = re.compile(r"^[^@\s]+@[^@\s]+\.[^@\s]+$")
DUPLICATE_KEY = 1062


# --------------------------------------------------------------------------
# App (created exactly once)
# --------------------------------------------------------------------------
app = Flask(__name__)
app.json.sort_keys = False

_cors_origins = [o.strip() for o in os.environ.get("CORS_ORIGINS", "").split(",") if o.strip()]
if _cors_origins:
    from flask_cors import CORS

    CORS(app, resources={r"/api/*": {"origins": _cors_origins}})


# --------------------------------------------------------------------------
# Errors (everything returns JSON, details only go to the server log)
# --------------------------------------------------------------------------
class ApiError(Exception):
    def __init__(self, status: int, message: str):
        super().__init__(message)
        self.status = status
        self.message = message


@app.errorhandler(ApiError)
def handle_api_error(err):
    return jsonify(error=err.message), err.status


@app.errorhandler(pymysql.MySQLError)
def handle_db_error(_err):
    log.exception("Database error")
    return jsonify(error="A database error occurred."), 500


@app.errorhandler(404)
def handle_not_found(_err):
    return jsonify(error="Not found."), 404


@app.errorhandler(405)
def handle_bad_method(_err):
    return jsonify(error="Method not allowed."), 405


@app.errorhandler(HTTPException)
def handle_http_error(err):
    return jsonify(error=err.description), err.code


@app.errorhandler(Exception)
def handle_unexpected(_err):
    log.exception("Unhandled error")
    return jsonify(error="Internal server error."), 500


# --------------------------------------------------------------------------
# DB connection per request
# --------------------------------------------------------------------------
def db():
    if "db" not in g:
        g.db = get_connection()
    return g.db


@app.teardown_appcontext
def close_db(_exc):
    conn = g.pop("db", None)
    if conn is None:
        return
    try:
        conn.rollback()  # discards anything not explicitly committed
    except pymysql.MySQLError:
        pass
    finally:
        conn.close()


# --------------------------------------------------------------------------
# Input helpers
# --------------------------------------------------------------------------
def json_body() -> dict:
    data = request.get_json(silent=True)
    if not isinstance(data, dict):
        raise ApiError(400, "Request body must be a JSON object.")
    return data


def json_token_field(name: str) -> str:
    value = json_body().get(name)
    if not isinstance(value, str) or not value or len(value) > 4096:
        raise ApiError(400, f"'{name}' is required.")
    return value


def parse_uuid(value, label: str) -> str:
    try:
        return str(uuid.UUID(str(value)))
    except (ValueError, TypeError):
        raise ApiError(400, f"{label} must be a valid UUID.")


def get_int(data, key, *, required=False, default=None, min_value=None, max_value=None):
    if data.get(key) is None:
        if required:
            raise ApiError(400, f"'{key}' is required.")
        return default
    value = data[key]
    if isinstance(value, bool) or not isinstance(value, int):
        raise ApiError(400, f"'{key}' must be an integer.")
    if (min_value is not None and value < min_value) or (max_value is not None and value > max_value):
        raise ApiError(400, f"'{key}' must be between {min_value} and {max_value}.")
    return value


def get_number(data, key, *, required=False, min_value=None, max_value=None):
    if data.get(key) is None:
        if required:
            raise ApiError(400, f"'{key}' is required.")
        return None
    value = data[key]
    if isinstance(value, bool) or not isinstance(value, (int, float)) or not math.isfinite(value):
        raise ApiError(400, f"'{key}' must be a number.")
    if (min_value is not None and value < min_value) or (max_value is not None and value > max_value):
        raise ApiError(400, f"'{key}' must be between {min_value} and {max_value}.")
    return Decimal(str(value)).quantize(Decimal("0.01"))


def get_str(data, key, *, required=False, max_len=255):
    value = data.get(key)
    if value is None or (isinstance(value, str) and not value.strip()):
        if required:
            raise ApiError(400, f"'{key}' is required.")
        return None
    if not isinstance(value, str):
        raise ApiError(400, f"'{key}' must be a string.")
    value = value.strip()
    if len(value) > max_len:
        raise ApiError(400, f"'{key}' must be at most {max_len} characters.")
    return value


def query_int(name, default, min_value, max_value):
    raw = request.args.get(name)
    if raw is None:
        return default
    try:
        value = int(raw)
    except ValueError:
        raise ApiError(400, f"Query parameter '{name}' must be an integer.")
    if not min_value <= value <= max_value:
        raise ApiError(400, f"Query parameter '{name}' must be between {min_value} and {max_value}.")
    return value


def parse_timestamp(value, key):
    """Accept ISO-8601 with a timezone; store as naive UTC."""
    if value is None:
        return None
    if not isinstance(value, str):
        raise ApiError(400, f"'{key}' must be an ISO-8601 timestamp string.")
    try:
        parsed = datetime.fromisoformat(value.replace("Z", "+00:00"))
    except ValueError:
        raise ApiError(400, f"'{key}' must be an ISO-8601 timestamp.")
    if parsed.tzinfo is None:
        raise ApiError(400, f"'{key}' must include a timezone, e.g. 2026-10-27T13:09:00Z.")
    return parsed.astimezone(timezone.utc).replace(tzinfo=None, microsecond=0)


def utc_now():
    return datetime.now(timezone.utc).replace(tzinfo=None, microsecond=0)


def require_admin():
    expected = os.environ.get("ADMIN_API_KEY")
    if not expected:
        raise ApiError(403, "Admin endpoints are disabled (ADMIN_API_KEY is not set).")
    provided = request.headers.get("X-Admin-Key", "")
    if not hmac.compare_digest(provided.encode(), expected.encode()):
        raise ApiError(401, "Invalid or missing admin key.")


# --------------------------------------------------------------------------
# Auth: Google token check, users, our own tokens
# --------------------------------------------------------------------------
def hash_token(raw: str) -> str:
    return hashlib.sha256(raw.encode()).hexdigest()


def verify_google_token(raw: str) -> dict:
    """Checks signature, expiry, issuer, and that the token was issued for our server."""
    claims = id_token.verify_oauth2_token(raw, _google_request, GOOGLE_WEB_CLIENT_ID)
    if not claims.get("email_verified"):
        raise ValueError("Google email not verified")
    return claims


def find_or_create_user(cur, claims: dict) -> dict:
    sub = claims["sub"]
    email = (claims.get("email") or "").lower() or None

    # 1. Returning Google user
    cur.execute(
        """SELECT u.id, u.public_id FROM user_identities i
           JOIN users u ON u.id = i.user_id
           WHERE i.provider = 'google' AND i.provider_subject = %s""",
        (sub,),
    )
    user = cur.fetchone()
    if user:
        cur.execute(
            """UPDATE user_identities
               SET email = %s, avatar_url = %s, last_login_at = UTC_TIMESTAMP()
               WHERE provider = 'google' AND provider_subject = %s""",
            (email, claims.get("picture"), sub),
        )
        return user

    # 2. First Google login: link to an existing user with this email, else create one.
    #    NOTE: emails created through the old POST /api/users were never verified.
    #    If real users already exist, review this linking rule before going live.
    user = None
    if email:
        cur.execute("SELECT id, public_id FROM users WHERE email = %s", (email,))
        user = cur.fetchone()
    if not user:
        public_id = str(uuid.uuid4())
        cur.execute(
            "INSERT INTO users (public_id, display_name, email) VALUES (%s, %s, %s)",
            (public_id, (claims.get("name") or email or "Breather")[:100], email),
        )
        user = {"id": cur.lastrowid, "public_id": public_id}

    cur.execute(
        """INSERT INTO user_identities
               (user_id, provider, provider_subject, email, avatar_url, last_login_at)
           VALUES (%s, 'google', %s, %s, %s, UTC_TIMESTAMP())""",
        (user["id"], sub, email, claims.get("picture")),
    )
    return user


def issue_tokens(cur, user: dict) -> dict:
    now = datetime.now(timezone.utc)
    access = jwt.encode(
        {"sub": user["public_id"], "iat": now, "exp": now + ACCESS_TTL, "type": "access"},
        JWT_SECRET,
        algorithm="HS256",
    )
    refresh = secrets.token_urlsafe(48)
    cur.execute(
        """INSERT INTO auth_refresh_tokens (user_id, token_hash, expires_at)
           VALUES (%s, %s, UTC_TIMESTAMP() + INTERVAL %s DAY)""",
        (user["id"], hash_token(refresh), REFRESH_DAYS),
    )
    return {
        "access_token": access,
        "refresh_token": refresh,
        "expires_in": int(ACCESS_TTL.total_seconds()),
        "user_id": user["public_id"],
    }


def login_required(view):
    """Puts the signed-in user on g.user. Goes BELOW the @app.get/@app.post line."""
    @wraps(view)
    def wrapper(*args, **kwargs):
        header = request.headers.get("Authorization", "")
        if not header.startswith("Bearer "):
            raise ApiError(401, "Missing token.")
        try:
            claims = jwt.decode(header[7:], JWT_SECRET, algorithms=["HS256"])  # pin algorithm
        except jwt.PyJWTError:
            raise ApiError(401, "Token expired or invalid.")
        if claims.get("type") != "access" or not claims.get("sub"):
            raise ApiError(401, "Wrong token type.")

        cur = db().cursor()
        cur.execute(
            "SELECT id, public_id, display_name, email, created_at FROM users WHERE public_id = %s",
            (claims["sub"],),
        )
        g.user = cur.fetchone()
        if not g.user:
            raise ApiError(401, "User not found.")
        return view(*args, **kwargs)

    return wrapper


def own_user(user_id):
    """The <user_id> in the URL must be the signed-in user. Use after @login_required."""
    if parse_uuid(user_id, "user_id") != g.user["public_id"]:
        raise ApiError(403, "You can only access your own data.")
    return g.user


auth_bp = Blueprint("auth", __name__, url_prefix="/auth")


@auth_bp.post("/google")
def login_google():
    raw = json_token_field("id_token")
    try:
        claims = verify_google_token(raw)
    except ValueError:
        raise ApiError(401, "Invalid Google token.")

    conn = db()
    cur = conn.cursor()
    try:
        user = find_or_create_user(cur, claims)
    except pymysql.err.IntegrityError as e:
        # Two first-time logins at once: the other one created the rows, so just look them up
        if e.args[0] != DUPLICATE_KEY:
            raise
        conn.rollback()
        user = find_or_create_user(cur, claims)
    tokens = issue_tokens(cur, user)
    conn.commit()
    return jsonify(tokens)


@auth_bp.post("/refresh")
def refresh_tokens():
    raw = json_token_field("refresh_token")
    conn = db()
    cur = conn.cursor()
    cur.execute(
        """SELECT t.id, u.id AS user_id, u.public_id
           FROM auth_refresh_tokens t JOIN users u ON u.id = t.user_id
           WHERE t.token_hash = %s
             AND t.revoked_at IS NULL
             AND t.expires_at > UTC_TIMESTAMP()
           FOR UPDATE""",
        (hash_token(raw),),
    )
    row = cur.fetchone()
    if not row:
        raise ApiError(401, "Invalid refresh token.")

    # Rotate: each refresh token can be used once
    cur.execute("UPDATE auth_refresh_tokens SET revoked_at = UTC_TIMESTAMP() WHERE id = %s", (row["id"],))
    tokens = issue_tokens(cur, {"id": row["user_id"], "public_id": row["public_id"]})
    conn.commit()
    return jsonify(tokens)


@auth_bp.post("/logout")
def logout():
    raw = json_token_field("refresh_token")
    conn = db()
    cur = conn.cursor()
    cur.execute(
        """UPDATE auth_refresh_tokens SET revoked_at = UTC_TIMESTAMP()
           WHERE token_hash = %s AND revoked_at IS NULL""",
        (hash_token(raw),),
    )
    conn.commit()
    return jsonify(ok=True)


app.register_blueprint(auth_bp)


# --------------------------------------------------------------------------
# Output helpers
# --------------------------------------------------------------------------
def iso(value):
    return None if value is None else value.replace(tzinfo=timezone.utc).isoformat().replace("+00:00", "Z")


def num(value):
    """Decimal/float -> int when whole, else float (so 4.00 shows as 4)."""
    if value is None:
        return None
    value = float(value)
    return int(value) if value.is_integer() else round(value, 2)


def pattern_label(phases):
    return "-".join(str(num(p["duration_sec"])) for p in phases)


def user_json(row):
    return {
        "id": row["public_id"],
        "display_name": row["display_name"],
        "email": row["email"],
        "created_at": iso(row["created_at"]),
    }


def technique_json(row, phases):
    return {
        "id": row["id"],
        "slug": row["slug"],
        "name": row["name"],
        "description": row["description"],
        "pattern": pattern_label(phases),
        "phases": phases,
        "cycle_duration_sec": num(sum(Decimal(str(p["duration_sec"])) for p in phases)),
        "default_duration_sec": row["default_duration_sec"],
        "plant_key": row["plant_key"],
        "sort_order": row["sort_order"],
        "is_active": bool(row["is_active"]),
    }


def load_snapshot(value):
    if isinstance(value, (str, bytes)):
        return json.loads(value)
    return value


def session_json(row):
    phases = load_snapshot(row["phase_snapshot"])
    target, elapsed = row["target_duration_sec"], row["elapsed_sec"]
    return {
        "id": row["public_id"],
        "technique": {
            "id": row["technique_id"],
            "slug": row["technique_slug"],
            "name": row["technique_name"],
            "plant_key": row["technique_plant_key"],
        },
        "status": row["status"],
        "pattern": pattern_label(phases),
        "phases": phases,
        "target_duration_sec": target,
        "elapsed_sec": elapsed,
        "remaining_sec": max(target - elapsed, 0),
        "progress_pct": round(min(elapsed / target, 1) * 100, 1) if target else 0,
        "cycles_completed": row["cycles_completed"],
        "accuracy_pct": num(row["accuracy_pct"]),
        "started_at": iso(row["started_at"]),
        "completed_at": iso(row["completed_at"]),
        "updated_at": iso(row["updated_at"]),
    }


def plant_progress(completed_count):
    """Every SESSIONS_PER_STAGE completed sessions grows the plant one stage.

    0 -> not collected; 1-9 -> collected; 10-19 -> grown; 20+ -> flourishing.
    """
    if completed_count == 0:
        return {"stage": "not_collected", "completed_sessions": 0,
                "progress_to_next": 0, "sessions_per_stage": SESSIONS_PER_STAGE}
    level = min(completed_count // SESSIONS_PER_STAGE, len(PLANT_STAGES) - 1)
    is_final = level == len(PLANT_STAGES) - 1
    return {
        "stage": PLANT_STAGES[level],
        "completed_sessions": completed_count,
        "progress_to_next": None if is_final else completed_count % SESSIONS_PER_STAGE,
        "sessions_per_stage": SESSIONS_PER_STAGE,
    }


# --------------------------------------------------------------------------
# Data access helpers
# --------------------------------------------------------------------------
TECHNIQUE_COLUMNS = "id, slug, name, description, default_duration_sec, plant_key, sort_order, is_active"

SESSION_SELECT = """
    SELECT s.id, s.public_id, s.user_id, s.technique_id, s.status, s.target_duration_sec,
           s.elapsed_sec, s.cycles_completed, s.accuracy_pct, s.phase_snapshot,
           s.started_at, s.completed_at, s.updated_at,
           t.slug AS technique_slug, t.name AS technique_name, t.plant_key AS technique_plant_key
    FROM breathing_sessions s
    JOIN techniques t ON t.id = s.technique_id
"""


def fetch_user(cur, user_id):
    cur.execute(
        "SELECT id, public_id, display_name, email, created_at FROM users WHERE public_id = %s",
        (parse_uuid(user_id, "user_id"),),
    )
    row = cur.fetchone()
    if not row:
        raise ApiError(404, "User not found.")
    return row


def fetch_technique(cur, ref, *, active_only=False):
    """Look up a technique by numeric id or by slug."""
    ref = str(ref).strip().lower()
    if ref.isdigit():
        where, param = "id = %s", int(ref)
    elif SLUG_RE.match(ref):
        where, param = "slug = %s", ref
    else:
        raise ApiError(400, "Technique must be referenced by its numeric id or slug.")
    sql = f"SELECT {TECHNIQUE_COLUMNS} FROM techniques WHERE {where}"
    if active_only:
        sql += " AND is_active = 1"
    cur.execute(sql, (param,))
    row = cur.fetchone()
    if not row:
        raise ApiError(404, "Technique not found.")
    return row


def load_phases(cur, technique_ids):
    result = {tid: [] for tid in technique_ids}
    if not technique_ids:
        return result
    placeholders = ", ".join(["%s"] * len(technique_ids))
    cur.execute(
        f"""SELECT technique_id, step_order, phase, duration_sec FROM technique_phases
            WHERE technique_id IN ({placeholders}) ORDER BY technique_id, step_order""",
        tuple(technique_ids),
    )
    for r in cur.fetchall():
        result[r["technique_id"]].append(
            {"step": r["step_order"], "phase": r["phase"], "duration_sec": num(r["duration_sec"])}
        )
    return result


def validate_phases(raw):
    if not isinstance(raw, list) or not 2 <= len(raw) <= 8:
        raise ApiError(400, "'phases' must be a list of 2 to 8 steps.")
    cleaned = []
    for i, item in enumerate(raw, start=1):
        if not isinstance(item, dict):
            raise ApiError(400, f"phases[{i}] must be an object.")
        if item.get("phase") not in PHASE_TYPES:
            raise ApiError(400, f"phases[{i}].phase must be one of: {', '.join(PHASE_TYPES)}.")
        duration = get_number(item, "duration_sec", required=True, min_value=0.5, max_value=60)
        cleaned.append((i, item["phase"], duration))
    kinds = {phase for _, phase, _ in cleaned}
    if "inhale" not in kinds or "exhale" not in kinds:
        raise ApiError(400, "'phases' must include at least one inhale and one exhale.")
    return cleaned


def insert_phases(cur, technique_id, phases):
    cur.executemany(
        "INSERT INTO technique_phases (technique_id, step_order, phase, duration_sec) VALUES (%s, %s, %s, %s)",
        [(technique_id, step, phase, duration) for step, phase, duration in phases],
    )


def technique_response(cur, technique_id):
    row = fetch_technique(cur, technique_id)
    return technique_json(row, load_phases(cur, [row["id"]])[row["id"]])


def fetch_session(cur, user_row, session_id, *, for_update=False):
    sql = SESSION_SELECT + " WHERE s.public_id = %s AND s.user_id = %s"
    if for_update:
        sql += " FOR UPDATE"
    cur.execute(sql, (parse_uuid(session_id, "session_id"), user_row["id"]))
    row = cur.fetchone()
    if not row:
        raise ApiError(404, "Session not found.")
    return row


def set_last_session(cur, user_db_id, session_db_id, technique_id):
    cur.execute(
        """
        INSERT INTO user_last_session (user_id, session_id, technique_id) VALUES (%s, %s, %s)
        ON DUPLICATE KEY UPDATE session_id = VALUES(session_id),
                                technique_id = VALUES(technique_id),
                                updated_at = CURRENT_TIMESTAMP
        """,
        (user_db_id, session_db_id, technique_id),
    )


def compute_streak(days_desc, today):
    """days_desc: distinct practice dates, newest first. Streak survives until end of the next day."""
    if not days_desc:
        return 0
    expected = today if days_desc[0] == today else today - timedelta(days=1)
    streak = 0
    for d in days_desc:
        if d == expected:
            streak += 1
            expected -= timedelta(days=1)
        elif d < expected:
            break
    return streak


# --------------------------------------------------------------------------
# Health (public)
# --------------------------------------------------------------------------
@app.get("/health")
@app.get("/api/health")
def health():
    cur = db().cursor()
    cur.execute("SELECT 1 AS ok")
    return jsonify(status="ok")


# --------------------------------------------------------------------------
# Signed-in user
# --------------------------------------------------------------------------
@app.get("/api/me")
@login_required
def get_me():
    """Call right after sign-in: the returned id is the <user_id> for all /api/users/... routes."""
    return jsonify(user=user_json(g.user))


# --------------------------------------------------------------------------
# 1 & 2. Techniques and their phase timings (reading is public, changing is admin)
# --------------------------------------------------------------------------
@app.get("/api/techniques")
def list_techniques():
    include_inactive = request.args.get("include_inactive", "false").lower() == "true"
    cur = db().cursor()
    sql = f"SELECT {TECHNIQUE_COLUMNS} FROM techniques"
    if not include_inactive:
        sql += " WHERE is_active = 1"
    cur.execute(sql + " ORDER BY sort_order, name")
    rows = cur.fetchall()
    phases = load_phases(cur, [r["id"] for r in rows])
    return jsonify(techniques=[technique_json(r, phases[r["id"]]) for r in rows])


@app.get("/api/techniques/<ref>")
def get_technique(ref):
    return jsonify(technique=technique_response(db().cursor(), ref))


@app.post("/api/techniques")
def create_technique():
    require_admin()
    data = json_body()
    slug = get_str(data, "slug", required=True, max_len=64).lower()
    if not SLUG_RE.match(slug) or slug.isdigit():
        raise ApiError(400, "'slug' must be lowercase words joined by hyphens, e.g. 'box-breathing'.")
    name = get_str(data, "name", required=True, max_len=100)
    description = get_str(data, "description", max_len=2000)
    default_duration = get_int(data, "default_duration_sec", required=True, min_value=30, max_value=MAX_SESSION_SEC)
    plant_key = get_str(data, "plant_key", max_len=32)
    sort_order = get_int(data, "sort_order", default=0, min_value=0, max_value=100000)
    phases = validate_phases(data.get("phases"))

    conn = db()
    cur = conn.cursor()
    try:
        cur.execute(
            """INSERT INTO techniques (slug, name, description, default_duration_sec, plant_key, sort_order)
               VALUES (%s, %s, %s, %s, %s, %s)""",
            (slug, name, description, default_duration, plant_key, sort_order),
        )
    except pymysql.err.IntegrityError as e:
        if e.args[0] == DUPLICATE_KEY:
            raise ApiError(409, "A technique with this slug already exists.")
        raise
    technique_id = cur.lastrowid
    insert_phases(cur, technique_id, phases)
    conn.commit()
    return jsonify(technique=technique_response(cur, technique_id)), 201


@app.patch("/api/techniques/<ref>")
def update_technique(ref):
    require_admin()
    data = json_body()
    conn = db()
    cur = conn.cursor()
    technique = fetch_technique(cur, ref)

    updates = {}
    if "name" in data:
        updates["name"] = get_str(data, "name", required=True, max_len=100)
    if "description" in data:
        updates["description"] = get_str(data, "description", max_len=2000)
    if "default_duration_sec" in data:
        updates["default_duration_sec"] = get_int(
            data, "default_duration_sec", required=True, min_value=30, max_value=MAX_SESSION_SEC)
    if "plant_key" in data:
        updates["plant_key"] = get_str(data, "plant_key", max_len=32)
    if "sort_order" in data:
        updates["sort_order"] = get_int(data, "sort_order", required=True, min_value=0, max_value=100000)
    if "is_active" in data:
        if not isinstance(data["is_active"], bool):
            raise ApiError(400, "'is_active' must be true or false.")
        updates["is_active"] = int(data["is_active"])
    if not updates:
        raise ApiError(400, "Nothing to update.")

    set_clause = ", ".join(f"{col} = %s" for col in updates)  # keys come from the fixed list above
    cur.execute(f"UPDATE techniques SET {set_clause} WHERE id = %s", (*updates.values(), technique["id"]))
    conn.commit()
    return jsonify(technique=technique_response(cur, technique["id"]))


@app.put("/api/techniques/<ref>/phases")
def replace_phases(ref):
    """Replace a technique's phase timings. Past sessions keep their own snapshot, so history is unaffected."""
    require_admin()
    phases = validate_phases(json_body().get("phases"))
    conn = db()
    cur = conn.cursor()
    technique = fetch_technique(cur, ref)
    cur.execute("DELETE FROM technique_phases WHERE technique_id = %s", (technique["id"],))
    insert_phases(cur, technique["id"], phases)
    conn.commit()  # delete + insert land together or not at all
    return jsonify(technique=technique_response(cur, technique["id"]))


# --------------------------------------------------------------------------
# 3. Users
# --------------------------------------------------------------------------
@app.post("/api/users")
def create_user():
    """Admin only now: normal users are created by signing in with Google."""
    require_admin()
    data = json_body()
    display_name = get_str(data, "display_name", required=True, max_len=100)
    email = get_str(data, "email", max_len=255)
    if email:
        email = email.lower()
        if not EMAIL_RE.match(email):
            raise ApiError(400, "'email' is not a valid email address.")

    conn = db()
    cur = conn.cursor()
    public_id = str(uuid.uuid4())
    try:
        cur.execute(
            "INSERT INTO users (public_id, display_name, email) VALUES (%s, %s, %s)",
            (public_id, display_name, email),
        )
    except pymysql.err.IntegrityError as e:
        if e.args[0] == DUPLICATE_KEY:
            raise ApiError(409, "A user with this email already exists.")
        raise
    conn.commit()
    return jsonify(user=user_json(fetch_user(cur, public_id))), 201


@app.get("/api/users/<user_id>")
@login_required
def get_user(user_id):
    return jsonify(user=user_json(own_user(user_id)))


# --------------------------------------------------------------------------
# 4. Sessions (every exercise a user starts or completes)
# --------------------------------------------------------------------------
@app.post("/api/users/<user_id>/sessions")
@login_required
def create_session(user_id):
    """Start a session (status in_progress, the default) or log an already-finished one (status completed).

    Starting a new in-progress session abandons any other in-progress session for the
    user, so "Redo" never leaves a half-finished session behind.
    """
    data = json_body()
    conn = db()
    cur = conn.cursor()
    user = own_user(user_id)

    if data.get("technique") is None:
        raise ApiError(400, "'technique' (id or slug) is required.")
    technique = fetch_technique(cur, data["technique"], active_only=True)
    phases = load_phases(cur, [technique["id"]])[technique["id"]]
    if not phases:
        raise ApiError(409, "This technique has no phases configured.")

    status = data.get("status", "in_progress")
    if status not in ("in_progress", "completed"):
        raise ApiError(400, "'status' must be 'in_progress' or 'completed' when creating a session.")
    target = get_int(data, "target_duration_sec", default=technique["default_duration_sec"],
                     min_value=30, max_value=MAX_SESSION_SEC)
    elapsed = get_int(data, "elapsed_sec", default=0, min_value=0, max_value=MAX_SESSION_SEC)
    cycles = get_int(data, "cycles_completed", default=0, min_value=0, max_value=10000)
    accuracy = get_number(data, "accuracy_pct", min_value=0, max_value=100)
    started_at = parse_timestamp(data.get("started_at"), "started_at") or utc_now()
    completed_at = None
    if status == "completed":
        completed_at = parse_timestamp(data.get("completed_at"), "completed_at") or utc_now()
        if completed_at < started_at:
            raise ApiError(400, "'completed_at' cannot be before 'started_at'.")

    snapshot = json.dumps([{"phase": p["phase"], "duration_sec": p["duration_sec"]} for p in phases])

    if status == "in_progress":
        cur.execute(
            "UPDATE breathing_sessions SET status = 'abandoned' WHERE user_id = %s AND status = 'in_progress'",
            (user["id"],),
        )
    public_id = str(uuid.uuid4())
    cur.execute(
        """
        INSERT INTO breathing_sessions
            (public_id, user_id, technique_id, status, target_duration_sec, elapsed_sec,
             cycles_completed, accuracy_pct, phase_snapshot, started_at, completed_at)
        VALUES (%s, %s, %s, %s, %s, %s, %s, %s, %s, %s, %s)
        """,
        (public_id, user["id"], technique["id"], status, target, elapsed,
         cycles, accuracy, snapshot, started_at, completed_at),
    )
    set_last_session(cur, user["id"], cur.lastrowid, technique["id"])
    conn.commit()
    return jsonify(session=session_json(fetch_session(cur, user, public_id))), 201


@app.patch("/api/users/<user_id>/sessions/<session_id>")
@login_required
def update_session(user_id, session_id):
    """Save progress on an in-progress session, or finish it (completed / abandoned)."""
    data = json_body()
    conn = db()
    cur = conn.cursor()
    user = own_user(user_id)
    row = fetch_session(cur, user, session_id, for_update=True)
    if row["status"] != "in_progress":
        raise ApiError(409, f"Only in-progress sessions can be updated; this one is {row['status']}.")

    updates = {}
    elapsed = get_int(data, "elapsed_sec", min_value=0, max_value=MAX_SESSION_SEC)
    if elapsed is not None:
        if elapsed < row["elapsed_sec"]:
            raise ApiError(400, "'elapsed_sec' cannot go backwards.")
        updates["elapsed_sec"] = elapsed
    cycles = get_int(data, "cycles_completed", min_value=0, max_value=10000)
    if cycles is not None:
        updates["cycles_completed"] = cycles
    accuracy = get_number(data, "accuracy_pct", min_value=0, max_value=100)
    if accuracy is not None:
        updates["accuracy_pct"] = accuracy

    status = data.get("status")
    if status is not None:
        if status not in SESSION_STATUSES:
            raise ApiError(400, f"'status' must be one of: {', '.join(SESSION_STATUSES)}.")
        updates["status"] = status
        if status == "completed":
            completed_at = parse_timestamp(data.get("completed_at"), "completed_at") or utc_now()
            if completed_at < row["started_at"]:
                raise ApiError(400, "'completed_at' cannot be before 'started_at'.")
            updates["completed_at"] = completed_at
    if not updates:
        raise ApiError(400, "Nothing to update.")

    set_clause = ", ".join(f"{col} = %s" for col in updates)  # keys come from the fixed list above
    cur.execute(f"UPDATE breathing_sessions SET {set_clause} WHERE id = %s", (*updates.values(), row["id"]))
    set_last_session(cur, user["id"], row["id"], row["technique_id"])
    conn.commit()
    return jsonify(session=session_json(fetch_session(cur, user, session_id)))


@app.get("/api/users/<user_id>/sessions")
@login_required
def list_sessions(user_id):
    """History. Filters: ?status=completed&technique=box-breathing&limit=20&offset=0"""
    cur = db().cursor()
    user = own_user(user_id)
    limit = query_int("limit", 20, 1, 100)
    offset = query_int("offset", 0, 0, 1_000_000)

    where, params = ["s.user_id = %s"], [user["id"]]
    status = request.args.get("status")
    if status:
        if status not in SESSION_STATUSES:
            raise ApiError(400, f"'status' must be one of: {', '.join(SESSION_STATUSES)}.")
        where.append("s.status = %s")
        params.append(status)
    if request.args.get("technique"):
        where.append("s.technique_id = %s")
        params.append(fetch_technique(cur, request.args["technique"])["id"])
    where_sql = " AND ".join(where)  # only fixed fragments, values go in params

    cur.execute(f"SELECT COUNT(*) AS n FROM breathing_sessions s WHERE {where_sql}", tuple(params))
    total = cur.fetchone()["n"]
    cur.execute(
        f"{SESSION_SELECT} WHERE {where_sql} ORDER BY s.started_at DESC, s.id DESC LIMIT %s OFFSET %s",
        (*params, limit, offset),
    )
    return jsonify(total=total, limit=limit, offset=offset,
                   sessions=[session_json(r) for r in cur.fetchall()])


@app.get("/api/users/<user_id>/sessions/<session_id>")
@login_required
def get_session(user_id, session_id):
    cur = db().cursor()
    user = own_user(user_id)
    return jsonify(session=session_json(fetch_session(cur, user, session_id)))


# --------------------------------------------------------------------------
# 5. Last session ("Continue last session" card)
# --------------------------------------------------------------------------
@app.get("/api/users/<user_id>/last-session")
@login_required
def get_last_session(user_id):
    cur = db().cursor()
    user = own_user(user_id)
    cur.execute(SESSION_SELECT + " JOIN user_last_session l ON l.session_id = s.id WHERE l.user_id = %s",
                (user["id"],))
    row = cur.fetchone()
    if not row:
        return jsonify(last_session=None)
    return jsonify(last_session={**session_json(row), "can_continue": row["status"] == "in_progress"})


@app.put("/api/users/<user_id>/last-session")
@login_required
def put_last_session(user_id):
    """Point the card at a specific session. Body: {"session_id": "<uuid>"}."""
    data = json_body()
    conn = db()
    cur = conn.cursor()
    user = own_user(user_id)
    if data.get("session_id") is None:
        raise ApiError(400, "'session_id' is required.")
    row = fetch_session(cur, user, data["session_id"])
    set_last_session(cur, user["id"], row["id"], row["technique_id"])
    conn.commit()
    return jsonify(last_session={**session_json(row), "can_continue": row["status"] == "in_progress"})


@app.delete("/api/users/<user_id>/last-session")
@login_required
def delete_last_session(user_id):
    """Hide the card. Only removes the pointer; the session itself stays in history."""
    conn = db()
    cur = conn.cursor()
    user = own_user(user_id)
    cur.execute("DELETE FROM user_last_session WHERE user_id = %s", (user["id"],))
    conn.commit()
    return "", 204


# --------------------------------------------------------------------------
# Home screen data
# --------------------------------------------------------------------------
@app.get("/api/users/<user_id>/techniques")
@login_required
def list_user_techniques(user_id):
    """Return all active techniques with this user's plant progress."""
    cur = db().cursor()
    user = own_user(user_id)
    cur.execute(
        f"SELECT {TECHNIQUE_COLUMNS} FROM techniques "
        "WHERE is_active = 1 ORDER BY sort_order, name"
    )
    rows = cur.fetchall()
    phases = load_phases(cur, [r["id"] for r in rows])

    cur.execute(
        """SELECT technique_id, COUNT(*) AS n, MAX(completed_at) AS last_completed_at
           FROM breathing_sessions
           WHERE user_id = %s AND status = 'completed'
           GROUP BY technique_id""",
        (user["id"],),
    )
    counts = {r["technique_id"]: r for r in cur.fetchall()}

    result = []
    for r in rows:
        c = counts.get(r["id"])
        progress = plant_progress(c["n"] if c else 0)
        progress["last_completed_at"] = iso(c["last_completed_at"]) if c else None
        result.append({
            **technique_json(r, phases[r["id"]]),
            "progress": progress,
        })

    return jsonify(techniques=result)


@app.get("/api/users/<user_id>/plants")
@login_required
def list_user_plants(user_id):
    """Return only plants collected by this user, with their technique details."""
    cur = db().cursor()
    user = own_user(user_id)

    cur.execute(
        f"""SELECT {TECHNIQUE_COLUMNS}
            FROM techniques
            WHERE is_active = 1 AND plant_key IS NOT NULL
            ORDER BY sort_order, name"""
    )
    rows = cur.fetchall()
    phases = load_phases(cur, [r["id"] for r in rows])

    cur.execute(
        """SELECT technique_id, COUNT(*) AS n, MAX(completed_at) AS last_completed_at
           FROM breathing_sessions
           WHERE user_id = %s AND status = 'completed'
           GROUP BY technique_id""",
        (user["id"],),
    )
    counts = {r["technique_id"]: r for r in cur.fetchall()}

    plants = []
    for r in rows:
        c = counts.get(r["id"])
        completed_count = c["n"] if c else 0

        # A plant is collected after at least one completed session.
        if completed_count == 0:
            continue

        progress = plant_progress(completed_count)
        progress["last_completed_at"] = iso(c["last_completed_at"])
        plants.append({
            **technique_json(r, phases[r["id"]]),
            "progress": progress,
        })

    return jsonify(plants=plants)

@app.get("/api/users/<user_id>/summary")
@login_required
def user_summary(user_id):
    """Streak and totals for the header. Days are counted in UTC for now."""
    cur = db().cursor()
    user = own_user(user_id)
    cur.execute(
        """SELECT DISTINCT DATE(completed_at) AS d FROM breathing_sessions
           WHERE user_id = %s AND status = 'completed' ORDER BY d DESC LIMIT 1000""",
        (user["id"],),
    )
    days = [r["d"] for r in cur.fetchall()]
    today = utc_now().date()
    cur.execute(
        """SELECT COUNT(*) AS sessions, COALESCE(SUM(elapsed_sec), 0) AS seconds, AVG(accuracy_pct) AS avg_acc
           FROM breathing_sessions WHERE user_id = %s AND status = 'completed'""",
        (user["id"],),
    )
    totals = cur.fetchone()
    return jsonify(
        user=user_json(user),
        current_streak_days=compute_streak(days, today),
        practiced_today=bool(days) and days[0] == today,
        total_completed_sessions=totals["sessions"],
        total_practice_sec=num(totals["seconds"]),
        average_accuracy_pct=num(totals["avg_acc"]),
    )


# --------------------------------------------------------------------------
# Band readings
# --------------------------------------------------------------------------
def _phase_at_elapsed(phases, elapsed_ms):
    """Return the guided phase expected at a session-relative time."""
    cycle_ms = sum(float(p["duration_sec"]) for p in phases) * 1000
    if cycle_ms <= 0:
        raise ApiError(409, "The session has no valid breathing cycle.")

    position = elapsed_ms % cycle_ms
    for phase in phases:
        duration_ms = float(phase["duration_sec"]) * 1000
        if position < duration_ms:
            return phase["phase"]
        position -= duration_ms
    return phases[-1]["phase"]


def _clean_band_reading(item, index):
    if not isinstance(item, dict):
        raise ApiError(400, f"readings[{index}] must be an object.")

    elapsed_ms = item.get("elapsed_ms")
    if isinstance(elapsed_ms, bool) or not isinstance(elapsed_ms, int):
        raise ApiError(400, f"readings[{index}].elapsed_ms must be an integer.")
    if not 0 <= elapsed_ms <= MAX_SESSION_SEC * 1000:
        raise ApiError(400, f"readings[{index}].elapsed_ms is outside the session limit.")

    detected_phase = item.get("detected_phase")
    if detected_phase is not None and detected_phase not in PHASE_TYPES:
        raise ApiError(400, f"readings[{index}].detected_phase must be one of: {', '.join(PHASE_TYPES)}.")

    confidence = item.get("confidence")
    if confidence is not None:
        if (isinstance(confidence, bool) or not isinstance(confidence, (int, float))
                or not math.isfinite(confidence) or not 0 <= confidence <= 1):
            raise ApiError(400, f"readings[{index}].confidence must be a number from 0 to 1.")
        confidence = round(float(confidence), 4)

    sensors = item.get("sensors", {})
    if not isinstance(sensors, dict) or len(sensors) > MAX_SENSOR_FIELDS:
        raise ApiError(400, f"readings[{index}].sensors must be an object with at most {MAX_SENSOR_FIELDS} fields.")

    clean_sensors = {}
    for key, value in sensors.items():
        if not isinstance(key, str) or not key or len(key) > 40:
            raise ApiError(400, f"readings[{index}] contains an invalid sensor field name.")
        if isinstance(value, bool) or not isinstance(value, (int, float)) or not math.isfinite(value):
            raise ApiError(400, f"readings[{index}].sensors.{key} must be a finite number.")
        clean_sensors[key] = float(value)

    return {
        "elapsed_ms": elapsed_ms,
        "detected_phase": detected_phase,
        "confidence": confidence,
        "sensors": clean_sensors,
    }


@app.post("/api/users/<user_id>/sessions/<session_id>/readings")
@login_required
def receive_band_readings(user_id, session_id):
    """Receive a batch of decoded BLE readings.

    Body: {"readings": [{"elapsed_ms": 1200, "detected_phase": "inhale",
                         "confidence": 0.91, "sensors": {"flex": 512}}]}

    `detected_phase` must come from the ESP32 firmware or the app's signal processing.
    """
    data = json_body()
    raw_readings = data.get("readings")
    if not isinstance(raw_readings, list) or not 1 <= len(raw_readings) <= MAX_READINGS_PER_REQUEST:
        raise ApiError(400, f"'readings' must be a list containing 1 to {MAX_READINGS_PER_REQUEST} items.")

    readings = [_clean_band_reading(item, i) for i, item in enumerate(raw_readings)]
    if any(readings[i]["elapsed_ms"] <= readings[i - 1]["elapsed_ms"] for i in range(1, len(readings))):
        raise ApiError(400, "readings must have strictly increasing elapsed_ms values.")

    conn = db()
    cur = conn.cursor()
    user = own_user(user_id)
    session = fetch_session(cur, user, session_id, for_update=True)
    if session["status"] != "in_progress":
        raise ApiError(409, "Band readings can only be added to an in-progress session.")

    phases = load_snapshot(session["phase_snapshot"])

    rows = []
    for reading in readings:
        expected = _phase_at_elapsed(phases, reading["elapsed_ms"])
        detected = reading["detected_phase"]
        matched = int(detected is not None and detected == expected)
        rows.append((
            session["id"],
            reading["elapsed_ms"],
            detected,
            reading["confidence"],
            json.dumps(reading["sensors"], separators=(",", ":")),
            expected,
            matched,
        ))

    # INSERT IGNORE makes retries safe: a sample is unique per session/time.
    cur.executemany(
        """
        INSERT IGNORE INTO breathing_session_readings
            (session_id, elapsed_ms, detected_phase, confidence,
             sensor_data, expected_phase, phase_matched)
        VALUES (%s, %s, %s, %s, %s, %s, %s)
        """,
        rows,
    )
    inserted = cur.rowcount

    cur.execute(
        """
        SELECT COUNT(*) AS total,
               COALESCE(SUM(phase_matched), 0) AS matched,
               MAX(elapsed_ms) AS latest_elapsed_ms
        FROM breathing_session_readings
        WHERE session_id = %s AND detected_phase IS NOT NULL
        """,
        (session["id"],),
    )
    stats = cur.fetchone()
    total = stats["total"]
    accuracy = round((stats["matched"] / total) * 100, 2) if total else None

    updates, params = [], []
    if accuracy is not None:
        updates.append("accuracy_pct = %s")
        params.append(accuracy)
    if stats["latest_elapsed_ms"] is not None:
        updates.append("elapsed_sec = GREATEST(elapsed_sec, %s)")
        params.append(int(stats["latest_elapsed_ms"] // 1000))
    if updates:
        cur.execute(
            f"UPDATE breathing_sessions SET {', '.join(updates)} WHERE id = %s",  # fixed fragments only
            (*params, session["id"]),
        )

    conn.commit()
    return jsonify(
        accepted=inserted,
        duplicates=len(readings) - inserted,
        accuracy_pct=accuracy,
        samples_compared=total,
        samples_matched=stats["matched"],
        latest_elapsed_ms=stats["latest_elapsed_ms"],
    ), 202


@app.get("/api/users/<user_id>/sessions/<session_id>/live")
@login_required
def get_live_session_state(user_id, session_id):
    """Data needed to refresh the live exercise screen."""
    cur = db().cursor()
    user = own_user(user_id)
    session = fetch_session(cur, user, session_id)

    cur.execute(
        """
        SELECT elapsed_ms, detected_phase, confidence, sensor_data, expected_phase, received_at
        FROM breathing_session_readings
        WHERE session_id = %s
        ORDER BY elapsed_ms DESC
        LIMIT 1
        """,
        (session["id"],),
    )
    latest = cur.fetchone()

    cur.execute(
        """
        SELECT COUNT(*) AS total, COALESCE(SUM(phase_matched), 0) AS matched
        FROM breathing_session_readings
        WHERE session_id = %s AND detected_phase IS NOT NULL
        """,
        (session["id"],),
    )
    stats = cur.fetchone()
    accuracy = round(stats["matched"] / stats["total"] * 100, 2) if stats["total"] else None

    latest_json = None
    if latest:
        latest_json = {
            "elapsed_ms": latest["elapsed_ms"],
            "detected_phase": latest["detected_phase"],
            "expected_phase": latest["expected_phase"],
            "confidence": float(latest["confidence"]) if latest["confidence"] is not None else None,
            "sensors": load_snapshot(latest["sensor_data"]),
            "received_at": iso(latest["received_at"]),
        }

    return jsonify(
        session=session_json(session),
        band={
            "connected": latest is not None,
            "latest_reading": latest_json,
            "samples_compared": stats["total"],
            "samples_matched": stats["matched"],
            "accuracy_pct": accuracy,
        },
    )


# --------------------------------------------------------------------------
# Statistics page
# --------------------------------------------------------------------------
def _statistics_period(period):
    """Return UTC [start, end) bounds and the chart bucket format."""
    now = utc_now()
    today = now.date()

    if period == "day":
        start = datetime.combine(today, datetime.min.time())
        bucket = "hour"
    elif period == "week":
        start = datetime.combine(today - timedelta(days=today.weekday()), datetime.min.time())
        bucket = "day"
    elif period == "month":
        start = datetime(today.year, today.month, 1)
        bucket = "day"
    elif period == "year":
        start = datetime(today.year, 1, 1)
        bucket = "month"
    else:
        raise ApiError(400, "'period' must be one of: day, week, month, year.")

    return start, now, bucket


def _average(values):
    values = [float(v) for v in values if v is not None]
    return round(sum(values) / len(values), 2) if values else None


@app.get("/api/users/<user_id>/statistics")
@login_required
def user_statistics(user_id):
    """Statistics page data. Query: ?period=day|week|month|year

    Reads from MySQL only. step_count and calories_burned are treated as cumulative
    daily counters: the day's maximum is used, so repeated snapshots aren't double-counted.
    """
    cur = db().cursor()
    user = own_user(user_id)

    period = request.args.get("period", "week").lower()
    start, end, bucket_type = _statistics_period(period)

    cur.execute(
        """
        SELECT recorded_at, heart_rate_bpm, blood_oxygen_pct, hrv_ms,
               stress_level, step_count, calories_burned, wrist_tilt,
               activity_state
        FROM user_health_readings
        WHERE user_id = %s AND recorded_at >= %s AND recorded_at < %s
        ORDER BY recorded_at ASC
        """,
        (user["id"], start, end),
    )
    readings = cur.fetchall()

    buckets = {}
    daily_totals = {}
    for row in readings:
        recorded = row["recorded_at"]
        if bucket_type == "hour":
            key = recorded.strftime("%H:00")
        elif bucket_type == "month":
            key = recorded.strftime("%Y-%m")
        else:
            key = recorded.date().isoformat()
        daily_key = recorded.date().isoformat()

        bucket = buckets.setdefault(key, {
            "heart_rate_values": [],
            "blood_oxygen_values": [],
            "hrv_values": [],
            "stress_values": [],
            "wrist_tilt_values": [],
            "step_count": None,
            "calories_burned": None,
        })

        for source, target in (
            ("heart_rate_bpm", "heart_rate_values"),
            ("blood_oxygen_pct", "blood_oxygen_values"),
            ("hrv_ms", "hrv_values"),
            ("stress_level", "stress_values"),
            ("wrist_tilt", "wrist_tilt_values"),
        ):
            if row[source] is not None:
                bucket[target].append(row[source])

        if row["step_count"] is not None:
            bucket["step_count"] = max(bucket["step_count"] or 0, int(row["step_count"]))
        if row["calories_burned"] is not None:
            bucket["calories_burned"] = max(bucket["calories_burned"] or 0, float(row["calories_burned"]))

        day_total = daily_totals.setdefault(daily_key, {"steps": 0, "calories": 0.0})
        if row["step_count"] is not None:
            day_total["steps"] = max(day_total["steps"], int(row["step_count"]))
        if row["calories_burned"] is not None:
            day_total["calories"] = max(day_total["calories"], float(row["calories_burned"]))

    chart = []
    for label, values in buckets.items():
        chart.append({
            "label": label,
            "heart_rate_bpm": _average(values["heart_rate_values"]),
            "blood_oxygen_pct": _average(values["blood_oxygen_values"]),
            "hrv_ms": _average(values["hrv_values"]),
            "stress_level": _average(values["stress_values"]),
            "step_count": values["step_count"],
            "calories_burned": round(values["calories_burned"], 2)
                if values["calories_burned"] is not None else None,
            "wrist_tilt": _average(values["wrist_tilt_values"]),
        })

    latest_reading = readings[-1] if readings else None
    total_steps = sum(v["steps"] for v in daily_totals.values())
    total_calories = round(sum(v["calories"] for v in daily_totals.values()), 2)

    cur.execute(
        """
        SELECT COUNT(*) AS exercises_done,
               COALESCE(SUM(elapsed_sec), 0) AS total_seconds,
               COUNT(DISTINCT technique_id) AS collectibles,
               COALESCE(SUM(cycles_completed), 0) AS cycles_completed,
               AVG(accuracy_pct) AS average_accuracy_pct
        FROM breathing_sessions
        WHERE user_id = %s AND status = 'completed'
          AND completed_at >= %s AND completed_at < %s
        """,
        (user["id"], start, end),
    )
    session_totals = cur.fetchone()

    cur.execute(
        """
        SELECT DATE(completed_at) AS activity_date,
               COUNT(*) AS exercises_done,
               COALESCE(SUM(elapsed_sec), 0) AS total_seconds
        FROM breathing_sessions
        WHERE user_id = %s AND status = 'completed'
          AND completed_at >= %s AND completed_at < %s
        GROUP BY DATE(completed_at)
        ORDER BY activity_date
        """,
        (user["id"], start, end),
    )
    breathing_activity = [
        {
            "date": row["activity_date"].isoformat(),
            "exercises_done": int(row["exercises_done"]),
            "total_seconds": int(row["total_seconds"]),
        }
        for row in cur.fetchall()
    ]

    latest_health = None
    if latest_reading:
        latest_health = {
            "recorded_at": iso(latest_reading["recorded_at"]),
            "heart_rate_bpm": num(latest_reading["heart_rate_bpm"]),
            "blood_oxygen_pct": num(latest_reading["blood_oxygen_pct"]),
            "hrv_ms": num(latest_reading["hrv_ms"]),
            "stress_level": num(latest_reading["stress_level"]),
            "step_count": latest_reading["step_count"],
            "calories_burned": num(latest_reading["calories_burned"]),
            "wrist_tilt": num(latest_reading["wrist_tilt"]),
            "activity_state": latest_reading["activity_state"],
        }

    return jsonify(
        user_id=user["public_id"],
        period=period,
        range={"start": iso(start), "end": iso(end), "timezone": "UTC"},
        summary={
            "heart_rate_bpm": _average(r["heart_rate_bpm"] for r in readings),
            "blood_oxygen_pct": _average(r["blood_oxygen_pct"] for r in readings),
            "hrv_ms": _average(r["hrv_ms"] for r in readings),
            "stress_level": _average(r["stress_level"] for r in readings),
            "steps": total_steps,
            "calories_burned": total_calories,
            "collectibles": int(session_totals["collectibles"]),
            "exercises_done": int(session_totals["exercises_done"]),
            "total_seconds": int(session_totals["total_seconds"]),
            "average_accuracy_pct": num(session_totals["average_accuracy_pct"]),
            "cycles_completed": int(session_totals["cycles_completed"]),
        },
        latest_health=latest_health,
        health_chart=chart,
        breathing_activity=breathing_activity,
    )

# ---------------------------------------------------------------------------
# PASTE INTO app.py, just above the "Run" block at the bottom.
# Needs no new imports: it uses what app.py already imports.
# ---------------------------------------------------------------------------

# --------------------------------------------------------------------------
# Band vitals: minute buckets in, period statistics out
# --------------------------------------------------------------------------
MAX_VITAL_BUCKETS = 200
KCAL_PER_STEP = 0.04  # rough active-calorie estimate; the band has no calorie sensor
STATS_PERIODS = ("day", "week", "month", "year")

# Fixed, whitelisted SQL fragments (never built from user input).
# The single %s is the timezone offset in minutes.
_LOCAL_TS = "DATE_ADD(bucket_start, INTERVAL %s MINUTE)"
_BUCKET_KEY_SQL = {
    "day": f"DATE_FORMAT({_LOCAL_TS}, '%%Y-%%m-%%d %%H')",
    "week": f"DATE_FORMAT({_LOCAL_TS}, '%%Y-%%m-%%d')",
    "month": f"DATE_FORMAT({_LOCAL_TS}, '%%Y-%%m-%%d')",
    "year": f"DATE_FORMAT({_LOCAL_TS}, '%%Y-%%m')",
}
_BUCKET_KEY_FMT = {"day": "%Y-%m-%d %H", "week": "%Y-%m-%d", "month": "%Y-%m-%d", "year": "%Y-%m"}


def _clean_vitals_bucket(item, index):
    if not isinstance(item, dict):
        raise ApiError(400, f"buckets[{index}] must be an object.")
    minute = parse_timestamp(item.get("minute"), "minute")
    if minute is None:
        raise ApiError(400, f"buckets[{index}].minute is required.")
    if minute.second:
        raise ApiError(400, f"buckets[{index}].minute must be aligned to a whole minute.")
    now = utc_now()
    if minute > now + timedelta(minutes=5) or minute < now - timedelta(days=30):
        raise ApiError(400, f"buckets[{index}].minute is outside the accepted window (last 30 days).")

    samples = get_int(item, "samples", required=True, min_value=1, max_value=1000)
    hr_avg = get_number(item, "hr_avg", required=True, min_value=20, max_value=250)
    hr_min = get_number(item, "hr_min", required=True, min_value=20, max_value=250)
    hr_max = get_number(item, "hr_max", required=True, min_value=20, max_value=250)
    spo2_avg = get_number(item, "spo2_avg", required=True, min_value=50, max_value=100)
    spo2_min = get_number(item, "spo2_min", required=True, min_value=50, max_value=100)
    steps = get_int(item, "steps_delta", default=0, min_value=0, max_value=20000)
    if not hr_min <= hr_avg <= hr_max:
        raise ApiError(400, f"buckets[{index}]: hr_min <= hr_avg <= hr_max must hold.")
    if spo2_min > spo2_avg:
        raise ApiError(400, f"buckets[{index}]: spo2_min cannot exceed spo2_avg.")
    demo = item.get("demo", False)
    if not isinstance(demo, bool):
        raise ApiError(400, f"buckets[{index}].demo must be true or false.")
    return (minute, samples, hr_avg, hr_min, hr_max, spo2_avg, spo2_min, steps, int(demo))


@app.post("/api/users/<user_id>/vitals")
@login_required
def ingest_vitals(user_id):
    """Store 1-minute buckets from the band. Safe to retry: a bucket is replaced, never added twice.

    Body: {"buckets": [{"minute": "2026-11-10T09:12:00Z", "samples": 120,
                        "hr_avg": 74.2, "hr_min": 68, "hr_max": 81,
                        "spo2_avg": 97.6, "spo2_min": 96.5,
                        "steps_delta": 14, "demo": true}]}
    """
    raw = json_body().get("buckets")
    if not isinstance(raw, list) or not 1 <= len(raw) <= MAX_VITAL_BUCKETS:
        raise ApiError(400, f"'buckets' must be a list of 1 to {MAX_VITAL_BUCKETS} items.")
    cleaned = [_clean_vitals_bucket(item, i) for i, item in enumerate(raw)]

    conn = db()
    cur = conn.cursor()
    user = own_user(user_id)
    cur.executemany(
        """
        INSERT INTO band_vitals_minutes
            (user_id, bucket_start, samples, hr_avg, hr_min, hr_max,
             spo2_avg, spo2_min, steps_delta, is_demo)
        VALUES (%s, %s, %s, %s, %s, %s, %s, %s, %s, %s)
        ON DUPLICATE KEY UPDATE
            samples = VALUES(samples), hr_avg = VALUES(hr_avg), hr_min = VALUES(hr_min),
            hr_max = VALUES(hr_max), spo2_avg = VALUES(spo2_avg), spo2_min = VALUES(spo2_min),
            steps_delta = VALUES(steps_delta), is_demo = VALUES(is_demo)
        """,
        [(user["id"], *row) for row in cleaned],
    )
    conn.commit()
    return jsonify(accepted=len(cleaned))


def _add_months(d, n):
    idx = d.year * 12 + (d.month - 1) + n
    return datetime(idx // 12, idx % 12 + 1, 1)


def _stats_window(period, offset_min, now_utc):
    """Returns (start_local, end_local, bucket_start_list) for the period, in the user's local time."""
    today = (now_utc + timedelta(minutes=offset_min)).replace(hour=0, minute=0, second=0, microsecond=0)
    if period == "day":
        start, end = today, today + timedelta(days=1)
        keys = [start + timedelta(hours=h) for h in range(24)]
    elif period in ("week", "month"):
        days = 7 if period == "week" else 30
        start, end = today - timedelta(days=days - 1), today + timedelta(days=1)
        keys = [start + timedelta(days=i) for i in range(days)]
    else:
        start = _add_months(today.replace(day=1), -11)
        end = _add_months(start, 12)
        keys = [_add_months(start, i) for i in range(12)]
    return start, end, keys


def _f1(value):
    return None if value is None else round(float(value), 1)


@app.get("/api/users/<user_id>/stats")
@login_required
def get_stats(user_id):
    """Everything the Statistics page needs for one period.

    ?period=day|week|month|year&tz_offset_min=330   (minutes east of UTC, e.g. India = 330)
    Missing hours/days are null in the series so the app can draw gaps instead of fake data.
    """
    cur = db().cursor()
    user = own_user(user_id)
    period = request.args.get("period", "week")
    if period not in STATS_PERIODS:
        raise ApiError(400, f"'period' must be one of: {', '.join(STATS_PERIODS)}.")
    offset = query_int("tz_offset_min", 0, -840, 840)

    start_local, end_local, keys = _stats_window(period, offset, utc_now())
    start_utc = start_local - timedelta(minutes=offset)
    end_utc = end_local - timedelta(minutes=offset)
    key_sql = _BUCKET_KEY_SQL[period]  # whitelisted constant

    # Whole-period summary
    cur.execute(
        f"""SELECT COALESCE(SUM(samples), 0) AS n,
                   SUM(hr_avg * samples) / SUM(samples) AS hr_avg,
                   MIN(hr_min) AS hr_min, MAX(hr_max) AS hr_max,
                   SUM(spo2_avg * samples) / SUM(samples) AS spo2_avg,
                   MIN(spo2_min) AS spo2_min,
                   COALESCE(SUM(steps_delta), 0) AS steps,
                   COUNT(DISTINCT DATE({_LOCAL_TS})) AS active_days,
                   COALESCE(MAX(is_demo), 0) AS demo,
                   MAX(bucket_start) AS last_at
            FROM band_vitals_minutes
            WHERE user_id = %s AND bucket_start >= %s AND bucket_start < %s""",
        (offset, user["id"], start_utc, end_utc),
    )
    s = cur.fetchone()

    # Per-bucket series
    cur.execute(
        f"""SELECT {key_sql} AS k,
                   SUM(samples) AS n,
                   SUM(hr_avg * samples) / SUM(samples) AS hr,
                   SUM(spo2_avg * samples) / SUM(samples) AS spo2,
                   SUM(steps_delta) AS steps
            FROM band_vitals_minutes
            WHERE user_id = %s AND bucket_start >= %s AND bucket_start < %s
            GROUP BY k""",
        (offset, user["id"], start_utc, end_utc),
    )
    by_key = {r["k"]: r for r in cur.fetchall()}
    fmt = _BUCKET_KEY_FMT[period]
    heart, spo2, steps, calories = [], [], [], []
    for k in keys:
        r = by_key.get(k.strftime(fmt))
        if r is None:
            heart.append(None); spo2.append(None); steps.append(None); calories.append(None)
        else:
            heart.append(_f1(r["hr"]))
            spo2.append(_f1(r["spo2"]))
            steps.append(int(r["steps"]))
            calories.append(round(int(r["steps"]) * KCAL_PER_STEP, 1))

    # Breathing tiles
    cur.execute(
        """SELECT COUNT(*) AS exercises, COALESCE(SUM(elapsed_sec), 0) AS seconds
           FROM breathing_sessions
           WHERE user_id = %s AND status = 'completed' AND completed_at >= %s AND completed_at < %s""",
        (user["id"], start_utc, end_utc),
    )
    b = cur.fetchone()
    # A plant is "collected" the first time a technique is completed.
    cur.execute(
        """SELECT COUNT(*) AS n FROM (
               SELECT technique_id, MIN(completed_at) AS first_at
               FROM breathing_sessions WHERE user_id = %s AND status = 'completed'
               GROUP BY technique_id
               HAVING first_at >= %s AND first_at < %s) x""",
        (user["id"], start_utc, end_utc),
    )
    collectibles = cur.fetchone()["n"]

    steps_total = int(s["steps"])
    active_days = int(s["active_days"])
    steps_avg = round(steps_total / active_days) if active_days else 0
    return jsonify(
        period=period,
        range_start=start_local.date().isoformat(),
        range_end=(end_local - timedelta(days=1)).date().isoformat(),
        tz_offset_min=offset,
        has_data=int(s["n"]) > 0,
        includes_demo=bool(s["demo"]),
        last_sample_at=iso(s["last_at"]),
        summary={
            "heart_rate": {"avg": _f1(s["hr_avg"]), "min": _f1(s["hr_min"]), "max": _f1(s["hr_max"])},
            "spo2": {"avg": _f1(s["spo2_avg"]), "min": _f1(s["spo2_min"])},
            "steps": {"total": steps_total, "daily_avg": steps_avg},
            "calories": {"total": round(steps_total * KCAL_PER_STEP, 1),
                         "daily_avg": round(steps_avg * KCAL_PER_STEP, 1), "estimated": True},
        },
        breathing={"exercises": b["exercises"], "collectibles": collectibles,
                   "total_sec": int(b["seconds"])},
        series={"heart_rate": heart, "spo2": spo2, "steps": steps, "calories": calories},
    )

# --------------------------------------------------------------------------
# Run (must stay at the very bottom of the file)
# --------------------------------------------------------------------------
if __name__ == "__main__":
    app.run(
        host=os.environ.get("HOST", "0.0.0.0"),
        port=int(os.environ.get("PORT", "5001")),
        debug=False,  # never enable on a networked server
    )