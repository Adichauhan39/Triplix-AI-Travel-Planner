"""
Triplix Travel Agent Server
CSV + MongoDB + Gemini AI + Google Cloud (Vertex AI)
"""
import os
from dotenv import load_dotenv

# Load environment variables from .env file
load_dotenv(override=True)

# ── Vertex AI / Gemini Configuration ────────────────────────────────────
# Supports two modes:
#   1. Vertex AI (recommended for hackathon): set GOOGLE_GENAI_USE_VERTEXAI=TRUE
#   2. Direct Gemini API (fallback): set GOOGLE_API_KEY

USE_VERTEX_AI = os.getenv('GOOGLE_GENAI_USE_VERTEXAI', 'FALSE').upper() == 'TRUE'
GOOGLE_CLOUD_PROJECT = os.getenv('GOOGLE_CLOUD_PROJECT', '')
GOOGLE_CLOUD_LOCATION = os.getenv('GOOGLE_CLOUD_LOCATION', 'us-central1')

if USE_VERTEX_AI:
    # ── Vertex AI Mode ──
    try:
        import vertexai
        from vertexai.generative_models import GenerativeModel, Part, GenerationConfig
        vertexai.init(project=GOOGLE_CLOUD_PROJECT, location=GOOGLE_CLOUD_LOCATION)
        print(f"[OK] Vertex AI initialized (project={GOOGLE_CLOUD_PROJECT}, location={GOOGLE_CLOUD_LOCATION})")

        # Create a compatibility shim so all existing genai.GenerativeModel() calls work
        class _GenaiCompat:
            """Shim that makes vertexai.GenerativeModel look like google.generativeai."""
            GenerativeModel = GenerativeModel
            @staticmethod
            def configure(**kwargs):
                pass  # No-op — Vertex AI uses service account auth
        genai = _GenaiCompat()
        _AI_MODE = "Vertex AI"
    except ImportError:
        print("[WARNING] google-cloud-aiplatform not installed — falling back to direct Gemini API")
        USE_VERTEX_AI = False

if not USE_VERTEX_AI:
    # ── Direct Gemini API Mode ──
    GOOGLE_API_KEY = os.getenv('GOOGLE_API_KEY')
    if not GOOGLE_API_KEY:
        raise ValueError("GOOGLE_API_KEY not found. Set it in .env, or use GOOGLE_GENAI_USE_VERTEXAI=TRUE for Vertex AI.")
    os.environ['GOOGLE_API_KEY'] = GOOGLE_API_KEY
    import google.generativeai as genai
    genai.configure(api_key=GOOGLE_API_KEY)
    _AI_MODE = "Gemini API"
    print(f"[OK] Gemini API configured (direct API key)")

from fastapi import FastAPI, Request
from fastapi.middleware.cors import CORSMiddleware
from pydantic import BaseModel
from typing import Dict, Any, Optional, List
from datetime import datetime, timedelta
import pandas as pd
import json
import requests
import random
import base64
import threading
import time
from concurrent.futures import ThreadPoolExecutor, TimeoutError as FuturesTimeoutError

# MongoDB was removed: the cluster it pointed at no longer exists, and every
# hotel search paid ~21s of DNS retries before falling through to the CSV data
# it actually served. Hotels come from CSV, and anything not covered there is
# handed off to Aviasales, so there was nothing left for a database to do.
# mongodb_layer.py is still on disk if it's ever wanted back.

# Configure
GOOGLE_PLACES_API_KEY = os.getenv('GOOGLE_PLACES_API_KEY', os.getenv('GOOGLE_API_KEY', ''))
OPENWEATHER_API_KEY = os.getenv('OPENWEATHER_API_KEY', '')
RECAPTCHA_SECRET_KEY = os.getenv('RECAPTCHA_SECRET_KEY', '')
RECAPTCHA_ALLOWED_HOSTS = [
    host.strip().lower()
    for host in os.getenv('RECAPTCHA_ALLOWED_HOSTS', '').split(',')
    if host.strip()
]
AMADEUS_CLIENT_ID = os.getenv('AMADEUS_CLIENT_ID', '')
AMADEUS_CLIENT_SECRET = os.getenv('AMADEUS_CLIENT_SECRET', '')
AMADEUS_HOST = os.getenv('AMADEUS_HOST', 'https://test.api.amadeus.com').rstrip('/')
USE_AMADEUS_HOTEL_PRICES = os.getenv('USE_AMADEUS_HOTEL_PRICES', 'TRUE').upper() == 'TRUE'
USE_AMADEUS_FLIGHTS = os.getenv('USE_AMADEUS_FLIGHTS', 'TRUE').upper() == 'TRUE'
DESTINATION_SUGGESTIONS_AI_ONLY = os.getenv('DESTINATION_SUGGESTIONS_AI_ONLY', 'FALSE').upper() == 'TRUE'
DESTINATION_SUGGESTIONS_USE_AI_FILL = os.getenv('DESTINATION_SUGGESTIONS_USE_AI_FILL', 'FALSE').upper() == 'TRUE'
_destination_suggestions_cache: Dict[str, Dict[str, Any]] = {}
_DESTINATION_CACHE_TTL_SECONDS = 300
_amadeus_token_cache: Dict[str, Any] = {'access_token': '', 'expires_at': 0}
hotels_df = pd.read_csv('data/hotels_india.csv')
flights_df = pd.read_csv('data/flights_india.csv')
destinations_df = pd.read_csv('data/destinations_india.csv')

# Load transportation data
try:
    trains_df = pd.read_csv('data/trains_india.csv')
except (FileNotFoundError, pd.errors.ParserError) as e:
    print(f"Warning: Could not load trains data: {e}")
    trains_df = pd.DataFrame()

try:
    buses_df = pd.read_csv('data/buses_india.csv')
except (FileNotFoundError, pd.errors.ParserError) as e:
    print(f"Warning: Could not load buses data: {e}")
    buses_df = pd.DataFrame()

try:
    cars_df = pd.read_csv('data/car_rentals_india.csv')
except (FileNotFoundError, pd.errors.ParserError) as e:
    print(f"Warning: Could not load car rentals data: {e}")
    cars_df = pd.DataFrame()

try:
    taxis_df = pd.read_csv('data/taxis_india.csv')
except (FileNotFoundError, pd.errors.ParserError) as e:
    print(f"Warning: Could not load taxis data: {e}")
    taxis_df = pd.DataFrame()

try:
    bikes_df = pd.read_csv('data/bikes_india.csv')
except (FileNotFoundError, pd.errors.ParserError) as e:
    print(f"Warning: Could not load bikes data: {e}")
    bikes_df = pd.DataFrame()

# Create app
app = FastAPI(title="Triplix Travel Agent", version="2.0.0")
app.add_middleware(CORSMiddleware, allow_origins=["*"], allow_credentials=True, allow_methods=["*"], allow_headers=["*"])


@app.on_event("startup")
async def startup_event():
    """Warm the on-disk photo cache."""
    _load_photo_cache()


@app.on_event("shutdown")
async def shutdown_event():
    """Persist the photo cache on shutdown."""
    _save_photo_cache()

# Helper: Headers for new Google APIs (Places API New)
def _google_headers(field_mask: str) -> dict:
    return {
        'Content-Type': 'application/json',
        'X-Goog-Api-Key': GOOGLE_PLACES_API_KEY,
        'X-Goog-FieldMask': field_mask
    }


def _extract_date_string(value: Any) -> str:
    """Normalize incoming date strings to YYYY-MM-DD when possible."""
    if not value:
        return ''

    if isinstance(value, datetime):
        return value.strftime('%Y-%m-%d')

    text = str(value).strip()
    if not text:
        return ''

    for fmt in ('%Y-%m-%d', '%Y-%m-%dT%H:%M:%S', '%Y-%m-%dT%H:%M:%S.%f'):
        try:
            return datetime.strptime(text, fmt).strftime('%Y-%m-%d')
        except ValueError:
            continue

    if 'T' in text:
        return text.split('T', 1)[0]

    return text[:10]


def _safe_int(value: Any, default: int) -> int:
    try:
        return int(value)
    except (TypeError, ValueError):
        return default


def _normalize_string_list(values: Any) -> list[str]:
    if not isinstance(values, list):
        return []

    normalized = []
    for value in values:
        if value is None:
            continue
        text = str(value).strip()
        if text:
            normalized.append(text)
    return normalized


def _chunk_trip_places(places: list[str], duration_days: int) -> list[list[str]]:
    if duration_days <= 0:
        return []

    cleaned_places = places or []
    per_day = max(1, (len(cleaned_places) + duration_days - 1) // duration_days) if cleaned_places else 0
    chunks = []

    for day_index in range(duration_days):
        if per_day:
            start = day_index * per_day
            end = start + per_day
            day_places = cleaned_places[start:end]
        else:
            day_places = []

        if not day_places and cleaned_places:
            day_places = [cleaned_places[day_index % len(cleaned_places)]]

        chunks.append(day_places)

    return chunks


def _get_weather_forecast(city: str, date_str: str) -> dict:
    """Fetch a forecast snapshot for a city/date, with a friendly fallback."""
    fallback = {
        'temp': '25-30°C',
        'condition': 'Pleasant',
        'description': 'Weather data unavailable',
        'icon': '[PARTLY_CLOUDY]',
        'humidity': None,
        'wind': None,
    }

    if not city or not date_str:
        return fallback

    if not OPENWEATHER_API_KEY:
        fallback['description'] = 'Using fallback weather snapshot'
        return fallback

    try:
        target_date = datetime.strptime(date_str, '%Y-%m-%d').date()
    except ValueError:
        return fallback

    try:
        response = requests.get(
            'http://api.openweathermap.org/data/2.5/forecast',
            params={
                'q': f'{city},IN',
                'appid': OPENWEATHER_API_KEY,
                'units': 'metric',
                'cnt': 40,
            },
            timeout=5,
        )

        if response.status_code != 200:
            return fallback

        closest_forecast = None
        min_day_gap = 999
        for forecast in response.json().get('list', []):
            forecast_dt = datetime.fromtimestamp(forecast['dt'])
            day_gap = abs((forecast_dt.date() - target_date).days)
            if day_gap < min_day_gap or (day_gap == min_day_gap and forecast_dt.hour == 12):
                min_day_gap = day_gap
                closest_forecast = forecast

        if not closest_forecast:
            return fallback

        weather = closest_forecast['weather'][0]
        weather_id = weather['id']
        icon = '[SUN]'
        if weather_id < 300:
            icon = '[STORM]'
        elif weather_id < 400:
            icon = '[CLOUDY]'
        elif weather_id < 600:
            icon = '[RAIN]'
        elif weather_id < 700:
            icon = '[SNOW]'
        elif weather_id < 800:
            icon = '[FOG]'
        elif weather_id == 800:
            icon = '[SUN]'
        elif weather_id == 801:
            icon = '[PARTLY_CLOUDY]'
        elif weather_id < 805:
            icon = '[CLOUDS]'

        temp_min = round(closest_forecast['main']['temp_min'])
        temp_max = round(closest_forecast['main']['temp_max'])
        return {
            'temp': f'{temp_min}-{temp_max}°C',
            'condition': weather['main'],
            'description': weather['description'].capitalize(),
            'icon': icon,
            'humidity': closest_forecast['main'].get('humidity'),
            'wind': round(closest_forecast['wind']['speed'] * 3.6, 1),
        }
    except Exception as exc:
        print(f'[WEATHER] Forecast lookup failed for {city} on {date_str}: {exc}')
        return fallback


def _categorize_weather_risk(weather: dict) -> dict:
    condition = str(weather.get('condition', '')).lower()
    description = str(weather.get('description', '')).lower()
    temp = str(weather.get('temp', ''))
    wind = weather.get('wind')

    reasons = []
    risk_level = 'low'

    def promote(level: str, target: str) -> str:
        severity_order = {'low': 0, 'medium': 1, 'high': 2}
        return target if severity_order[target] > severity_order[level] else level

    if any(token in condition or token in description for token in ['thunder', 'storm']):
        risk_level = 'high'
        reasons.append('Thunderstorm risk can disrupt outdoor sightseeing and transfers.')
    elif any(token in condition or token in description for token in ['rain', 'drizzle', 'shower']):
        risk_level = 'medium'
        reasons.append('Rain may affect beaches, walking tours, and outdoor viewpoints.')
    elif any(token in condition or token in description for token in ['fog', 'mist', 'haze']):
        risk_level = 'medium'
        reasons.append('Low visibility may slow road travel and scenic activities.')

    if isinstance(wind, (int, float)) and wind >= 30:
        risk_level = 'high' if risk_level == 'medium' else promote(risk_level, 'medium')
        reasons.append('Strong winds can make transfers and open-air plans uncomfortable.')

    if '35' in temp or '36' in temp or '37' in temp or '38' in temp or '39' in temp or '40' in temp:
        risk_level = promote(risk_level, 'medium')
        reasons.append('High daytime heat suggests moving intense activities to early or late hours.')

    if not reasons:
        reasons.append('Current forecast looks stable for the planned schedule.')

    indoor_backup = [
        'museum or gallery visit',
        'local food trail or cafe stop',
        'shopping street or indoor market',
        'spa, wellness, or cultural workshop',
    ]

    return {
        'level': risk_level,
        'reasons': reasons,
        'indoor_backup_ideas': indoor_backup,
    }


def _build_itinerary_state(
    from_location: str,
    to_location: str,
    stay_city: str,
    start_date: Any,
    end_date: Any,
    duration_days: Any,
    selected_destinations: list[str],
    selected_hotels: list[str],
    selected_transport: list[str],
    budget: Any,
    travelers: Any,
    itinerary_text: str,
) -> dict:
    normalized_start = _extract_date_string(start_date)
    normalized_end = _extract_date_string(end_date)
    safe_duration = max(1, _safe_int(duration_days, 3))

    if not normalized_start:
        normalized_start = datetime.now().strftime('%Y-%m-%d')

    try:
        start_dt = datetime.strptime(normalized_start, '%Y-%m-%d')
    except ValueError:
        start_dt = datetime.now()
        normalized_start = start_dt.strftime('%Y-%m-%d')

    if not normalized_end:
        normalized_end = (start_dt + timedelta(days=safe_duration - 1)).strftime('%Y-%m-%d')

    place_chunks = _chunk_trip_places(selected_destinations, safe_duration)
    daily_plan = []

    for day_index in range(safe_duration):
        day_date = (start_dt + timedelta(days=day_index)).strftime('%Y-%m-%d')
        weather = _get_weather_forecast(stay_city or to_location, day_date)
        risk = _categorize_weather_risk(weather)
        day_places = place_chunks[day_index] if day_index < len(place_chunks) else []
        day_label = f'Day {day_index + 1}'

        daily_plan.append({
            'day': day_index + 1,
            'label': day_label,
            'date': day_date,
            'focus_places': day_places,
            'weather': weather,
            'weather_risk': risk,
        })

    risky_days = [
        {
            'day': day['day'],
            'date': day['date'],
            'risk_level': day['weather_risk']['level'],
            'weather': day['weather'],
            'reasons': day['weather_risk']['reasons'],
        }
        for day in daily_plan
        if day['weather_risk']['level'] in {'medium', 'high'}
    ]

    return {
        'from': from_location,
        'to': to_location,
        'stay_city': stay_city or to_location,
        'start_date': normalized_start,
        'end_date': normalized_end,
        'duration_days': safe_duration,
        'budget': budget,
        'travelers': travelers,
        'selected_destinations': selected_destinations,
        'selected_hotels': selected_hotels,
        'selected_transport': selected_transport,
        'generated_at': datetime.now().isoformat(),
        'daily_plan': daily_plan,
        'risky_days': risky_days,
        'itinerary_text': itinerary_text,
    }


def _build_dynamic_replan_prompt(
    message: str,
    itinerary_text: str,
    itinerary_state: dict,
    recent_chat: str,
) -> str:
    risky_days = itinerary_state.get('risky_days', [])
    city = itinerary_state.get('stay_city') or itinerary_state.get('to') or 'the destination'

    if risky_days:
        risk_summary = json.dumps(risky_days, indent=2)
        risk_instruction = 'Prioritize moving outdoor or weather-sensitive items away from risky windows and use indoor backups when needed.'
    else:
        risk_summary = '[]'
        risk_instruction = 'No major weather risk was detected. Tighten sequencing and add a short monitoring note instead of making unnecessary changes.'

    return f"""You are Triplix Dynamic Re-planning Agent. Your job is to proactively repair an existing trip plan when weather or disruption risk appears.

User trigger:
{message}

Recent conversation:
{recent_chat or 'No recent chat provided.'}

Current itinerary:
{itinerary_text[:8000] if itinerary_text else 'No itinerary available.'}

Structured itinerary state:
{json.dumps(itinerary_state, indent=2)[:10000]}

Detected risk days for {city}:
{risk_summary}

Instructions:
1. Preserve confirmed hotel and transport details unless the user explicitly wants them changed.
2. Detect which parts of the plan are likely weather-sensitive.
3. Reorder outdoor sightseeing onto safer days or safer time windows where possible.
4. Insert resilient alternatives on risky days such as food trails, museums, markets, spas, cultural experiences, or covered activities.
5. If no risky days exist, keep the plan mostly intact and add a concise monitoring note.
6. Keep budget awareness in mind and do not inflate costs without explaining why.
7. End with a short section titled Re-plan Summary that states what changed and why.
8. Mention any day that should be rechecked closer to departure.

{risk_instruction}

Return the complete updated itinerary, not just the delta."""


def _run_dynamic_replan(
    message: str,
    itinerary_text: str,
    itinerary_state: dict,
    recent_chat: str,
) -> dict:
    refreshed_state = _build_itinerary_state(
        from_location=itinerary_state.get('from', 'Unknown'),
        to_location=itinerary_state.get('to', itinerary_state.get('stay_city', 'Unknown')),
        stay_city=itinerary_state.get('stay_city', itinerary_state.get('to', 'Unknown')),
        start_date=itinerary_state.get('start_date', ''),
        end_date=itinerary_state.get('end_date', ''),
        duration_days=itinerary_state.get('duration_days', 3),
        selected_destinations=_normalize_string_list(itinerary_state.get('selected_destinations', [])),
        selected_hotels=_normalize_string_list(itinerary_state.get('selected_hotels', [])),
        selected_transport=_normalize_string_list(itinerary_state.get('selected_transport', [])),
        budget=itinerary_state.get('budget'),
        travelers=itinerary_state.get('travelers'),
        itinerary_text=itinerary_text,
    )

    model = genai.GenerativeModel('gemini-2.5-flash')
    response_obj = model.generate_content(
        _build_dynamic_replan_prompt(message, itinerary_text, refreshed_state, recent_chat)
    )
    refreshed_state['itinerary_text'] = response_obj.text

    return {
        'response': response_obj.text,
        'itinerary_state': refreshed_state,
        'risk_summary': refreshed_state.get('risky_days', []),
    }

def _create_hotel_description(hotel_name, hotel_type, amenities, city, rating):
    """Create a detailed description for the hotel"""
    type_descriptions = {
        'Hotel': 'a premium accommodation',
        'Resort': 'a luxurious resort experience',
        'Hostel': 'a budget-friendly shared accommodation',
        'Homestay': 'a cozy home-like stay',
        'Villa': 'a private villa experience',
        'Boutique Hotel': 'a stylish boutique hotel',
        'Guesthouse': 'a charming guesthouse',
    }
    
    description = f"{hotel_name} is {type_descriptions.get(hotel_type, 'an excellent accommodation')} located in {city}, India. "
    
    # Add rating description
    if rating >= 4.5:
        description += f"This highly-rated property ({rating}/5) offers exceptional service and quality. "
    elif rating >= 4.0:
        description += f"This well-rated property ({rating}/5) provides good value and comfort. "
    else:
        description += f"This property ({rating}/5) offers basic amenities at an affordable price. "
    
    # Add amenities description
    if 'Pool' in amenities:
        description += "Enjoy the refreshing swimming pool and relax in style. "
    if 'Spa' in amenities:
        description += "Unwind with spa treatments and wellness facilities. "
    if 'Beach Access' in amenities:
        description += "Direct beach access makes it perfect for beach lovers. "
    if 'WiFi' in amenities:
        description += "Stay connected with complimentary high-speed WiFi. "
    if 'Gym' in amenities:
        description += "Maintain your fitness routine with the on-site gym. "
    
    return description

def _create_recommendation(hotel_name, hotel_type, amenities, city, price, rating):
    """Create a personalized recommendation for why this hotel is good"""
    recommendation = ""
    
    if rating >= 4.5:
        recommendation += f"[STAR] Excellent choice! {hotel_name} boasts outstanding reviews and premium amenities. "
    elif rating >= 4.0:
        recommendation += f"[GOOD] Great value! {hotel_name} offers reliable service with good amenities. "
    
    # Price-based recommendation
    if price < 2000:
        recommendation += "Perfect for budget travelers looking for essential comforts. "
    elif price < 5000:
        recommendation += "Ideal for mid-range travelers seeking quality and convenience. "
    elif price < 10000:
        recommendation += "Excellent for those wanting premium experiences without breaking the bank. "
    else:
        recommendation += "Luxury experience for special occasions and discerning travelers. "
    
    # Location-based recommendation
    city_recommendations = {
        'Goa': "Perfect for beach vacations and water sports enthusiasts. ",
        'Mumbai': "Ideal for business travelers and city explorers. ",
        'Delhi': "Great for cultural experiences and historical sightseeing. ",
        'Jaipur': "Excellent for heritage lovers and palace enthusiasts. ",
        'Agra': "Perfect for Taj Mahal visitors and history buffs. ",
    }
    recommendation += city_recommendations.get(city, f"Well-located in {city} for local attractions. ")
    
    # Amenity-based recommendation
    if 'Pool' in amenities and 'Spa' in amenities:
        recommendation += "Relaxation paradise with pool and spa facilities. "
    elif 'Beach Access' in amenities:
        recommendation += "Direct beach access makes it unbeatable for coastal getaways. "
    elif 'Gym' in amenities:
        recommendation += "Fitness-focused travelers will appreciate the gym facilities. "
    
    return recommendation

def _get_nearby_attractions(city):
    """Get nearby attractions for the city"""
    attractions = {
        'Goa': ['Baga Beach', 'Anjuna Beach', 'Calangute Beach', 'Dudhsagar Falls', 'Fort Aguada'],
        'Mumbai': ['Gateway of India', 'Marine Drive', 'Elephanta Caves', 'Chor Bazaar', 'Juhu Beach'],
        'Delhi': ['Red Fort', 'India Gate', 'Qutub Minar', 'Lotus Temple', 'Akshardham Temple'],
        'Jaipur': ['Amber Fort', 'City Palace', 'Hawa Mahal', 'Jantar Mantar', 'Nahargarh Fort'],
        'Agra': ['Taj Mahal', 'Agra Fort', 'Fatehpur Sikri', 'Itmad-ud-Daulah', 'Mehtab Bagh'],
        'Kolkata': ['Victoria Memorial', 'Howrah Bridge', 'Marble Palace', 'South City Mall', 'Princep Ghat'],
        'Chennai': ['Marina Beach', 'Kapaleeshwarar Temple', 'Fort St. George', 'San Thome Basilica', 'Guindy National Park'],
        'Bangalore': ['Lalbagh Botanical Garden', 'Cubbon Park', 'Bangalore Palace', 'Vidhana Soudha', 'UB City'],
        'Hyderabad': ['Charminar', 'Golconda Fort', 'Hussain Sagar Lake', 'Salar Jung Museum', 'Birla Mandir'],
        'Pune': ['Shaniwar Wada', 'Aga Khan Palace', 'Sinhagad Fort', 'Parvati Hill', 'Bund Garden'],
    }
    return attractions.get(city, [f'Local attractions in {city}'])

def _parse_iso_date(date_input: Any) -> Optional[str]:
    """Normalize date values to YYYY-MM-DD for downstream APIs."""
    if not date_input:
        return None
    raw = str(date_input).strip()
    if not raw:
        return None
    try:
        return datetime.fromisoformat(raw.replace('Z', '+00:00')).date().isoformat()
    except ValueError:
        pass
    for fmt in ('%Y-%m-%d', '%d-%m-%Y', '%d/%m/%Y', '%m/%d/%Y'):
        try:
            return datetime.strptime(raw, fmt).date().isoformat()
        except ValueError:
            continue
    return None

def _city_to_iata(city: str) -> Optional[str]:
    """Convert supported Indian cities to IATA city/airport codes for Amadeus."""
    mapping = {
        'delhi': 'DEL',
        'new delhi': 'DEL',
        'mumbai': 'BOM',
        'bengaluru': 'BLR',
        'bangalore': 'BLR',
        'goa': 'GOI',
        'jaipur': 'JAI',
        'agra': 'AGR',
        'hyderabad': 'HYD',
        'pune': 'PNQ',
        'kolkata': 'CCU',
        'chennai': 'MAA',
        'ahmedabad': 'AMD',
        'kochi': 'COK',
        'cochin': 'COK',
        'lucknow': 'LKO',
        'raipur': 'RPR',
        'indore': 'IDR',
        'bhopal': 'BHO',
        'nagpur': 'NAG',
        'surat': 'STV',
        'varanasi': 'VNS',
        'amritsar': 'ATQ',
        'udaipur': 'UDR',
        'jodhpur': 'JDH',
        'patna': 'PAT',
        'guwahati': 'GAU',
        'bhubaneswar': 'BBI',
        'coimbatore': 'CJB',
        'trivandrum': 'TRV',
        'thiruvananthapuram': 'TRV',
        'srinagar': 'SXR',
        'dehradun': 'DED',
        'chandigarh': 'IXC',
        'ranchi': 'IXR',
        'vadodara': 'BDQ',
        'visakhapatnam': 'VTZ',
        'madurai': 'IXM',
        'mangalore': 'IXE',
        'leh': 'IXL',
        'port blair': 'IXZ',
    }
    # Tolerate "Raipur, Chhattisgarh, India" as well as "Raipur" — the app's
    # destination picker returns fully-qualified labels.
    key = str(city).split(',')[0].strip().lower()
    return mapping.get(key)

TRAVELPAYOUTS_API_TOKEN = os.getenv('TRAVELPAYOUTS_API_TOKEN', '')
TRAVELPAYOUTS_MARKER = os.getenv('TRAVELPAYOUTS_MARKER', '')

# Off by default: flights must come from Aviasales so every result shown is
# genuinely bookable at the price displayed. Set FLIGHTS_ALLOW_SYNTHETIC=1
# only for an offline demo, and never in production — it re-enables the CSV
# and Gemini paths, which invent flight numbers and fares.
FLIGHTS_ALLOW_SYNTHETIC = os.getenv('FLIGHTS_ALLOW_SYNTHETIC', '').strip().lower() in ('1', 'true', 'yes')

# Same rule for hotels: only real inventory. Off by default — see the note at
# the Gemini hotel path for why (unbookable results, and ~45s to produce them).
HOTELS_ALLOW_AI_GENERATED = os.getenv('HOTELS_ALLOW_AI_GENERATED', '').strip().lower() in ('1', 'true', 'yes')


# Set by _fetch_aviasales_flights when the requested trip shape had no fares
# but the opposite one did, keyed by (origin, destination). Read by the search
# endpoint to build a hint for the empty state.
_alternate_shape_hint = {}


def _fetch_aviasales_flights(from_city, to_city, departure_date, return_date,
                             passengers, travel_class):
    """Real Aviasales fares for a route, via the Travelpayouts data API.

    IMPORTANT — this is a price *cache*, not a live availability search. The
    API returns fares that recent searches happened to record, so a route can
    come back with one offer or none even when flights obviously exist. Treat
    an empty result as "no cached fare", not "no flights", and fall through to
    the next source rather than telling the user the route doesn't exist.

    Returns [] on any failure so the caller falls back to CSV/AI.
    """
    if not TRAVELPAYOUTS_API_TOKEN:
        return []

    origin_info = _resolve_airport(from_city)
    dest_info = _resolve_airport(to_city)
    if not origin_info or not dest_info:
        print(f"[AVIASALES] Could not resolve airports for {from_city!r} -> {to_city!r}")
        return []

    origin = origin_info['iata']
    destination = dest_info['iata']
    if origin == destination:
        print(f"[AVIASALES] {from_city!r} and {to_city!r} share airport {origin}")
        return []

    base = {
        'origin': origin,
        'destination': destination,
        'currency': 'inr',
        'sorting': 'price',
        'limit': 30,
        'one_way': 'false' if return_date else 'true',
    }

    def fetch(params):
        try:
            resp = requests.get(
                'https://api.travelpayouts.com/aviasales/v3/prices_for_dates',
                params=params,
                headers={'X-Access-Token': TRAVELPAYOUTS_API_TOKEN},
                timeout=12,
            )
            if resp.status_code != 200:
                print(f"[AVIASALES] HTTP {resp.status_code} for {origin}->{destination}")
                return []
            return resp.json().get('data') or []
        except Exception as e:
            print(f"[AVIASALES] Request failed: {e}")
            return []

    requested_day = str(departure_date)[:10] if departure_date else ''
    return_day = str(return_date)[:10] if return_date else ''
    wants_round_trip = bool(return_day)

    # The trip shape is never substituted. A one-way and a round-trip fare are
    # different products at different prices (BLR-RPR on 11 Aug: 0 one-way
    # fares but 12 round trips from Rs13,608) and quoting a return fare as a
    # one-way price would understate the trip by roughly half. Only the DATE
    # is widened, and the client is told when that happened.
    shape = 'false' if wants_round_trip else 'true'
    attempts = []
    if requested_day:
        primary = dict(base, departure_at=requested_day, one_way=shape)
        if return_day:
            primary['return_at'] = return_day
        attempts.append(('exact', primary))
        attempts.append(('widened',
                         dict(base, departure_at=requested_day[:7], one_way=shape)))
    attempts.append(('widened', dict(base, one_way=shape)))

    offers, exact_date = [], True
    for level, params in attempts:
        offers = fetch(params)
        if offers:
            exact_date = level == 'exact'
            break

    if not offers:
        # Nothing in the shape asked for. Check whether the OTHER shape has
        # fares so the client can say "no one-way fares, but round trips from
        # Rs X" — a useful hint, kept out of the results list so its price can
        # never be mistaken for the one the user searched.
        probe = dict(base, one_way='true' if wants_round_trip else 'false')
        if requested_day:
            probe['departure_at'] = requested_day
            if not wants_round_trip:
                probe['return_at'] = (
                    datetime.fromisoformat(requested_day) + timedelta(days=3)
                ).strftime('%Y-%m-%d')
        alt_offers = fetch(probe) or fetch(
            dict(base, one_way='true' if wants_round_trip else 'false'))
        if alt_offers:
            cheapest = min(x.get('price', 0) for x in alt_offers if x.get('price'))
            _alternate_shape_hint[(origin, destination)] = {
                'shape': 'one_way' if wants_round_trip else 'round_trip',
                'from_price': cheapest,
                'count': len(alt_offers),
            }
        return []

    results = []
    for offer in offers:
        try:
            row = _create_aviasales_flight_result(
                offer, from_city, to_city, passengers, travel_class,
                departure_date, return_date,
            )
            # Tell the client when we flew from a different city's airport, so
            # it can say so rather than implying the village has an airport.
            row['origin_airport_info'] = origin_info
            row['destination_airport_info'] = dest_info
            # False when this fare is for a different day than the user asked
            # for, so the UI can label it rather than implying it's available
            # on the requested date.
            row['exact_date'] = exact_date
            row['requested_date'] = requested_day
            results.append(row)
        except Exception as e:
            print(f"[AVIASALES] Skipped malformed offer: {e}")

    print(f"[AVIASALES] {len(results)} cached fares for {origin}->{destination}")
    return results


def _create_aviasales_flight_result(offer, from_city, to_city, passengers,
                                    travel_class, departure_date, return_date):
    """Map one Aviasales offer onto the same result shape the app already
    consumes from the CSV path, so no Flutter changes are needed."""
    airline = offer.get('airline', '')
    flight_number = str(offer.get('flight_number', ''))
    stops = int(offer.get('transfers') or 0)
    price = float(offer.get('price') or 0)

    departure_at = str(offer.get('departure_at') or '')
    departure_time = departure_at[11:16] if len(departure_at) >= 16 else ''

    minutes = int(offer.get('duration') or 0)
    duration = f"{minutes // 60}h {minutes % 60}m" if minutes else ''

    # `link` is a path relative to the Aviasales host. Resolve it against the
    # India storefront (aviasales.in + market=in) so fares render in INR — the
    # .com domain infers the market from the visitor and can show an Indian
    # user USD. Then attach the marker so the click is attributed.
    link = offer.get('link') or ''
    booking_url = f"https://aviasales.in{link}" if link.startswith('/') else link
    if booking_url:
        extra = {'market': 'in', 'currency': 'inr', 'locale': 'en'}
        if TRAVELPAYOUTS_MARKER:
            extra['marker'] = TRAVELPAYOUTS_MARKER
        for key, value in extra.items():
            if f'{key}=' in booking_url:
                continue
            booking_url += ('&' if '?' in booking_url else '?') + f'{key}={value}'

    description = (
        f"{airline} flight {flight_number} from {from_city.title()} to "
        f"{to_city.title()}. "
    )
    description += ("Direct flight. " if stops == 0
                    else f"Flight with {stops} stop(s). ")
    description += "Fare and availability confirmed on Aviasales at booking."

    recommendation = (
        "Direct flight — fastest option on this route. " if stops == 0
        else "Connecting flight. "
    )
    recommendation += f"Lowest fare recorded for this date: Rs{int(price)}."

    return {
        'id': f"aviasales_{airline}{flight_number}_{departure_at[:10]}",
        'flight_date': departure_at[:10],
        'provider': airline,
        'route_number': f"{airline}{flight_number}",
        'from_city': from_city.title(),
        'to_city': to_city.title(),
        'departure_time': departure_time,
        'arrival_time': '',  # not supplied by this endpoint
        'duration': duration,
        'stops': stops,
        'vehicle_type': 'Aircraft',
        'price': price,
        'class': (travel_class or 'economy').title(),
        'amenities': [],
        'description': description,
        'why_recommended': recommendation,
        'passengers': passengers,
        'departure_date': departure_date,
        'return_date': return_date,
        'extras': [],
        'accessibility': [],
        'booking_url': booking_url,
        'origin_airport': offer.get('origin_airport', ''),
        'destination_airport': offer.get('destination_airport', ''),
    }


_AIRPORTS_PATH = os.path.join(os.path.dirname(os.path.abspath(__file__)), '.airports.json')
_AIRPORTS_URL = 'https://api.travelpayouts.com/data/en/airports.json'
_airports_cache = None
_airport_lookup_cache = {}


def _load_airports():
    """Travelpayouts' airport dataset (IATA code + coordinates), cached to disk.

    Only 'flightable' airports are kept — the full file includes heliports and
    disused strips that Aviasales can't sell tickets for, and offering someone
    a flight to one of those is worse than offering nothing.
    """
    global _airports_cache
    if _airports_cache is not None:
        return _airports_cache

    data = None
    try:
        if os.path.exists(_AIRPORTS_PATH):
            with open(_AIRPORTS_PATH, 'r', encoding='utf-8') as fh:
                data = json.load(fh)
    except Exception:
        data = None

    if data is None:
        try:
            print("[AIRPORTS] Downloading airport dataset…")
            data = requests.get(_AIRPORTS_URL, timeout=45).json()
            with open(_AIRPORTS_PATH, 'w', encoding='utf-8') as fh:
                json.dump(data, fh)
        except Exception as e:
            print(f"[AIRPORTS] Could not load dataset: {e}")
            _airports_cache = []
            return _airports_cache

    _airports_cache = [
        a for a in data
        if a.get('flightable') and a.get('code') and (a.get('coordinates') or {}).get('lat') is not None
    ]
    print(f"[AIRPORTS] {len(_airports_cache)} flightable airports available")
    return _airports_cache


def _haversine_km(lat1, lon1, lat2, lon2):
    from math import radians, sin, cos, asin, sqrt
    lat1, lon1, lat2, lon2 = map(radians, (lat1, lon1, lat2, lon2))
    h = sin((lat2 - lat1) / 2) ** 2 + cos(lat1) * cos(lat2) * sin((lon2 - lon1) / 2) ** 2
    return 2 * 6371.0 * asin(sqrt(h))


def _geocode_city(city: str):
    """(lat, lon) for a free-text place via Google Places, or None."""
    if not GOOGLE_PLACES_API_KEY:
        return None
    try:
        resp = requests.post(
            'https://places.googleapis.com/v1/places:searchText',
            headers=_google_headers('places.location,places.displayName'),
            json={'textQuery': city, 'maxResultCount': 1},
            timeout=8,
        ).json()
        places = resp.get('places') or []
        if not places:
            return None
        loc = places[0].get('location') or {}
        if loc.get('latitude') is None:
            return None
        return (loc['latitude'], loc['longitude'])
    except Exception as e:
        print(f"[AIRPORTS] Geocode failed for {city!r}: {e}")
        return None


def _resolve_airport(city: str):
    """Resolve a free-text city to a bookable airport.

    Returns a dict with the IATA code plus, when the city has no airport of
    its own, which airport was substituted and how far away it is — the caller
    surfaces that so a user searching a village isn't silently shown flights
    from a city 200km away.

    Returns None when nothing usable is found.
    """
    if not city:
        return None

    key = str(city).strip().lower()
    if key in _airport_lookup_cache:
        return _airport_lookup_cache[key]

    # Fast path: the hand-maintained map covers the big cities exactly.
    exact = _city_to_iata(city)
    if exact:
        result = {'iata': exact, 'substituted': False,
                  'airport_name': '', 'distance_km': 0, 'query': city}
        _airport_lookup_cache[key] = result
        return result

    airports = _load_airports()
    if not airports:
        return None

    coords = _geocode_city(city)
    if not coords:
        print(f"[AIRPORTS] Could not geocode {city!r}")
        return None

    lat, lon = coords
    nearest, best = None, None
    for a in airports:
        c = a['coordinates']
        d = _haversine_km(lat, lon, c['lat'], c['lon'])
        if best is None or d < best:
            best, nearest = d, a

    if nearest is None:
        return None

    result = {
        'iata': nearest['code'],
        # Under ~30km the airport effectively serves that city, so don't
        # bother the user with a "nearest airport" note.
        'substituted': best > 30,
        'airport_name': nearest.get('name', ''),
        'distance_km': round(best),
        'query': city,
    }
    _airport_lookup_cache[key] = result
    print(f"[AIRPORTS] {city!r} -> {result['iata']} "
          f"({result['airport_name']}, {result['distance_km']}km)")
    return result


def _amadeus_credentials_ready() -> bool:
    return bool(AMADEUS_CLIENT_ID and AMADEUS_CLIENT_SECRET)

def _map_flight_class_to_amadeus(travel_class: str) -> str:
    mapping = {
        'economy': 'ECONOMY',
        'premium_economy': 'PREMIUM_ECONOMY',
        'business': 'BUSINESS',
        'first_class': 'FIRST',
        'first': 'FIRST',
    }
    return mapping.get((travel_class or 'economy').strip().lower(), 'ECONOMY')

def _fetch_amadeus_flights(
    from_city: str,
    to_city: str,
    departure_date: str,
    return_date: Optional[str],
    passengers: int,
    travel_class: str,
) -> List[Dict[str, Any]]:
    """Fetch live flight offers from Amadeus and map to app flight shape."""
    if not USE_AMADEUS_FLIGHTS:
        return []

    token = _get_amadeus_access_token()
    if not token:
        return []

    origin = _city_to_iata(from_city)
    destination = _city_to_iata(to_city)
    dep = _parse_iso_date(departure_date)
    ret = _parse_iso_date(return_date) if return_date else None
    if not origin or not destination or not dep:
        return []

    params = {
        'originLocationCode': origin,
        'destinationLocationCode': destination,
        'departureDate': dep,
        'adults': max(1, int(passengers or 1)),
        'travelClass': _map_flight_class_to_amadeus(travel_class),
        'currencyCode': 'INR',
        'max': 12,
    }
    if ret:
        params['returnDate'] = ret

    try:
        resp = requests.get(
            f"{AMADEUS_HOST}/v2/shopping/flight-offers",
            headers={'Authorization': f'Bearer {token}'},
            params=params,
            timeout=18,
        )
        if resp.status_code != 200:
            print(f"[AMADEUS] Flight offers failed: {resp.status_code} {resp.text[:220]}")
            return []

        offers = resp.json().get('data', []) or []
        mapped: List[Dict[str, Any]] = []

        for offer in offers:
            itineraries = offer.get('itineraries', []) or []
            if not itineraries:
                continue

            first_itinerary = itineraries[0]
            segments = first_itinerary.get('segments', []) or []
            if not segments:
                continue

            first_seg = segments[0]
            last_seg = segments[-1]

            dep_at = str(first_seg.get('departure', {}).get('at', ''))
            arr_at = str(last_seg.get('arrival', {}).get('at', ''))
            dep_time = dep_at[11:16] if 'T' in dep_at else dep_at
            arr_time = arr_at[11:16] if 'T' in arr_at else arr_at

            price_obj = offer.get('price', {}) or {}
            try:
                total_price = float(price_obj.get('grandTotal') or price_obj.get('total') or 0)
            except (TypeError, ValueError):
                total_price = 0.0
            if total_price <= 0:
                continue

            carrier = first_seg.get('carrierCode', 'AIRLINE')
            flight_no = f"{carrier}{first_seg.get('number', '')}".strip()
            aircraft = first_seg.get('aircraft', {}).get('code', 'Aircraft')

            mapped.append({
                'id': str(offer.get('id') or f"{flight_no}_{dep_time}"),
                'provider': carrier,
                'route_number': flight_no,
                'from_city': str(from_city).title(),
                'to_city': str(to_city).title(),
                'departure_time': dep_time,
                'arrival_time': arr_time,
                'duration': first_itinerary.get('duration', 'PT0H0M'),
                'stops': max(0, len(segments) - 1),
                'vehicle_type': aircraft,
                'price': total_price,
                'class': travel_class.title(),
                'amenities': [],
                'description': f"{carrier} flight {flight_no} from {str(from_city).title()} to {str(to_city).title()}.",
                'why_recommended': 'Live Amadeus fare with real-time availability.',
                'passengers': max(1, int(passengers or 1)),
                'departure_date': dep,
                'return_date': ret,
                'extras': [],
                'accessibility': [],
                'source': 'amadeus',
                'raw_offer': offer,
            })

        return mapped
    except Exception as e:
        print(f"[AMADEUS] Flight fetch error: {e}")
        return []

def _get_amadeus_access_token() -> Optional[str]:
    now_ts = datetime.utcnow().timestamp()
    cached_token = _amadeus_token_cache.get('access_token', '')
    expires_at = float(_amadeus_token_cache.get('expires_at', 0) or 0)
    if cached_token and expires_at > (now_ts + 30):
        return cached_token

    if not _amadeus_credentials_ready():
        return None

    try:
        response = requests.post(
            f"{AMADEUS_HOST}/v1/security/oauth2/token",
            headers={'Content-Type': 'application/x-www-form-urlencoded'},
            data={
                'grant_type': 'client_credentials',
                'client_id': AMADEUS_CLIENT_ID,
                'client_secret': AMADEUS_CLIENT_SECRET,
            },
            timeout=12,
        )
        if response.status_code != 200:
            print(f"[AMADEUS] Token request failed: {response.status_code} {response.text[:200]}")
            return None
        payload = response.json()
        token = payload.get('access_token')
        expires_in = int(payload.get('expires_in', 1800) or 1800)
        if token:
            _amadeus_token_cache['access_token'] = token
            _amadeus_token_cache['expires_at'] = now_ts + expires_in
            return token
    except Exception as e:
        print(f"[AMADEUS] Token error: {e}")
    return None

def _fetch_amadeus_hotels(city: str, budget: float, check_in: str, check_out: str) -> List[Dict[str, Any]]:
    """Fetch live hotel offers from Amadeus and map to app hotel shape."""
    token = _get_amadeus_access_token()
    if not token:
        return []

    city_code = _city_to_iata(city)
    if not city_code:
        print(f"[AMADEUS] No IATA mapping for city: {city}")
        return []

    headers = {'Authorization': f'Bearer {token}'}
    try:
        list_resp = requests.get(
            f"{AMADEUS_HOST}/v1/reference-data/locations/hotels/by-city",
            headers=headers,
            params={'cityCode': city_code, 'radius': 20, 'radiusUnit': 'KM'},
            timeout=15,
        )
        if list_resp.status_code != 200:
            print(f"[AMADEUS] Hotel list failed: {list_resp.status_code} {list_resp.text[:200]}")
            return []
        hotels_data = list_resp.json().get('data', [])
        hotel_ids = [h.get('hotelId') for h in hotels_data if h.get('hotelId')][:20]
        if not hotel_ids:
            return []

        offers_resp = requests.get(
            f"{AMADEUS_HOST}/v3/shopping/hotel-offers",
            headers=headers,
            params={
                'hotelIds': ','.join(hotel_ids),
                'adults': 1,
                'roomQuantity': 1,
                'checkInDate': check_in,
                'checkOutDate': check_out,
                'currency': 'INR',
                'bestRateOnly': 'true',
            },
            timeout=20,
        )
        if offers_resp.status_code != 200:
            print(f"[AMADEUS] Offers failed: {offers_resp.status_code} {offers_resp.text[:200]}")
            return []

        response_data = offers_resp.json().get('data', [])
        results: List[Dict[str, Any]] = []
        for item in response_data:
            hotel_info = item.get('hotel', {}) or {}
            offers = item.get('offers', []) or []
            if not offers:
                continue

            offer = offers[0]
            price_obj = offer.get('price', {}) or {}
            total_price = price_obj.get('total')
            currency = price_obj.get('currency', 'INR')
            try:
                nightly_price = float(total_price)
            except (TypeError, ValueError):
                continue

            if budget and nightly_price > float(budget):
                continue

            hotel_name = hotel_info.get('name', 'Hotel')
            amenities: List[str] = []
            hotel_type = 'Hotel'
            rating = float(hotel_info.get('rating') or 4.2)
            description = _create_hotel_description(hotel_name, hotel_type, amenities, city, rating)
            why_recommended = _create_recommendation(hotel_name, hotel_type, amenities, city, nightly_price, rating)
            nearby_attractions = _get_nearby_attractions(city)
            image_url = get_hotel_image(hotel_name, city)

            results.append({
                'name': hotel_name,
                'city': city,
                'price_per_night': nightly_price,
                'price_currency': currency,
                'type': hotel_type,
                'rating': rating,
                'amenities': amenities,
                'description': description,
                'why_recommended': why_recommended,
                'nearby_attractions': nearby_attractions,
                'image_url': image_url,
                'image': image_url,
            })

        return results[:10]
    except Exception as e:
        print(f"[AMADEUS] Fetch error: {e}")
        return []

def _search_flights(from_city, to_city, departure_date, return_date, passengers, travel_class, preferences, extras, travel_type, accessibility):
    """Search for flights"""
    try:
        # Prefer live Amadeus fares first when credentials are available.
        live_flights = _fetch_amadeus_flights(
            from_city=from_city,
            to_city=to_city,
            departure_date=departure_date,
            return_date=return_date,
            passengers=passengers,
            travel_class=travel_class,
        )
        if live_flights:
            print(f"[OK] Amadeus: {len(live_flights)} flights")
            return {
                'status': 'success',
                'powered_by': 'Amadeus',
                'ai_used': False,
                'results': live_flights,
                'count': len(live_flights),
            }

        # Real Aviasales fares. Sits above the CSV so anything we can show as
        # genuinely bookable wins over invented data; empty results fall
        # through, since this is a price cache and gaps are expected.
        aviasales_flights = _fetch_aviasales_flights(
            from_city=from_city,
            to_city=to_city,
            departure_date=departure_date,
            return_date=return_date,
            passengers=passengers,
            travel_class=travel_class,
        )
        if aviasales_flights:
            return {
                'status': 'success',
                'powered_by': 'Aviasales',
                'ai_used': False,
                'results': aviasales_flights,
                'count': len(aviasales_flights),
            }

        # Aviasales is the only trusted flight source. The CSV rows and the
        # Gemini path below both produce flights that look real but cannot be
        # booked — fabricated flight numbers at invented prices. Showing those
        # to a user who then can't book them is worse than showing nothing, so
        # they're off unless explicitly enabled for an offline demo.
        if not FLIGHTS_ALLOW_SYNTHETIC:
            print("[FLIGHTS] No Aviasales fares; synthetic fallbacks disabled")
            origin_info = _resolve_airport(from_city)
            dest_info = _resolve_airport(to_city)
            hint = None
            if not origin_info or not dest_info:
                message = ('We could not find an airport near '
                           f'{from_city.title() if not origin_info else to_city.title()}.')
            else:
                message = 'No fares available for this route and date.'
                hint = _alternate_shape_hint.pop(
                    (origin_info['iata'], dest_info['iata']), None)
                if hint:
                    shape = ('one-way' if hint['shape'] == 'one_way'
                             else 'return')
                    message = (
                        f"No {'return' if shape == 'one-way' else 'one-way'} "
                        f"fares recorded for this route. {hint['count']} "
                        f"{shape} fares are available from "
                        f"Rs{int(hint['from_price'])}."
                    )
            return {
                'status': 'success',
                'powered_by': 'Aviasales',
                'ai_used': False,
                'results': [],
                'count': 0,
                'message': message,
                'alternate_shape': hint,
                'origin_airport_info': origin_info,
                'destination_airport_info': dest_info,
            }

        # Try CSV first
        # NB: flights_india.csv names these columns 'from'/'to' (and
        # price_economy/price_business/aircraft_type below) — not the
        # from_city/to_city used by the train, bus, taxi and bike CSVs.
        filtered_flights = flights_df[
            (flights_df['from'].str.lower() == from_city) &
            (flights_df['to'].str.lower() == to_city)
        ]

        # Filter by class availability
        if travel_class == 'economy':
            filtered_flights = filtered_flights[filtered_flights['price_economy'] > 0]
        elif travel_class in ['business', 'first_class']:
            filtered_flights = filtered_flights[filtered_flights['price_business'] > 0]

        has_special = len(preferences) > 0 or len(extras) > 0 or len(accessibility) > 0 or travel_class != 'economy'

        if len(filtered_flights) > 0 and not has_special:
            print(f"[OK] CSV: {len(filtered_flights)} flights")
            results = []
            for _, f in filtered_flights.iterrows():
                price = f['price_economy'] if travel_class == 'economy' else f['price_business']
                amenities = f['amenities'].split(', ') if pd.notna(f['amenities']) else []

                results.append(_create_flight_result(f, price, travel_class, amenities, passengers, departure_date, return_date, extras, accessibility))
            return {'status': 'success', 'powered_by': 'CSV', 'ai_used': False, 'results': results, 'count': len(results)}

        # Use Gemini AI
        return _ai_search_travel("flight", from_city, to_city, departure_date, return_date, passengers, travel_class, preferences, extras, travel_type, accessibility)

    except Exception as e:
        print(f"[ERROR] Flight search error: {e}")
        return {"status": "error", "message": str(e)}

def _search_trains(from_city, to_city, departure_date, return_date, passengers, travel_class, preferences, extras, travel_type, accessibility):
    """Search for trains"""
    try:
        if len(trains_df) > 0:
            filtered_trains = trains_df[
                (trains_df['from_city'].str.lower() == from_city) &
                (trains_df['to_city'].str.lower() == to_city)
            ]

            # Filter by preferences
            if 'ac' in preferences:
                filtered_trains = filtered_trains[filtered_trains['ac_available'] == True]
            if 'sleeper' in preferences:
                filtered_trains = filtered_trains[filtered_trains['sleeper_available'] == True]

            if len(filtered_trains) > 0:
                print(f"[OK] CSV: {len(filtered_trains)} trains")
                results = []
                for _, t in filtered_trains.iterrows():
                    results.append(_create_train_result(t, travel_class, preferences, passengers, departure_date, return_date, extras, accessibility))
                return {'status': 'success', 'powered_by': 'CSV', 'ai_used': False, 'results': results, 'count': len(results)}

        # Use AI fallback
        return _ai_search_travel("train", from_city, to_city, departure_date, return_date, passengers, travel_class, preferences, extras, travel_type, accessibility)

    except Exception as e:
        print(f"[ERROR] Train search error: {e}")
        return {"status": "error", "message": str(e)}

def _search_buses(from_city, to_city, departure_date, return_date, passengers, travel_class, preferences, extras, travel_type, accessibility):
    """Search for buses"""
    try:
        if len(buses_df) > 0:
            filtered_buses = buses_df[
                (buses_df['from_city'].str.lower() == from_city) &
                (buses_df['to_city'].str.lower() == to_city)
            ]

            # Filter by preferences
            if 'ac' in preferences:
                filtered_buses = filtered_buses[filtered_buses['ac_available'] == True]

            if len(filtered_buses) > 0:
                print(f"[OK] CSV: {len(filtered_buses)} buses")
                results = []
                for _, b in filtered_buses.iterrows():
                    results.append(_create_bus_result(b, travel_class, preferences, passengers, departure_date, return_date, extras, accessibility))
                return {'status': 'success', 'powered_by': 'CSV', 'ai_used': False, 'results': results, 'count': len(results)}

        # Use AI fallback
        return _ai_search_travel("bus", from_city, to_city, departure_date, return_date, passengers, travel_class, preferences, extras, travel_type, accessibility)

    except Exception as e:
        print(f"[ERROR] Bus search error: {e}")
        return {"status": "error", "message": str(e)}

def _search_car_rentals(from_city, departure_date, return_date, passengers, travel_class, preferences, extras, duration_hours, accessibility):
    """Search for car rentals"""
    try:
        if len(cars_df) > 0:
            filtered_cars = cars_df[cars_df['city'].str.lower() == from_city]

            # Filter by preferences
            if 'private' in preferences:
                filtered_cars = filtered_cars[filtered_cars['private'] == True]

            if len(filtered_cars) > 0:
                print(f"[OK] CSV: {len(filtered_cars)} car rentals")
                results = []
                for _, c in filtered_cars.iterrows():
                    results.append(_create_car_result(c, travel_class, preferences, passengers, departure_date, return_date, duration_hours, extras, accessibility))
                return {'status': 'success', 'powered_by': 'CSV', 'ai_used': False, 'results': results, 'count': len(results)}

        # Use AI fallback
        return _ai_search_travel("car_rental", from_city, None, departure_date, return_date, passengers, travel_class, preferences, extras, "one_way", accessibility, duration_hours)

    except Exception as e:
        print(f"[ERROR] Car rental search error: {e}")
        return {"status": "error", "message": str(e)}

def _search_taxis(from_city, to_city, departure_date, passengers, travel_class, preferences, extras, accessibility):
    """Search for taxis"""
    try:
        if len(taxis_df) > 0:
            filtered_taxis = taxis_df[
                (taxis_df['from_city'].str.lower() == from_city) &
                (taxis_df['to_city'].str.lower() == to_city)
            ]

            if len(filtered_taxis) > 0:
                print(f"[OK] CSV: {len(filtered_taxis)} taxis")
                results = []
                for _, t in filtered_taxis.iterrows():
                    results.append(_create_taxi_result(t, travel_class, preferences, passengers, departure_date, extras, accessibility))
                return {'status': 'success', 'powered_by': 'CSV', 'ai_used': False, 'results': results, 'count': len(results)}

        # Use AI fallback
        return _ai_search_travel("taxi", from_city, to_city, departure_date, None, passengers, travel_class, preferences, extras, "one_way", accessibility)

    except Exception as e:
        print(f"[ERROR] Taxi search error: {e}")
        return {"status": "error", "message": str(e)}

def _search_bikes(from_city, to_city, departure_date, passengers, travel_class, preferences, extras, duration_hours, accessibility):
    """Search for bike/scooter rentals"""
    try:
        if len(bikes_df) > 0:
            filtered_bikes = bikes_df[
                (bikes_df['from_city'].str.lower() == from_city) &
                (bikes_df['to_city'].str.lower() == to_city)
            ]

            if len(filtered_bikes) > 0:
                print(f"[OK] CSV: {len(filtered_bikes)} bike rentals")
                results = []
                for _, b in filtered_bikes.iterrows():
                    results.append(_create_bike_result(b, travel_class, preferences, passengers, departure_date, duration_hours, extras, accessibility))
                return {'status': 'success', 'powered_by': 'CSV', 'ai_used': False, 'results': results, 'count': len(results)}

        # Use AI fallback
        return _ai_search_travel("bike_scooter", from_city, to_city, departure_date, None, passengers, travel_class, preferences, extras, "one_way", accessibility, duration_hours)

    except Exception as e:
        print(f"[ERROR] Bike search error: {e}")
        return {"status": "error", "message": str(e)}

def _ai_search_travel(mode, from_city, to_city, departure_date, return_date, passengers, travel_class, preferences, extras, travel_type, accessibility, duration_hours=None):
    """Use AI to search for travel options"""
    print(f"[AI] Using Gemini AI for {mode} search...")

    mode_names = {
        "flight": "flights",
        "train": "trains",
        "bus": "buses",
        "car_rental": "car rentals",
        "taxi": "taxis",
        "bike_scooter": "bike/scooter rentals"
    }

    preferences_text = ", ".join(preferences) if preferences else "standard"
    extras_text = ", ".join(extras) if extras else "basic service"
    accessibility_text = ", ".join(accessibility) if accessibility else "standard accessibility"

    if mode in ["car_rental", "bike_scooter"]:
        prompt = f"""Find 6-10 {mode_names[mode]} in {from_city}, India.
Duration: {duration_hours} hours
Departure: {departure_date}
Return: {return_date if return_date else 'Same day'}
Passengers: {passengers}
Class: {travel_class.title()}
Preferences: {preferences_text}
Extras: {extras_text}
Accessibility: {accessibility_text}

Return JSON with 'results' array. Each {mode} must have:
- id: string (unique identifier)
- provider: string (company name)
- vehicle_type: string (car model, bike type)
- price_per_hour: number (in INR)
- total_price: number (calculated for duration)
- amenities: array of strings
- description: detailed description (2-3 sentences)
- why_recommended: why this option is good (2-3 sentences)
- class: string
- passengers: number
- duration_hours: number
- extras: array of strings
- accessibility: array of strings

Format: {{"results": [{{"id": "CAR001", "provider": "Uber", ...}}]}}"""
    elif mode == "taxi":
        prompt = f"""Find 6-10 {mode_names[mode]} from {from_city} to {to_city}, India.
Departure: {departure_date}
Passengers: {passengers}
Class: {travel_class.title()}
Preferences: {preferences_text}
Extras: {extras_text}
Accessibility: {accessibility_text}

Return JSON with 'results' array. Each taxi must have:
- id: string (unique identifier)
- provider: string (company name)
- vehicle_type: string (car model)
- estimated_duration: string (e.g., "3h 30m")
- distance_km: number
- price: number (in INR)
- amenities: array of strings
- description: detailed description (2-3 sentences)
- why_recommended: why this option is good (2-3 sentences)
- class: string
- passengers: number
- extras: array of strings
- accessibility: array of strings

Format: {{"results": [{{"id": "TAXI001", "provider": "Uber", ...}}]}}"""
    else:
        prompt = f"""Find 6-10 {mode_names[mode]} from {from_city} to {to_city}, India.
Departure: {departure_date}
Return: {return_date if return_date else 'One-way'}
Travel Type: {travel_type.replace('_', ' ').title()}
Passengers: {passengers}
Class: {travel_class.title()}
Preferences: {preferences_text}
Extras: {extras_text}
Accessibility: {accessibility_text}

Return JSON with 'results' array. Each {mode} must have:
- id: string (unique identifier)
- provider: string (airline/train/bus company)
- route_number: string (flight/train/bus number)
- departure_time: string (HH:MM format)
- arrival_time: string (HH:MM format)
- duration: string (e.g., "2h 30m")
- stops: number (0 for direct)
- vehicle_type: string (aircraft/train type/bus type)
- price: number (in INR)
- class: string
- amenities: array of strings
- description: detailed description (2-3 sentences)
- why_recommended: why this option is good (2-3 sentences)
- passengers: number
- departure_date: string
- return_date: string (null for one-way)
- extras: array of strings
- accessibility: array of strings

Format: {{"results": [{{"id": "FL001", "provider": "Air India", ...}}]}}"""

    model = genai.GenerativeModel('gemini-2.5-flash')
    response = model.generate_content(prompt)
    text = response.text

    if '```json' in text:
        text = text.split('```json')[1].split('```')[0]
    elif '```' in text:
        text = text.split('```')[1].split('```')[0]

    result = json.loads(text.strip())
    results = result.get('results', [])

    # Ensure all required fields are present
    for result in results:
        result['passengers'] = passengers
        result['departure_date'] = departure_date
        result['return_date'] = return_date
        result['class'] = travel_class.title()
        result['extras'] = extras
        result['accessibility'] = accessibility
        if duration_hours:
            result['duration_hours'] = duration_hours
        # Add AI match score
        import random
        result['match_score'] = f"{random.randint(85, 98)}% Match"

    print(f"[OK] Gemini: {len(results)} {mode} results")

    return {'status': 'success', 'powered_by': 'Gemini AI', 'ai_used': True, 'results': results, 'count': len(results)}

def _create_flight_result(f, price, travel_class, amenities, passengers, departure_date, return_date, extras, accessibility):
    """Create standardized flight result"""
    description = f"{f['airline']} flight {f['flight_number']} from {f['from']} to {f['to']}. "
    if f['stops'] == 0:
        description += "Direct flight with excellent service. "
    else:
        description += f"Flight with {f['stops']} stop(s) for a comfortable journey. "
    description += f"Modern {f['aircraft_type']} aircraft with premium amenities."

    recommendation = f"Great choice for traveling from {f['from']} to {f['to']}. "
    if f['stops'] == 0:
        recommendation += "Direct flight saves time and reduces jet lag. "
    if 'WiFi' in amenities:
        recommendation += "Stay connected with in-flight WiFi. "
    if 'Entertainment' in amenities:
        recommendation += "Enjoy entertainment systems for a pleasant journey. "

    return {
        'id': f"{f['flight_number']}_{f['departure_time']}",
        'provider': f['airline'],
        'route_number': f['flight_number'],
        'from_city': f['from'],
        'to_city': f['to'],
        'departure_time': f['departure_time'],
        'arrival_time': f['arrival_time'],
        'duration': f['duration'],
        'stops': int(f['stops']),
        'vehicle_type': f['aircraft_type'],
        'price': float(price),
        'class': travel_class.title(),
        'amenities': amenities,
        'description': description,
        'why_recommended': recommendation,
        'passengers': passengers,
        'departure_date': departure_date,
        'return_date': return_date,
        'extras': extras,
        'accessibility': accessibility
    }

def _create_train_result(t, travel_class, preferences, passengers, departure_date, return_date, extras, accessibility):
    """Create standardized train result"""
    # Implementation for train results
    return {
        'id': f"TRAIN_{t.get('train_number', '001')}",
        'provider': t.get('railway', 'Indian Railways'),
        'route_number': t.get('train_number', '12345'),
        'from_city': t['from_city'],
        'to_city': t['to_city'],
        'departure_time': t.get('departure_time', '08:00'),
        'arrival_time': t.get('arrival_time', '18:00'),
        'duration': t.get('duration', '10h 0m'),
        'stops': t.get('stops', 0),
        'vehicle_type': t.get('train_type', 'Express'),
        'price': float(t.get('price', 1500)),
        'class': travel_class.title(),
        'amenities': ['WiFi', 'Meals'] if 'ac' in preferences else ['Basic seating'],
        'description': f"Comfortable train journey from {t['from_city']} to {t['to_city']} with modern amenities.",
        'why_recommended': f"Reliable train service with scenic routes and comfortable seating.",
        'passengers': passengers,
        'departure_date': departure_date,
        'return_date': return_date,
        'extras': extras,
        'accessibility': accessibility
    }

def _create_bus_result(b, travel_class, preferences, passengers, departure_date, return_date, extras, accessibility):
    """Create standardized bus result"""
    # Implementation for bus results
    return {
        'id': f"BUS_{b.get('bus_number', '001')}",
        'provider': b.get('operator', 'RedBus'),
        'route_number': b.get('bus_number', 'B123'),
        'from_city': b['from_city'],
        'to_city': b['to_city'],
        'departure_time': b.get('departure_time', '22:00'),
        'arrival_time': b.get('arrival_time', '06:00'),
        'duration': b.get('duration', '8h 0m'),
        'stops': b.get('stops', 1),
        'vehicle_type': b.get('bus_type', 'Volvo'),
        'price': float(b.get('price', 800)),
        'class': travel_class.title(),
        'amenities': ['AC', 'WiFi', 'Entertainment'] if 'ac' in preferences else ['Basic seating'],
        'description': f"Comfortable bus service from {b['from_city']} to {b['to_city']} with modern amenities.",
        'why_recommended': f"Reliable bus service with comfortable seating and good connectivity.",
        'passengers': passengers,
        'departure_date': departure_date,
        'return_date': return_date,
        'extras': extras,
        'accessibility': accessibility
    }

def _create_car_result(c, travel_class, preferences, passengers, departure_date, return_date, duration_hours, extras, accessibility):
    """Create standardized car rental result"""
    # Implementation for car rental results
    return {
        'id': f"CAR_{c.get('car_id', '001')}",
        'provider': c.get('company', 'Uber'),
        'vehicle_type': c.get('model', 'Sedan'),
        'price_per_hour': float(c.get('price_per_hour', 200)),
        'total_price': float(c.get('price_per_hour', 200)) * (duration_hours or 24),
        'amenities': ['AC', 'GPS', 'Music'],
        'description': f"Comfortable {c.get('model', 'Sedan')} rental in {c['city']} with all modern amenities.",
        'why_recommended': f"Flexible transportation option perfect for exploring {c['city']} at your own pace.",
        'class': travel_class.title(),
        'passengers': passengers,
        'departure_date': departure_date,
        'return_date': return_date,
        'duration_hours': duration_hours,
        'extras': extras,
        'accessibility': accessibility
    }

def _create_taxi_result(t, travel_class, preferences, passengers, departure_date, extras, accessibility):
    """Create standardized taxi result"""
    # Implementation for taxi results
    return {
        'id': f"TAXI_{t.get('taxi_id', '001')}",
        'provider': t.get('company', 'Uber'),
        'vehicle_type': t.get('model', 'Sedan'),
        'estimated_duration': t.get('duration', '2h 30m'),
        'distance_km': float(t.get('distance', 150)),
        'price': float(t.get('price', 1200)),
        'amenities': ['AC', 'GPS'],
        'description': f"Reliable taxi service from {t['from_city']} to {t['to_city']} with professional drivers.",
        'why_recommended': f"Convenient door-to-door transportation with tracking and safety features.",
        'class': travel_class.title(),
        'passengers': passengers,
        'departure_date': departure_date,
        'extras': extras,
        'accessibility': accessibility
    }

def _create_bike_result(b, travel_class, preferences, passengers, departure_date, duration_hours, extras, accessibility):
    """Create standardized bike result"""
    # Implementation for bike results
    return {
        'id': f"BIKE_{b.get('bike_id', '001')}",
        'provider': b.get('company', 'Rapido'),
        'vehicle_type': b.get('model', 'Scooter'),
        'price_per_hour': float(b.get('price_per_hour', 50)),
        'total_price': float(b.get('price_per_hour', 50)) * (duration_hours or 4),
        'amenities': ['GPS', 'Helmet'],
        'description': f"Convenient {b.get('model', 'Scooter')} rental for short trips in {b['from_city']}.",
        'why_recommended': f"Perfect for navigating city traffic and exploring local areas efficiently.",
        'class': travel_class.title(),
        'passengers': passengers,
        'departure_date': departure_date,
        'duration_hours': duration_hours,
        'extras': extras,
        'accessibility': accessibility
    }

def get_hotel_images_bulk(hotel_names, city):
    """Resolve photos for several hotels at once: {name: url}.

    Each get_hotel_image() call costs two sequential Google round trips, so
    doing them in a loop made hotel search scale with the number of results —
    a 6-hotel city took ~28s, right up against the client's 30s timeout. The
    lookups are pure network waits, so a thread pool collapses that into
    roughly the cost of one.
    """
    names = [n for n in dict.fromkeys(hotel_names) if n]
    if not names:
        return {}
    if len(names) == 1:
        return {names[0]: get_hotel_image(names[0], city)}

    results = {}
    with ThreadPoolExecutor(max_workers=min(12, len(names))) as executor:
        futures = {
            executor.submit(get_hotel_image, name, city): name
            for name in names
        }
        for future in futures:
            name = futures[future]
            try:
                results[name] = future.result(timeout=20)
            except Exception as e:
                print(f"[IMAGE] Bulk lookup failed for {name!r}: {e}")
                results[name] = ""
    return results


def get_hotel_image(hotel_name, city):
    """
    Get real hotel image URL using Google Places API (New)
    Uses skipHttpRedirect to get direct lh3.googleusercontent.com URLs
    Falls back to curated hotel images if Places API fails or no key
    """
    try:
        # Check cache first
        cache_key = f"{hotel_name}_{city}"
        if cache_key in _photo_cache:
            return _photo_cache[cache_key]
        
        # Skip Places API if no key is configured
        if not GOOGLE_PLACES_API_KEY:
            raise ValueError("No GOOGLE_PLACES_API_KEY configured")

        # Use Google Places API (New) to find real hotel photo
        # Search with exact name + city; don't append "hotel" since the name may already contain it
        search_url = "https://places.googleapis.com/v1/places:searchText"
        headers = {
            'Content-Type': 'application/json',
            'X-Goog-Api-Key': GOOGLE_PLACES_API_KEY,
            'X-Goog-FieldMask': 'places.displayName,places.photos,places.formattedAddress'
        }
        
        # Try exact name first for best match
        query = f"{hotel_name}, {city}, India"
        resp = requests.post(search_url, headers=headers,
            json={"textQuery": query, "maxResultCount": 1},
            timeout=8
        ).json()
        
        places = resp.get('places', [])
        
        # If no result, retry with "hotel" appended for generic names
        if not places:
            hotel_keywords = ['hotel', 'resort', 'hostel', 'palace', 'inn', 'lodge', 'villa', 'suites', 'taj', 'leela', 'oberoi', 'itc']
            if not any(kw in hotel_name.lower() for kw in hotel_keywords):
                query = f"{hotel_name} hotel, {city}, India"
                resp = requests.post(search_url, headers=headers,
                    json={"textQuery": query, "maxResultCount": 1},
                    timeout=8
                ).json()
                places = resp.get('places', [])
        
        if places and places[0].get('photos'):
            # Try first 3 photos and pick the first one that resolves
            for photo in places[0]['photos'][:3]:
                photo_name = photo.get('name', '')
                if photo_name:
                    media_url = f"https://places.googleapis.com/v1/{photo_name}/media?maxWidthPx=800&skipHttpRedirect=true&key={GOOGLE_PLACES_API_KEY}"
                    try:
                        media_resp = requests.get(media_url, timeout=5).json()
                        direct_url = media_resp.get('photoUri', '')
                        if direct_url:
                            _photo_cache[cache_key] = direct_url
                            print(f"[IMAGE] [OK] Found real image for '{hotel_name}' in {city}")
                            return direct_url
                    except:
                        continue
        
        # Fallback: use hotel-type-specific Unsplash images
        print(f"[IMAGE] [WARNING] Using fallback image for '{hotel_name}' in {city}")
        name_lower = hotel_name.lower()
        
        # Categorize by hotel type keywords
        if any(w in name_lower for w in ['hostel', 'zostel', 'backpack', 'hosteller', 'dormitor']):
            category_images = [
                "https://images.unsplash.com/photo-1555854877-bab0e564b8d5",  # hostel common area
                "https://images.unsplash.com/photo-1520277739336-7bf67edfa768",  # hostel beds
                "https://images.unsplash.com/photo-1559599238-308793637427",  # hostel lounge
            ]
        elif any(w in name_lower for w in ['resort', 'exotica', 'lake', 'beach', 'palace']):
            category_images = [
                "https://images.unsplash.com/photo-1566073771259-6a8506099945",  # luxury resort pool
                "https://images.unsplash.com/photo-1520250497591-112f2f40a3f4",  # resort infinity pool
                "https://images.unsplash.com/photo-1571896349842-33c89424de2d",  # tropical resort
                "https://images.unsplash.com/photo-1582719508461-905c673771fd",  # beach resort
            ]
        elif any(w in name_lower for w in ['taj', 'oberoi', 'leela', 'itc', 'marriott', 'hyatt', 'westin', 'rambagh']):
            category_images = [
                "https://images.unsplash.com/photo-1542314831-068cd1dbfeeb",  # grand luxury hotel
                "https://images.unsplash.com/photo-1455587734955-081b22074882",  # elegant hotel lobby
                "https://images.unsplash.com/photo-1578683010236-d716f9a3f461",  # luxury suite
                "https://images.unsplash.com/photo-1551882547-ff40c63fe5fa",  # premium hotel exterior
            ]
        else:
            category_images = [
                "https://images.unsplash.com/photo-1564501049412-61c2a3083791",  # modern hotel room
                "https://images.unsplash.com/photo-1445019980597-93fa8acb246c",  # cozy hotel
                "https://images.unsplash.com/photo-1590490360182-c33d57733427",  # comfortable room
                "https://images.unsplash.com/photo-1586611292717-f828b167408c",  # city hotel
            ]
        
        image_idx = abs(hash(hotel_name)) % len(category_images)
        url = f"{category_images[image_idx]}?w=800&h=600&fit=crop"
        _photo_cache[cache_key] = url
        return url
    except Exception as e:
        print(f"[IMAGE] [ERROR] Error for '{hotel_name}': {e}")
        url = "https://images.unsplash.com/photo-1566073771259-6a8506099945?w=800&h=600&fit=crop"
        return url

# Photo cache to avoid repeated API calls.
#
# Backed by a JSON file so it survives restarts. Resolving photos for one
# city's ~30 activities costs two Google round trips each — about 8s cold
# versus ~2s warm — and an in-memory-only cache paid that 8s again after
# every restart.
#
# Entries carry a fetch timestamp and expire after _PHOTO_CACHE_TTL. The
# Places photo URLs stored here are signed googleusercontent links whose
# exact lifetime Google doesn't document, so this deliberately errs short:
# a stale entry means a broken image, which is worse than a slow one. Raise
# the TTL if you observe the URLs outliving it.
_PHOTO_CACHE_PATH = os.path.join(os.path.dirname(os.path.abspath(__file__)), '.photo_cache.json')
_PHOTO_CACHE_TTL = 24 * 60 * 60  # seconds
_photo_cache = {}
_photo_cache_lock = threading.Lock()


def _load_photo_cache():
    """Restore non-expired cache entries from disk. Never fatal — a missing or
    corrupt cache file just means starting cold."""
    try:
        if not os.path.exists(_PHOTO_CACHE_PATH):
            return
        with open(_PHOTO_CACHE_PATH, 'r', encoding='utf-8') as fh:
            stored = json.load(fh)
        now = time.time()
        kept = {
            key: entry['url']
            for key, entry in stored.items()
            if isinstance(entry, dict)
            and entry.get('url')
            and now - entry.get('at', 0) < _PHOTO_CACHE_TTL
        }
        _photo_cache.update(kept)
        print(f"[CACHE] Loaded {len(kept)} photo URLs from disk "
              f"({len(stored) - len(kept)} expired)")
    except Exception as e:
        print(f"[CACHE] Could not load photo cache: {e}")


def _save_photo_cache():
    """Merge this process's cache into the file on disk.

    Merges rather than overwrites because uvicorn runs multiple worker
    processes, each with its own _photo_cache — a blind write would drop
    whatever the other worker had already resolved. Existing timestamps are
    preserved so re-saving can't extend an entry's life indefinitely.
    """
    try:
        with _photo_cache_lock:
            snapshot = dict(_photo_cache)
        if not snapshot:
            return

        existing = {}
        try:
            if os.path.exists(_PHOTO_CACHE_PATH):
                with open(_PHOTO_CACHE_PATH, 'r', encoding='utf-8') as fh:
                    existing = json.load(fh)
        except Exception:
            existing = {}

        now = time.time()
        payload = dict(existing) if isinstance(existing, dict) else {}
        for key, url in snapshot.items():
            prior = payload.get(key)
            keep_at = prior.get('at', now) if isinstance(prior, dict) else now
            payload[key] = {'url': url, 'at': keep_at}

        payload = {
            key: entry for key, entry in payload.items()
            if isinstance(entry, dict) and now - entry.get('at', 0) < _PHOTO_CACHE_TTL
        }

        tmp = f"{_PHOTO_CACHE_PATH}.{os.getpid()}.tmp"
        with open(tmp, 'w', encoding='utf-8') as fh:
            json.dump(payload, fh)
        os.replace(tmp, _PHOTO_CACHE_PATH)  # atomic, so a crash can't truncate it
    except Exception as e:
        print(f"[CACHE] Could not save photo cache: {e}")

# Themed fallback pools (all IDs verified to resolve on images.unsplash.com),
# keyed by rough activity topic. Used when Places API finds nothing for an
# abstract/generic activity word (e.g. "Daily Life", "Retail Therapy") that
# isn't a real, searchable place.
_ACTIVITY_FALLBACK_THEMES = {
    'nature': [
        "1441974231531-c6227db76b6e", "1441906363162-903afd0d3d52",
        "1477587458883-47145ed94245", "1512621776951-a57141f2eefd",
    ],
    'spiritual': [
        "1519501025264-65ba15a82390", "1476514525535-07fb3b4ae5f1",
    ],
    'food': [
        "1517248135467-4c7edcad34c4", "1533105079780-92b9be482077",
        "1555396273-367ea4eb4db5",
    ],
    'market': [
        "1555529669-e69e7aa0ba9a", "1533900298318-6b8da08a523e",
    ],
    'heritage': [
        "1519677100203-a0e668c92439", "1524492412937-b28074a5d7da",
    ],
    'urban': [
        "1449824913935-59a10b8d2000", "1502602898657-3e91760cbb34",
    ],
    'entertainment': [
        "1488646953014-85cb44e25828", "1566073771259-6a8506099945",
    ],
}

_ACTIVITY_THEME_KEYWORDS = {
    'nature': ['park', 'garden', 'lake', 'green', 'nature', 'picnic', 'river',
               'zoo', 'hill', 'forest', 'beach', 'view'],
    'spiritual': ['temple', 'shrine', 'mosque', 'church', 'dargah', 'pilgrim',
                  'spiritual', 'religious', 'meditation', 'ashram', 'sacred'],
    'food': ['food', 'cuisine', 'cafe', 'restaurant', 'dhaba', 'biryani',
             'snack', 'sweet', 'dining', 'eatery', 'street food', 'diner'],
    'market': ['market', 'shop', 'mall', 'bazaar', 'textile', 'retail',
               'souvenir', 'boutique', 'wholesale'],
    'heritage': ['fort', 'palace', 'monument', 'museum', 'heritage',
                 'historical', 'ancient', 'old town', 'ruins', 'building'],
    'urban': ['city', 'urban', 'cityscape', 'architecture', 'walk',
              'local life', 'daily life', 'views', 'commercial', 'stroll'],
    'entertainment': ['cinema', 'amusement', 'entertainment', 'theme park',
                       'family fun', 'recreation', 'playground', 'event',
                       'leisure'],
}


def _fallback_theme_for(query: str) -> str:
    q = query.lower()
    for theme, keywords in _ACTIVITY_THEME_KEYWORDS.items():
        if any(kw in q for kw in keywords):
            return theme
    return 'urban'


def get_activity_image(
    query: str,
    city: str,
    used_urls: Optional[set] = None,
    lock: Optional[threading.Lock] = None,
) -> str:
    """
    Get a real image for a travel activity/attraction using Google Places API
    (New). Same pattern as get_hotel_image, generalized to any short activity
    keyword (e.g. "Fort", "Biryani") combined with the city, so onboarding's
    destination-interests chips can show a real photo instead of plain text.

    [used_urls]/[lock], when provided, avoid handing out the same photo to
    two different activities in the same batch — small/less-mapped cities
    often only have a handful of indexed Places, so without this, distinct
    activities (e.g. "Local Market" and "Wholesale Market") can resolve to
    the literal same place and photo.
    """
    cache_key = f"activity_{query}_{city}"
    if cache_key in _photo_cache:
        return _photo_cache[cache_key]

    def claim(key: str) -> bool:
        """Registers key as used if it isn't already; returns False if taken."""
        if used_urls is None:
            return True
        if lock is not None:
            with lock:
                if key in used_urls:
                    return False
                used_urls.add(key)
                return True
        if key in used_urls:
            return False
        used_urls.add(key)
        return True

    try:
        if not GOOGLE_PLACES_API_KEY:
            raise ValueError("No GOOGLE_PLACES_API_KEY configured")

        search_url = "https://places.googleapis.com/v1/places:searchText"
        headers = {
            'Content-Type': 'application/json',
            'X-Goog-Api-Key': GOOGLE_PLACES_API_KEY,
            'X-Goog-FieldMask': 'places.displayName,places.photos'
        }
        search_query = f"{query} in {city}, India"
        resp = requests.post(search_url, headers=headers,
            json={"textQuery": search_query, "maxResultCount": 3},
            timeout=8
        ).json()

        # Dedupe by PLACE, not by final photo URL. Vague activity words
        # (e.g. "City Exploration") in a small/sparsely-mapped city often
        # resolve to the exact same top landmark as a concrete one (e.g.
        # "Fort") — two different photos of that same place are still
        # both "a picture of the fort", which reads as a duplicate to a
        # user even though the URLs technically differ. A photo's `name`
        # is "places/{place_id}/photos/{photo_id}", so the place_id prefix
        # doubles as a stable per-place dedup key.
        places = resp.get('places', [])
        for place in places:
            photos = place.get('photos', [])
            if not photos:
                continue
            first_name = photos[0].get('name', '')
            place_key = first_name.split('/photos/')[0] if first_name else ''
            if not place_key or not claim(place_key):
                continue  # this place already used by another activity

            for photo in photos[:3]:
                photo_name = photo.get('name', '')
                if not photo_name:
                    continue
                media_url = f"https://places.googleapis.com/v1/{photo_name}/media?maxWidthPx=600&skipHttpRedirect=true&key={GOOGLE_PLACES_API_KEY}"
                try:
                    media_resp = requests.get(media_url, timeout=5).json()
                    direct_url = media_resp.get('photoUri', '')
                except Exception:
                    continue
                if direct_url:
                    _photo_cache[cache_key] = direct_url
                    return direct_url
            # Claimed the place but couldn't resolve any of its photos
            # (rare) — fall through and try the next place.

        # Fallback: themed stock images, trying to avoid a repeat within
        # this batch before accepting one.
        theme = _fallback_theme_for(query)
        candidates = _ACTIVITY_FALLBACK_THEMES[theme]
        for photo_id in candidates:
            if claim(photo_id):
                url = f"https://images.unsplash.com/photo-{photo_id}?w=400&h=300&fit=crop"
                _photo_cache[cache_key] = url
                return url

        # Every themed candidate was already used this batch — accept a
        # repeat rather than return nothing.
        url = f"https://images.unsplash.com/photo-{candidates[0]}?w=400&h=300&fit=crop"
        _photo_cache[cache_key] = url
        return url
    except Exception as e:
        print(f"[ACTIVITY IMAGE] [ERROR] '{query}' in {city}: {e}")
        return "https://images.unsplash.com/photo-1488646953014-85cb44e25828?w=400&h=300&fit=crop"


class ActivityImagesRequest(BaseModel):
    city: str
    activities: List[str]


@app.post("/api/destination/activity-images")
def get_activity_images(request: ActivityImagesRequest):
    """
    Batch-fetch one representative real photo per activity keyword for a
    city (e.g. "Fort" -> a real fort photo for that city). Runs the Places
    API lookups concurrently since a city's activity list can be 30+ items
    and each lookup is a blocking HTTP call. Cache hits are seeded into
    used_urls before dispatching fresh lookups, so a cached result and a
    freshly-fetched one can't collide either.
    """
    try:
        activities = list(dict.fromkeys(request.activities))  # dedupe, keep order
        used_urls: set = set()
        lock = threading.Lock()

        results: Dict[str, str] = {}
        to_fetch = []
        for activity in activities:
            cache_key = f"activity_{activity}_{request.city}"
            cached = _photo_cache.get(cache_key)
            if cached:
                results[activity] = cached
                used_urls.add(cached)
            else:
                to_fetch.append(activity)

        if to_fetch:
            # These workers are idle on network I/O, not CPU-bound, so the pool
            # can cover the whole activity list in one wave. At 8 workers a
            # typical 30-item list took 4 sequential rounds (~10s cold); sizing
            # to the work itself brings that down to roughly one round trip.
            with ThreadPoolExecutor(max_workers=min(32, len(to_fetch))) as executor:
                fetched = list(executor.map(
                    lambda activity: (
                        activity,
                        get_activity_image(activity, request.city, used_urls, lock),
                    ),
                    to_fetch,
                ))
            results.update(dict(fetched))
            # Checkpoint here rather than only on shutdown: the server is
            # usually stopped with a kill, which never runs the shutdown hook,
            # and this is the point where expensive new lookups exist.
            _save_photo_cache()

        return {"status": "success", "city": request.city, "images": results}
    except Exception as e:
        print(f"[ACTIVITY IMAGES ERROR] {e}")
        return {"status": "error", "message": str(e), "images": {}}


class HotelSearchRequest(BaseModel):
    message: str
    context: Dict[str, Any]

class AgentRequest(BaseModel):
    message: str
    context: Optional[Dict[str, Any]] = {}
    page: Optional[str] = "home"

class RecaptchaVerifyRequest(BaseModel):
    token: str
    action: Optional[str] = 'auth'
    remote_ip: Optional[str] = None

class FlightSearchRequest(BaseModel):
    from_city: str
    to_city: str
    departure_date: str
    return_date: str = None
    passengers: int = 1
    flight_class: str = "economy"
    preferences: list = []

class TravelBookingRequest(BaseModel):
    mode: str  # "flight", "train", "bus", "car_rental", "taxi", "bike_scooter"
    from_city: str
    to_city: str = None  # Not needed for car_rental, taxi, bike_scooter
    departure_date: str
    return_date: str = None
    passengers: int = 1
    travel_class: str = "economy"  # "economy", "business", "first_class"
    preferences: list = []  # ["ac", "non_ac", "sleeper", "shared", "private"]
    extras: list = []  # ["pickup", "luggage", "wifi", "meals"]
    travel_type: str = "one_way"  # "one_way", "round_trip", "multi_city"
    accessibility: list = []  # ["wheelchair", "child_seat"]
    duration_hours: int = None  # For car_rental, taxi, bike_scooter

@app.get("/")
def root():
    return {
        "status": "OK",
        "mode": f"CSV + {_AI_MODE}",
        "version": "2.0",
        "cors_enabled": True,
        "ai_mode": _AI_MODE,
        "vertex_ai": USE_VERTEX_AI,
        "powered_by": "Google Cloud + Aviasales",
    }


@app.get("/api/health")
async def health_check():
    """Health check endpoint with AI status."""
    return {
        "status": "healthy",
        "ai_mode": _AI_MODE,
        "vertex_ai": USE_VERTEX_AI,
        "version": "2.0",
        "google_places_key_loaded": bool(GOOGLE_PLACES_API_KEY),
        "google_api_key_loaded": bool(GOOGLE_API_KEY),
        "recaptcha_configured": bool(RECAPTCHA_SECRET_KEY),
        "google_places_key_prefix": GOOGLE_PLACES_API_KEY[:6] + "…" if GOOGLE_PLACES_API_KEY else "MISSING",
    }

@app.post("/api/security/verify-captcha")
async def verify_captcha(payload: RecaptchaVerifyRequest, request: Request):
    """Verify reCAPTCHA token server-side using Google's siteverify API."""
    print(f"[CAPTCHA] Incoming verify request | action={payload.action} | token_len={len(payload.token or '')} | secret_len={len(RECAPTCHA_SECRET_KEY)} | allowed_hosts={RECAPTCHA_ALLOWED_HOSTS}", flush=True)

    if not RECAPTCHA_SECRET_KEY:
        print("[CAPTCHA] Rejected: RECAPTCHA_SECRET_KEY not configured", flush=True)
        return {
            'success': False,
            'verified': False,
            'reason': 'captcha_not_configured',
        }

    remote_ip = payload.remote_ip or (request.client.host if request.client else None)

    try:
        verify_response = requests.post(
            'https://www.google.com/recaptcha/api/siteverify',
            data={
                'secret': RECAPTCHA_SECRET_KEY,
                'response': payload.token,
                'remoteip': remote_ip or '',
            },
            timeout=8,
        )
    except Exception as exc:
        print(f"[CAPTCHA] Google siteverify network error: {exc}", flush=True)
        return {
            'success': False,
            'verified': False,
            'reason': 'network_error',
            'error': str(exc),
        }

    if verify_response.status_code != 200:
        print(f"[CAPTCHA] Google returned non-200: {verify_response.status_code} body={verify_response.text[:200]}", flush=True)
        return {
            'success': False,
            'verified': False,
            'reason': 'google_verify_failed',
            'status_code': verify_response.status_code,
        }

    try:
        data = verify_response.json()
    except Exception:
        print(f"[CAPTCHA] Could not parse Google response: {verify_response.text[:200]}", flush=True)
        return {
            'success': False,
            'verified': False,
            'reason': 'invalid_google_response',
        }

    print(f"[CAPTCHA] Google siteverify response: {data}", flush=True)

    verified = bool(data.get('success'))
    hostname = str(data.get('hostname', '')).lower().strip()
    reason = 'ok' if verified else 'google_verification_failed'

    if verified and RECAPTCHA_ALLOWED_HOSTS and hostname:
        host_allowed = False
        for allowed in RECAPTCHA_ALLOWED_HOSTS:
            if hostname == allowed or hostname.endswith(f'.{allowed}'):
                host_allowed = True
                break
        if not host_allowed:
            print(f"[CAPTCHA] Hostname '{hostname}' not in allowed list {RECAPTCHA_ALLOWED_HOSTS}", flush=True)
            verified = False
            reason = 'hostname_mismatch'

    print(f"[CAPTCHA] Final result: verified={verified} reason={reason} hostname={hostname}", flush=True)

    return {
        'success': True,
        'verified': verified,
        'reason': reason,
        'hostname': data.get('hostname'),
        'challenge_ts': data.get('challenge_ts'),
        'error_codes': data.get('error-codes', []),
        'action': payload.action,
    }

@app.post("/api/analyze-photo")
async def analyze_photo(request: Request):
    """
    AI-powered photo analysis for Trip Reel feature.
    Uses Gemini Vision to classify photos as travel-worthy or not.
    Rejects documents, blurry photos, screenshots, and inappropriate content.
    """
    try:
        body = await request.json()
        image_b64 = body.get('image_base64', '')
        file_name = body.get('file_name', 'photo.jpg')

        if not image_b64:
            return {"is_travel_photo": False, "quality_score": 0,
                    "caption": "", "rejection_reason": "No image provided"}

        image_bytes = base64.b64decode(image_b64)

        prompt = """Analyze this image for a travel trip reel/highlight video. Return a JSON object with these fields:

1. "is_travel_photo": boolean — true ONLY if this is a good travel/vacation photo (scenery, landmarks, food, people enjoying, cultural sites, nature, beaches, temples, markets, etc.)
   Set false for: documents, screenshots, receipts, bills, ID cards, blurry/dark photos, explicit content, random objects, text-heavy images, memes, or non-travel content.

2. "quality_score": integer 0-100 — rate photo quality for a highlight reel:
   90-100: Stunning travel shot (great composition, lighting, iconic landmark)
   70-89: Good travel photo (clear, interesting subject)
   40-69: Acceptable (recognizable travel scene but not great quality)
   0-39: Poor quality or not travel-related

3. "caption": string — A short, catchy 3-8 word caption for the reel slide (e.g., "Sunset at Taj Mahal", "Street food in Delhi")

4. "rejection_reason": string — If is_travel_photo is false, explain why (e.g., "This appears to be a document/receipt", "Image is too blurry"). Empty string if approved.

5. "category": string — One of: "landmark", "nature", "food", "people", "culture", "adventure", "nightlife", "transport", "accommodation", "other"

Return ONLY the JSON object, no markdown or extra text."""

        model = genai.GenerativeModel('gemini-2.5-flash')

        if USE_VERTEX_AI:
            image_part = Part.from_data(data=image_bytes, mime_type="image/jpeg")
            response = model.generate_content([prompt, image_part])
        else:
            import google.generativeai as genai_direct
            response = model.generate_content([
                prompt,
                {"mime_type": "image/jpeg", "data": image_bytes}
            ])

        result_text = response.text.strip()
        # Clean markdown fences if present
        if result_text.startswith('```'):
            result_text = result_text.split('\n', 1)[-1]
        if result_text.endswith('```'):
            result_text = result_text.rsplit('```', 1)[0]
        result_text = result_text.strip()

        result = json.loads(result_text)

        return {
            "is_travel_photo": result.get("is_travel_photo", False),
            "quality_score": result.get("quality_score", 50),
            "caption": result.get("caption", ""),
            "rejection_reason": result.get("rejection_reason", ""),
            "category": result.get("category", "other"),
        }

    except json.JSONDecodeError:
        print(f"[PHOTO] AI returned non-JSON, approving with defaults")
        return {"is_travel_photo": True, "quality_score": 60,
                "caption": "Travel moment", "rejection_reason": "", "category": "other"}
    except Exception as e:
        print(f"[PHOTO] Analysis error: {e}")
        return {"is_travel_photo": True, "quality_score": 50,
                "caption": "Travel photo", "rejection_reason": "", "category": "other"}


@app.post("/api/agent")
def handle_agent_request(request: AgentRequest):
    """
    Main agent endpoint - handles all AI requests from Flutter app
    Routes to appropriate functionality based on message and context
    """
    try:
        message = request.message
        context = request.context or {}
        page = request.page or 'home'
        
        print(f"\n[API/AGENT] Request received:")
        # Avoid printing message content that may have unicode characters
        print(f"   Message length: {len(message)} chars")
        print(f"   Page: {page}")
        
        # Simple conversational response using Gemini
        model = genai.GenerativeModel('gemini-2.5-flash')
        
        # Build context for Gemini
        user_prefs = context.get('user_preferences', {})
        conversation_history = context.get('conversation_history', [])
        
        # Check if user is asking for hotels
        message_lower = message.lower()
        
        # Priority intents that override hotel search (even if city is mentioned)
        is_directions_query = any(k in message_lower for k in ['how to get', 'how to reach', 'distance from', 'distance between', 'distance to', 'route from', 'directions to', 'travel from', 'how far', 'reach from', 'far is', 'km from', 'hours from', 'time to reach', 'way to reach', 'get from', 'go from'])
        is_nearby_query = any(k in message_lower for k in ['nearby', 'near my', 'restaurants near', 'restaurants in', 'atm near', 'things to do', 'places to visit', 'what to see', 'attractions in', 'explore', 'places near', 'food in', 'eat in'])
        is_translate_query = any(k in message_lower for k in ['translate', 'how to say', 'local language', 'phrases', 'survival phrases', 'hindi for', 'speak', 'language in', 'say hello'])
        is_insights_query = any(k in message_lower for k in ['best time', 'when to visit', 'best month', 'weather in', 'season', 'what to pack', 'packing list', 'climate', 'temperature in'])
        
        # General conversational intents — user is asking about the destination,
        # activities, culture, food, safety, tips, etc.  These should NEVER
        # be hijacked by hotel search even if a city name appears.
        is_general_query = any(k in message_lower for k in [
            # Activity / experience queries
            'things to do', 'what to do', 'activities in', 'adventure in', 'trek',
            'hike', 'scuba', 'diving', 'surfing', 'rafting', 'paragliding', 'camping',
            'safari', 'snorkeling', 'kayaking', 'bungee', 'zip line',
            # Culture / sightseeing
            'temple', 'temples', 'church', 'mosque', 'fort', 'palace', 'museum',
            'monument', 'heritage', 'culture', 'history', 'historical', 'architecture',
            'ruins', 'art', 'gallery', 'festival', 'celebration',
            # Food
            'food', 'cuisine', 'restaurant', 'street food', 'cafe', 'dish', 'dishes',
            'eat', 'eating', 'breakfast', 'lunch', 'dinner', 'snack', 'dessert',
            'local food', 'must try', 'famous food', 'best food',
            # Nature / geography
            'beach', 'beaches', 'mountain', 'hill', 'waterfall', 'lake', 'river',
            'forest', 'garden', 'park', 'island', 'viewpoint', 'sunrise', 'sunset',
            'scenic', 'landscape', 'nature',
            # Travel tips / safety / general info
            'safety', 'safe', 'dangerous', 'tips', 'advice', 'guide', 'how is',
            'what is', 'tell me about', 'information about', 'info about',
            'known for', 'famous for', 'popular in', 'must visit',
            'budget tips', 'save money', 'cheap', 'affordable',
            'nightlife', 'shopping', 'market', 'bazaar', 'mall', 'souvenir',
            'spa', 'wellness', 'yoga', 'meditation', 'ayurveda',
            # Conversational follow-ups
            'what else', 'anything else', 'more options', 'other options',
            'tell me more', 'more about', 'what about', 'how about',
            'can you suggest', 'suggest me', 'recommend', 'recommendation',
            'which one', 'which is better', 'should i',
            # Itinerary / plan modification phrases
            'add', 'remove', 'change', 'modify', 'update', 'swap', 'replace',
            'instead', 'also want', 'i want to', 'can we', 'can you',
            'include', 'skip', 'drop', 'cancel',
            # Casual chat
            'thank', 'thanks', 'ok', 'okay', 'cool', 'great', 'nice', 'awesome',
            'perfect', 'sure', 'yes', 'no', 'hi', 'hello', 'hey', 'bye',
        ])
        has_priority_intent = is_directions_query or is_nearby_query or is_translate_query or is_insights_query or is_general_query
        
        print(f"   Intent: directions={is_directions_query} nearby={is_nearby_query} translate={is_translate_query} insights={is_insights_query} general={is_general_query}")
        
        # Hotel search should only trigger on EXPLICIT hotel search intent,
        # not just because a city name or the word "hotel" appears in passing.
        _hotel_search_phrases = [
            'find hotel', 'find hotels', 'search hotel', 'search hotels',
            'show hotel', 'show hotels', 'hotel in', 'hotels in',
            'find accommodation', 'search accommodation',
            'show accommodation', 'accommodation in',
            'find room', 'find rooms', 'where to stay in',
            'places to stay in', 'stay in', 'book hotel', 'book a hotel',
            'hostel in', 'resort in', 'find hostel', 'find resort',
            'looking for hotel', 'looking for hotels', 'need a hotel',
            'need hotel', 'need accommodation', 'suggest hotel',
            'suggest hotels', 'recommend hotel', 'recommend hotels',
            'hotel options', 'hotel suggestions', 'hotel recommendation',
        ]
        asking_for_hotels = not has_priority_intent and any(phrase in message_lower for phrase in _hotel_search_phrases)
        
        # Destination/places search — user explicitly wants destination cards to choose from
        _destination_search_phrases = [
            'suggest destination', 'suggest destinations', 'suggest me destination',
            'suggest me destinations', 'recommend destination', 'recommend destinations',
            'show destination', 'show destinations', 'find destination', 'find destinations',
            'destination options', 'destination suggestions', 'destination recommendation',
            'places to visit', 'where to go', 'where should i go', 'where can i go',
            'suggest places', 'recommend places', 'show places', 'best places',
            'top destinations', 'popular destinations', 'best destinations',
            'where to travel', 'travel destinations', 'vacation destinations',
            'suggest me places', 'recommend me places', 'suggest cities',
            'which city', 'which place', 'which destination',
        ]
        asking_for_destinations = not has_priority_intent and not asking_for_hotels and any(phrase in message_lower for phrase in _destination_search_phrases)
        
        print(f"   Intent: hotels={asking_for_hotels} destinations={asking_for_destinations}")
        import re
        budget_match = re.search(r'(?:budget|budgeted|price|rs\.?|₹)\s*(\d+)|(\d{4,6})', message_lower)
        extracted_budget = None
        if budget_match:
            extracted_budget = int(budget_match.group(1) or budget_match.group(2))
            print(f"   Extracted budget from message: Rs.{extracted_budget}")
        
        # Try to extract destination from the current message first
        # Sort cities by length (longest first) to prevent partial matches
        # e.g., check "darjeeling" before "dar", "raipur" before "jaipur" confusion
        cities = [
            # Long names first to avoid partial matches
            'darjeeling', 'coimbatore', 'chandigarh', 'trivandrum', 'bhubaneswar', 'visakhapatnam',
            'thiruvananthapuram', 'pondicherry', 'puducherry', 'dehradun', 'mussoorie',
            'aurangabad', 'kanyakumari', 'haldwani', 'nainital',
            # Medium length cities
            'bengaluru', 'bangalore', 'hyderabad', 'rishikesh', 'varanasi', 'kolkata', 'chennai', 
            'udaipur', 'jodhpur', 'bikaner', 'jaisalmer', 'ajmer', 'pushkar', 'shimla', 'manali', 
            'mumbai', 'jaipur', 'raipur', 'kerala', 'mysore', 'nashik', 'nagpur', 'indore', 
            'bhopal', 'lucknow', 'kanpur', 'patna', 'ranchi', 'guwahati', 'shillong', 'imphal',
            'kohima', 'aizawl', 'gangtok', 'itanagar', 'dispur', 'panaji', 'kochi', 'cochin',
            'pune', 'surat', 'rajkot', 'vadodara', 'ahmedabad', 'amritsar', 'ludhiana', 'jalandhar',
            'bhilai', 'bilaspur', 'korba', 'jammu', 'srinagar', 'leh', 'ladakh', 'madurai',
            'tirupati', 'vizag', 'mangalore', 'hubli', 'belgaum', 'salem', 'trichy', 'erode',
            'allahabad', 'prayagraj', 'mathura', 'haridwar', 'ujjain', 'dwarka', 'somnath',
            # Short names last
            'delhi', 'agra', 'ooty', 'goa', 'gaya', 'durg', 'puri', 'diu'
        ]
        destination = None
        from_city = None  # Track the source city (from X to Y)
        
        # Use word boundary matching to avoid false matches
        import re
        
        # Check for "from X to Y" pattern first
        from_to_pattern = r'\bfrom\s+(\w+)\s+to\s+(\w+)\b'
        from_to_match = re.search(from_to_pattern, message_lower)
        
        if from_to_match:
            potential_from = from_to_match.group(1)
            potential_to = from_to_match.group(2)
            
            print(f"   Detected travel pattern: '{potential_from}' to '{potential_to}'")
            
            # Validate both cities exist in our list
            for city in cities:
                if city == potential_to.lower():
                    destination = city.capitalize()
                    print(f"   Destination city: {destination}")
                if city == potential_from.lower():
                    from_city = city.capitalize()
                    print(f"   Source city: {from_city}")
            
            # Only set asking_for_hotels when user explicitly used a
            # hotel-search phrase; the "from X to Y" pattern alone is travel
            # planning, not necessarily a hotel search.
        
        # If no "from-to" pattern, just look for any city mention
        # (used for context — does NOT force hotel search)
        if not destination:
            for city in cities:
                # Match city name with word boundaries to ensure exact match
                pattern = r'\b' + re.escape(city) + r'\b'
                if re.search(pattern, message_lower):
                    if city == 'bengaluru':
                        destination = 'Bangalore'
                    elif city == 'cochin':
                        destination = 'Kochi'
                    elif city == 'puducherry':
                        destination = 'Pondicherry'
                    else:
                        destination = city.capitalize()
                    # Do NOT force asking_for_hotels just because a city
                    # was mentioned.  The phrase-level check above is the
                    # only gateway to hotel search.
                    print(f"   Detected destination: {destination}")
                    break
        
        # If asking for hotels, provide actual hotel data
        if asking_for_hotels:
            # Get budget - prioritize extracted budget from message
            budget = extracted_budget if extracted_budget else user_prefs.get('budget', 50000)
            if budget is None:
                budget = 50000  # Default budget
            
            print(f"   Using budget: Rs.{budget}")
            
            if not destination:
                destination = user_prefs.get('destination', None)
            
            # Try to extract destination from conversation history if still not found
            if not destination:
                for msg in conversation_history[-5:]:  # Check last 5 messages
                    if isinstance(msg, dict):
                        content = msg.get('content', '').lower()
                        # Check for common Indian cities with word boundaries
                        for city in cities:
                            pattern = r'\b' + re.escape(city) + r'\b'
                            if re.search(pattern, content):
                                if city == 'bengaluru':
                                    destination = 'Bangalore'
                                else:
                                    destination = city.capitalize()
                                break
                    if destination:
                        break
            
            # If we have destination, search hotels
            if destination:
                try:
                    # Search hotels from CSV
                    city_hotels = hotels_df[hotels_df['city'].str.lower() == destination.lower()]
                    budget_hotels = city_hotels[city_hotels['price_per_night'] <= budget]
                    
                    if not budget_hotels.empty:
                        # Get top hotels - smart calculation based on duration and budget
                        # Base: 2-3 hotels for short trips, more for longer stays
                        duration_days = context.get('duration_days', 3)
                        travelers = context.get('travelers', 1)
                        
                        # Smart hotel count logic:
                        # - Short trip (1-3 days): 3-5 hotels
                        # - Medium trip (4-7 days): 5-8 hotels  
                        # - Long trip (8+ days): 8-10 hotels
                        # - High budget (>100k): +2 bonus hotels
                        if duration_days <= 3:
                            hotel_count = min(5, len(budget_hotels))
                        elif duration_days <= 7:
                            hotel_count = min(8, len(budget_hotels))
                        else:
                            hotel_count = min(10, len(budget_hotels))
                        
                        # Bonus hotels for high budget (more choices)
                        if budget > 100000:
                            hotel_count = min(hotel_count + 2, len(budget_hotels))
                        
                        top_hotels = budget_hotels.head(hotel_count)
                        
                        # Build hotel list response for text
                        hotel_list = []
                        suggestions = []
                        
                        for idx, hotel in top_hotels.iterrows():
                            # Text format
                            hotel_info = f"**{hotel['name']}** - Rs.{hotel['price_per_night']}/night\n"
                            location = hotel.get('location', hotel.get('city', destination))
                            hotel_info += f"  Location: {location}\n"
                            if pd.notna(hotel.get('rating')):
                                hotel_info += f"  Rating: {hotel.get('rating', 'N/A')}/5\n"
                            if pd.notna(hotel.get('amenities')):
                                amenities_str = str(hotel['amenities'])[:80]
                                hotel_info += f"  Amenities: {amenities_str}\n"
                            hotel_list.append(hotel_info)
                            
                            # Card format for Flutter suggestions
                            amenities = str(hotel.get('extras', '')).split('|') if pd.notna(hotel.get('extras')) else []
                            hotel_type = hotel.get('accommodation_type', 'Hotel')
                            
                            suggestions.append({
                                'id': hotel['name'],
                                'type': 'hotel',
                                'title': hotel['name'],
                                'description': f"{hotel_type} | Rating: {hotel.get('rating', 'N/A')} stars\n{', '.join(amenities[:3])}",
                                'price': float(hotel['price_per_night']),
                                'location': location,
                                'rating': str(hotel.get('rating', 'N/A')),
                                'image': get_hotel_image(hotel['name'], destination),
                                'stage': 'hotels',
                            })
                        
                        ai_response = f"Great! I found {len(top_hotels)} hotels in {destination} within your Rs.{budget} budget. Swipe right on the ones you like!"
                        
                        return {
                            "success": True,
                            "response": ai_response,
                            "agent": "hotel_search",
                            "data": {"hotels": top_hotels.to_dict('records')},
                            "suggestions": suggestions,
                            "show_suggestions": True,
                            "page": page,
                            "source": "ultra_simple_server"
                        }
                    else:
                        # No hotels in CSV - use Gemini AI to generate recommendations
                        print(f"   No hotels in CSV for {destination}, using Gemini AI...")
                        
                        prompt = f"""Find 5-8 hotels in {destination}, India under ₹{budget}/night.

Return JSON with 'hotels' array. Each hotel must have:
- name: string
- type: string (Hotel/Resort/Hostel/etc.)  
- price_per_night: number
- rating: number (1-5)
- amenities: array of strings
- description: detailed description (2-3 sentences)

Format: {{"hotels": [{{"name": "...", "type": "...", "price_per_night": 5000, "rating": 4.2, "amenities": ["WiFi", "Pool"], "description": "..."}}]}}"""
                        
                        response_obj = model.generate_content(prompt)
                        text = response_obj.text
                        
                        if '```json' in text:
                            text = text.split('```json')[1].split('```')[0]
                        elif '```' in text:
                            text = text.split('```')[1].split('```')[0]
                        
                        result = json.loads(text.strip())
                        hotels = result.get('hotels', [])
                        
                        # Convert to suggestions format
                        suggestions = []
                        for hotel in hotels:
                            suggestions.append({
                                'id': hotel['name'],
                                'type': 'hotel',
                                'title': hotel['name'],
                                'description': f"{hotel.get('type', 'Hotel')} | Rating: {hotel.get('rating', 'N/A')} stars\n{hotel.get('description', '')}",
                                'price': float(hotel.get('price_per_night', budget * 0.5)),
                                'location': destination,
                                'rating': str(hotel.get('rating', 'N/A')),
                                'image': get_hotel_image(hotel['name'], destination),
                                'stage': 'hotels',
                            })
                        
                        ai_response = f"Great! I found {len(hotels)} hotels in {destination} within your Rs.{budget} budget using AI recommendations. Swipe right on the ones you like!"
                        
                        return {
                            "success": True,
                            "response": ai_response,
                            "agent": "gemini_hotels",
                            "data": {"hotels": hotels},
                            "suggestions": suggestions,
                            "show_suggestions": True,
                            "page": page,
                            "source": "ultra_simple_server"
                        }
                except Exception as e:
                    print(f"   Hotel search error: {e}")
                    ai_response = f"Let me search for hotels in {destination}... Please wait a moment."
            else:
                ai_response = "I'd love to show you hotels! Which city or destination are you interested in? For example: Goa, Jaipur, Manali, etc."
        elif asking_for_destinations:
            # Generate destination city cards the user can swipe/select
            print(f"   🗺️ Generating destination cards for user to choose...")
            user_prefs = context.get('user_preferences', {})
            user_interests = user_prefs.get('activities', [])
            user_budget = extracted_budget or user_prefs.get('budget', 50000)
            companion = user_prefs.get('companion', '')
            occasion = user_prefs.get('occasion', '')

            dest_prompt = f"""Suggest 8-10 real travel destination cities in India for a traveler.

User preferences:
- Budget: ₹{user_budget}
- Interests: {', '.join(user_interests) if user_interests else 'general sightseeing'}
- Companion: {companion or 'not specified'}
- Occasion: {occasion or 'not specified'}
- User's message: {message}

Return a JSON array of destination cities. Each must have:
- "name": city name (e.g. "Jaipur", "Munnar", "Rishikesh")
- "state": state name
- "tagline": catchy 5-8 word tagline
- "description": 2-3 sentence description of why visit
- "best_for": array of 3-4 things it's best for (e.g. ["Heritage", "Food", "Shopping"])
- "avg_daily_budget": estimated daily budget in INR
- "rating": number 3.5-5.0

Return ONLY the JSON array, no markdown."""

            try:
                dest_model = genai.GenerativeModel('gemini-2.5-flash')
                dest_response = dest_model.generate_content(dest_prompt)
                dest_text = dest_response.text.strip()
                if dest_text.startswith("```"):
                    dest_text = dest_text.split("```")[1]
                    if dest_text.startswith("json"):
                        dest_text = dest_text[4:]
                    dest_text = dest_text.strip()
                dest_cities = json.loads(dest_text)

                suggestions = []
                for idx, dc in enumerate(dest_cities):
                    city_name = dc.get('name', 'Unknown')
                    # Get real photo from Google Places
                    try:
                        search_url = "https://places.googleapis.com/v1/places:searchText"
                        headers_places = {
                            'Content-Type': 'application/json',
                            'X-Goog-Api-Key': GOOGLE_PLACES_API_KEY,
                            'X-Goog-FieldMask': 'places.photos'
                        }
                        resp = requests.post(search_url, headers=headers_places,
                            json={"textQuery": f"{city_name} city India tourist", "maxResultCount": 1},
                            timeout=5
                        ).json()
                        places = resp.get('places', [])
                        image_url = ''
                        if places and places[0].get('photos'):
                            photo_name = places[0]['photos'][0].get('name', '')
                            if photo_name:
                                media_url = f"https://places.googleapis.com/v1/{photo_name}/media?maxWidthPx=800&skipHttpRedirect=true&key={GOOGLE_PLACES_API_KEY}"
                                try:
                                    media_resp = requests.get(media_url, timeout=5).json()
                                    image_url = media_resp.get('photoUri', '')
                                except:
                                    pass
                    except:
                        image_url = ''

                    if not image_url:
                        _dest_imgs = [
                            "https://images.unsplash.com/photo-1506012787146-f92b2d7d6d96?w=800&h=600&fit=crop",
                            "https://images.unsplash.com/photo-1507525428034-b723cf961d3e?w=800&h=600&fit=crop",
                            "https://images.unsplash.com/photo-1469474968028-56623f02e42e?w=800&h=600&fit=crop",
                            "https://images.unsplash.com/photo-1476514525535-07fb3b4ae5f1?w=800&h=600&fit=crop",
                            "https://images.unsplash.com/photo-1501785888041-af3ef285b470?w=800&h=600&fit=crop",
                        ]
                        image_url = _dest_imgs[idx % len(_dest_imgs)]

                    best_for = dc.get('best_for', [])
                    suggestions.append({
                        'id': f'dest_{city_name.lower().replace(" ", "_")}',
                        'type': 'destination',
                        'title': city_name,
                        'description': f"{dc.get('tagline', '')}\n{dc.get('state', '')}\n{', '.join(best_for[:4])}",
                        'price': dc.get('avg_daily_budget', 0),
                        'rating': str(dc.get('rating', '4.0')),
                        'image': image_url,
                        'stage': 'destinations',
                    })

                ai_response = f"Here are {len(suggestions)} amazing destinations I recommend! Swipe right on the ones that interest you."

                return {
                    "success": True,
                    "response": ai_response,
                    "agent": "destination_search",
                    "data": {"destinations": dest_cities},
                    "suggestions": suggestions,
                    "show_suggestions": True,
                    "page": page,
                    "source": "ultra_simple_server"
                }
            except Exception as e:
                print(f"   Destination card generation error: {e}")
                ai_response = "Let me suggest some destinations for you..."
        else:
            # ===== SMART ROUTING: Detect intent and use Google APIs =====
            # Only attempt API-specific handlers when the narrow intent
            # (directions/nearby/translate/insights) fired.  If only
            # is_general_query matched, skip straight to the general AI
            # response so follow-up and conversational queries aren't
            # swallowed by API calls that may fail silently.
            
            # Reuse the already-detected intents from above
            asking_directions = is_directions_query
            asking_nearby = is_nearby_query
            asking_translate = is_translate_query
            asking_insights = is_insights_query
            
            # --- DIRECTIONS ---
            if asking_directions:
                # Extract origin and destination from message
                origin_city = None
                dest_city = None
                for city in cities:
                    pattern = r'\b' + re.escape(city) + r'\b'
                    matches = re.findall(pattern, message_lower)
                    if matches:
                        if not origin_city:
                            origin_city = city.capitalize()
                        elif not dest_city:
                            dest_city = city.capitalize()
                
                # If only one city found, use user's preference as origin
                if origin_city and not dest_city:
                    dest_city = origin_city
                    origin_city = user_prefs.get('from', 'Delhi')
                
                if origin_city and dest_city:
                    try:
                        dir_resp = requests.get('https://maps.googleapis.com/maps/api/directions/json', params={
                            'origin': f"{origin_city}, India",
                            'destination': f"{dest_city}, India",
                            'key': GOOGLE_PLACES_API_KEY
                        }).json()
                        
                        if dir_resp.get('status') == 'OK':
                            leg = dir_resp['routes'][0]['legs'][0]
                            distance = leg['distance']['text']
                            duration = leg['duration']['text']
                            
                            ai_response = f"🗺️ **{origin_city} → {dest_city}**\n\n"
                            ai_response += f"📏 Distance: **{distance}**\n"
                            ai_response += f"⏱️ Duration: **{duration}** (by road)\n\n"
                            ai_response += f"Would you like me to search for flights or trains between these cities?"
                            
                            return {
                                "success": True,
                                "response": ai_response,
                                "agent": "google_maps",
                                "data": {"origin": origin_city, "destination": dest_city, "distance": distance, "duration": duration},
                                "page": page,
                                "source": "ultra_simple_server"
                            }
                    except Exception as e:
                        print(f"   Directions API error: {e}")
            
            # --- NEARBY PLACES ---
            elif asking_nearby:
                # Find which city to search nearby
                nearby_city = destination or user_prefs.get('destination', None)
                if not nearby_city:
                    for city in cities:
                        pattern = r'\b' + re.escape(city) + r'\b'
                        if re.search(pattern, message_lower):
                            nearby_city = city.capitalize()
                            break
                
                # Determine type
                place_type = 'tourist_attraction'
                if any(k in message_lower for k in ['restaurant', 'food', 'eat', 'dining']):
                    place_type = 'restaurant'
                elif any(k in message_lower for k in ['atm', 'bank', 'money']):
                    place_type = 'atm'
                elif any(k in message_lower for k in ['hospital', 'doctor', 'medical']):
                    place_type = 'hospital'
                elif any(k in message_lower for k in ['pharmacy', 'medicine']):
                    place_type = 'pharmacy'
                
                if nearby_city:
                    try:
                        # Geocode city first
                        geo_resp = requests.post('https://places.googleapis.com/v1/places:searchText',
                            headers=_google_headers("places.location"),
                            json={"textQuery": f"{nearby_city}, India", "maxResultCount": 1}
                        ).json()
                        geo_places = geo_resp.get('places', [])
                        
                        if geo_places:
                            loc = geo_places[0].get('location', {})
                            lat, lng = loc.get('latitude', 0), loc.get('longitude', 0)
                            
                            nearby_resp = requests.post('https://places.googleapis.com/v1/places:searchNearby',
                                headers=_google_headers("places.displayName,places.rating,places.formattedAddress"),
                                json={
                                    "includedTypes": [place_type],
                                    "maxResultCount": 8,
                                    "locationRestriction": {
                                        "circle": {
                                            "center": {"latitude": lat, "longitude": lng},
                                            "radius": 3000.0
                                        }
                                    }
                                }
                            ).json()
                            
                            places_found = nearby_resp.get('places', [])
                            if places_found:
                                type_label = place_type.replace('_', ' ').title()
                                ai_response = f"📍 **{type_label}s near {nearby_city}:**\n\n"
                                for i, p in enumerate(places_found[:8], 1):
                                    name = p.get('displayName', {}).get('text', 'Unknown')
                                    rating = p.get('rating', 'N/A')
                                    addr = p.get('formattedAddress', '')
                                    ai_response += f"{i}. **{name}** ⭐ {rating}\n   {addr}\n\n"
                                
                                return {
                                    "success": True,
                                    "response": ai_response,
                                    "agent": "google_places",
                                    "data": {"city": nearby_city, "type": place_type, "count": len(places_found)},
                                    "page": page,
                                    "source": "ultra_simple_server"
                                }
                    except Exception as e:
                        print(f"   Nearby search error: {e}")
            
            # --- TRANSLATION / PHRASES ---
            elif asking_translate:
                translate_city = None
                for city in cities:
                    pattern = r'\b' + re.escape(city) + r'\b'
                    if re.search(pattern, message_lower):
                        translate_city = city.capitalize()
                        break
                if not translate_city:
                    translate_city = user_prefs.get('destination', None)
                
                if translate_city:
                    try:
                        t_model = genai.GenerativeModel('gemini-2.5-flash')
                        t_prompt = f"""Generate 8 essential travel survival phrases for {translate_city}, India.
Return as a formatted list with: English | Local translation | Pronunciation
Categories: greeting, food, directions, emergency, shopping"""
                        t_resp = t_model.generate_content(t_prompt)
                        ai_response = f"🌐 **Survival Phrases for {translate_city}:**\n\n{t_resp.text}"
                        
                        return {
                            "success": True,
                            "response": ai_response,
                            "agent": "google_translate",
                            "data": {"city": translate_city},
                            "page": page,
                            "source": "ultra_simple_server"
                        }
                    except Exception as e:
                        print(f"   Translation error: {e}")
            
            # --- BEST TIME / INSIGHTS ---
            elif asking_insights:
                insight_city = None
                for city in cities:
                    pattern = r'\b' + re.escape(city) + r'\b'
                    if re.search(pattern, message_lower):
                        insight_city = city.capitalize()
                        break
                if not insight_city:
                    insight_city = user_prefs.get('destination', None)
                
                if insight_city:
                    # Check if asking for packing list
                    if 'pack' in message_lower:
                        try:
                            p_model = genai.GenerativeModel('gemini-2.5-flash')
                            p_prompt = f"""Create a smart packing list for a trip to {insight_city}, India. 
Be concise. Group by: Essentials, Clothing, Destination-specific items. Use bullet points."""
                            p_resp = p_model.generate_content(p_prompt)
                            ai_response = f"🎒 **Packing List for {insight_city}:**\n\n{p_resp.text}"
                            
                            return {
                                "success": True,
                                "response": ai_response,
                                "agent": "travel_insights",
                                "data": {"city": insight_city, "type": "packing"},
                                "page": page,
                                "source": "ultra_simple_server"
                            }
                        except Exception as e:
                            print(f"   Packing list error: {e}")
                    else:
                        try:
                            i_model = genai.GenerativeModel('gemini-2.5-flash')
                            i_prompt = f"""Best time to visit {insight_city}, India. Be concise (5-6 lines max).
Include: best months, avoid months, weather summary, one budget tip."""
                            i_resp = i_model.generate_content(i_prompt)
                            ai_response = f"📊 **Best Time to Visit {insight_city}:**\n\n{i_resp.text}"
                            
                            return {
                                "success": True,
                                "response": ai_response,
                                "agent": "travel_insights",
                                "data": {"city": insight_city, "type": "best_time"},
                                "page": page,
                                "source": "ultra_simple_server"
                            }
                        except Exception as e:
                            print(f"   Insights error: {e}")
            
            # --- COMPARISON / VS QUERIES ---
            is_comparison = any(k in message_lower for k in ['vs', 'versus', 'compare', 'which is better', 'difference between', 'or should i', 'better option'])
            if is_comparison:
                try:
                    c_model = genai.GenerativeModel('gemini-2.5-flash')
                    c_prompt = f"""Compare the following for a traveler planning a trip in India.

User's question: {message}

User's preferences:
- Budget: ₹{user_prefs.get('budget', 'flexible')}
- Interests: {', '.join(user_prefs.get('activities', [])) if user_prefs.get('activities') else 'general sightseeing'}

Provide a clear, structured comparison with:
1. **Quick Verdict** - Your top recommendation in 1 sentence
2. **Comparison Table** - Key factors (cost, experience, time, accessibility)
3. **Best For** - Who each option suits best
4. **Pro Tip** - An insider tip

Keep it concise and actionable. Use markdown formatting."""
                    c_resp = c_model.generate_content(c_prompt)
                    return {
                        "success": True,
                        "response": c_resp.text,
                        "agent": "travel_advisor",
                        "data": {},
                        "page": page,
                        "source": "ultra_simple_server"
                    }
                except Exception as e:
                    print(f"   Comparison error: {e}")
            
            # --- DEFAULT: General AI Response ---
            # Build recent conversation context (use more history, longer snippets)
            recent_history = ""
            for msg in conversation_history[-10:]:
                if isinstance(msg, dict):
                    role = msg.get('role', 'user')
                    content = msg.get('content', '')[:500]
                    recent_history += f"{role}: {content}\n"
            
            # Extract trip state from context
            trip_state = context.get('trip_state', {})
            selected_hotels = trip_state.get('selected_hotels', [])
            selected_transport = trip_state.get('selected_transport', [])
            selected_destinations = trip_state.get('selected_destinations', [])
            has_itinerary = trip_state.get('has_itinerary', False)
            current_itinerary = context.get('current_itinerary', None)
            
            # Build trip summary for context
            trip_summary = ""
            if user_prefs.get('from') or user_prefs.get('to'):
                trip_summary += f"\nTrip: {user_prefs.get('from', '?')} → {user_prefs.get('to', '?')}"
            if user_prefs.get('stay_city'):
                trip_summary += f" (staying in {user_prefs.get('stay_city')})"
            if user_prefs.get('dates'):
                trip_summary += f"\nDates: {user_prefs.get('dates')}"
            if user_prefs.get('duration_days'):
                trip_summary += f" ({user_prefs.get('duration_days')} days)"
            if user_prefs.get('travelers'):
                trip_summary += f"\nTravelers: {user_prefs.get('travelers')}"
            if selected_hotels:
                trip_summary += f"\nSelected Hotels: {', '.join(selected_hotels)}"
            if selected_transport:
                trip_summary += f"\nSelected Transport: {', '.join(selected_transport)}"
            if selected_destinations:
                trip_summary += f"\nSelected Places: {', '.join(selected_destinations)}"
            if has_itinerary:
                trip_summary += f"\nItinerary: Already generated"
            
            # Create a context-aware prompt for general queries
            # Check if user has an existing itinerary and might be asking to modify it
            itinerary_context = ""
            if current_itinerary:
                itinerary_context = f"""
=== CURRENT ITINERARY (User has an active plan) ===
{current_itinerary[:4000]}
...

IMPORTANT: If the user is asking to change, add, remove, or adjust ANYTHING about their trip/plan/itinerary,
you MUST provide a helpful response that acknowledges the change. Suggest what you'd modify and tell them
you're updating the plan. Treat ANY request that relates to their trip as a plan adjustment request.
Examples of plan adjustments: "I also want to visit a temple", "can we do scuba?", "add a spa day",
"I want more adventure", "less sightseeing", "what about trying local food?", "can we squeeze in shopping?"
"""

            prompt = f"""You are Triplix, an expert AI travel concierge for India. You are knowledgeable, helpful, and conversational.

=== CONVERSATION HISTORY ===
{recent_history}

=== USER'S CURRENT MESSAGE ===
{message}

=== USER'S TRAVEL PROFILE ===
- Budget: ₹{user_prefs.get('budget', 'Not set')}
- Destination: {user_prefs.get('destination', 'Not set')}
- Preferred Activities: {', '.join(user_prefs.get('activities', [])) if user_prefs.get('activities') else 'Not set'}
- Preferred Transport: {', '.join(user_prefs.get('transport', [])) if user_prefs.get('transport') else 'Not set'}
- Accommodation Style: {', '.join(user_prefs.get('accommodation', [])) if user_prefs.get('accommodation') else 'Not set'}
- Dietary: {', '.join(user_prefs.get('dietary', [])) if user_prefs.get('dietary') else 'Not set'}
- Companion: {user_prefs.get('companion', 'Not set')}
- Occasion: {user_prefs.get('occasion', 'Not set')}
{trip_summary}
{itinerary_context}

=== YOUR CAPABILITIES ===
You can help with:
1. General travel knowledge - tips, best times, culture, food, safety, customs, visa info
2. Destination recommendations - suggest places based on preferences
3. Budget advice - how to save money, budget breakdowns, cost estimates
4. Comparing options - help choose between destinations, hotels, transport
5. Local insights - hidden gems, local food, off-beat places
6. Travel planning advice - packing tips, what to expect, dos and don'ts
7. Answer ANY general question - you're a smart AI, answer confidently
8. Plan adjustments - if the user has an itinerary, help modify it on-the-fly (add activities, swap places, adjust timing, change preferences)

=== RESPONSE GUIDELINES ===
1. Be CONVERSATIONAL and HELPFUL. Answer the actual question asked.
2. If the user asks a general knowledge question (even non-travel), answer it well.
3. If the user wants to modify their trip and has an existing itinerary:
   - Acknowledge the change enthusiastically
   - Explain how you'd adjust the plan (which day, what time, what gets moved)
   - Provide the updated section of the plan with the change applied
   - Note any budget impact
   - Example: "Great idea! I'll add a morning temple visit on Day 2. I'll move the market visit to afternoon so everything fits. Here's the updated Day 2..."
4. If the user adds something extra (activity, place, food, experience):
   - Say YES and fit it into the plan naturally
   - Pick the best day/time slot
   - Adjust surrounding activities if needed
5. Use the conversation history to maintain context. If user refers to "that hotel" or "the first option", figure out what they mean.
6. Give specific, actionable answers. Not vague suggestions.
7. If user says casual things like "hi", "thanks", "ok", "cool" - respond naturally and briefly.
8. Keep responses concise but complete. 2-5 sentences for simple questions, longer for complex travel advice.
9. Use markdown formatting: **bold** for emphasis, bullet points for lists.
10. If you don't know something specific, say so honestly but offer related help.
11. NEVER say "I can't help with that" - always find a way to be useful."""

            # Get AI response
            response = model.generate_content(prompt)
            ai_response = response.text
        
        print(f"   AI Response generated ({len(ai_response)} chars)")
        
        return {
            "success": True,
            "response": ai_response,
            "agent": "gemini",
            "data": {},
            "page": page,
            "source": "ultra_simple_server"
        }
        
    except Exception as e:
        print(f"   Error: {e}")
        import traceback
        traceback.print_exc()
        return {
            "success": False,
            "error": str(e),
            "response": "I'm sorry, I encountered an error. Please try again.",
            "source": "ultra_simple_server"
        }

@app.post("/api/manager")
def handle_manager_request(request: AgentRequest):
    """
    Manager endpoint - generates complete itinerary based on user's swiped selections
    Coordinates all the selected hotels, transport, and destinations into a cohesive plan
    Can also UPDATE existing itineraries based on additional user requests
    """
    try:
        message = request.message
        context = request.context
        
        print(f"\n[MANAGER] Itinerary Request:")
        print(f"   Message: {message}")
        print(f"   Context keys: {list(context.keys())}")
        
        # ── Budget Page Handler ─────────────────────────────────────
        page = context.get('page', '')
        if page == 'budget' or context.get('action') == 'budget_chat':
            budget_info = context.get('budget_info', {})
            total_budget = budget_info.get('total_budget', 0)
            group_size = budget_info.get('group_size', 1)
            total_spent = budget_info.get('total_spent', 0)
            remaining = budget_info.get('remaining', total_budget)
            expenses = budget_info.get('expenses', [])
            allocation = budget_info.get('allocation', {})
            spent_by_category = budget_info.get('spent_by_category', {})

            budget_prompt = f"""You are Triplix Budget Manager AI. You ONLY help with budget and expense management. Do NOT generate itineraries or travel plans.

User message: "{message}"

Current Budget Status:
- Total Budget: ₹{total_budget:,.0f}
- Group Size: {group_size} people
- Per Person: ₹{total_budget/group_size if group_size > 0 else total_budget:,.0f}
- Total Spent: ₹{total_spent:,.0f}
- Remaining: ₹{remaining:,.0f}
- Expenses logged: {len(expenses)}
- Allocation: {json.dumps(allocation)}
- Spent by category: {json.dumps(spent_by_category)}

Instructions:
1. If the user is SETTING a budget (e.g. "my budget is 50000") → confirm the budget setup with a breakdown
2. If the user is LOGGING an expense (e.g. "spent 2000 on hotel", "paid 500 for lunch") → confirm the expense was recorded, show category, and updated remaining balance
3. If the user asks for a SUMMARY → show detailed budget summary with category-wise spending
4. If the user asks for TIPS → give money-saving travel tips
5. If the user wants to REDISTRIBUTE → suggest new allocation percentages
6. Keep responses SHORT and focused on budget only (3-5 lines max)
7. Use ₹ symbol and emojis for visual appeal
8. NEVER generate an itinerary or travel plan

Respond as a budget assistant only:"""

            print(f"   [BUDGET PAGE] Handling budget-specific request")
            model = genai.GenerativeModel('gemini-2.5-flash')
            response_obj = model.generate_content(budget_prompt)
            ai_response = response_obj.text

            return {
                "response": ai_response,
                "agent": "budget_tracker",
                "page": "budget",
                "data": {"budget_info": budget_info},
            }
        
        # ── Regular Itinerary Handler ───────────────────────────────
        trip_state = context.get('trip_state', {})
        selected_hotels = context.get('selected_hotels', trip_state.get('selected_hotels', []))
        selected_transport = context.get('selected_transport', trip_state.get('selected_transport', []))
        selected_destinations = context.get('selected_destinations', trip_state.get('selected_destinations', []))
        
        # Get travel details from context - use user_preferences if available
        user_prefs = context.get('user_preferences', {})
        from_location = context.get('from', user_prefs.get('from', 'Unknown'))
        to_location = context.get('to', user_prefs.get('destination', 'Unknown'))
        stay_city = context.get('stay_city', to_location)
        start_date = context.get('start_date', user_prefs.get('start_date', ''))
        end_date = context.get('end_date', user_prefs.get('end_date', ''))
        duration_days = context.get('duration_days', user_prefs.get('duration_days', 3))
        budget = context.get('budget', user_prefs.get('budget', 50000))
        travelers = context.get('travelers', user_prefs.get('travelers', 1))
        
        # Check if there's an existing itinerary to update
        existing_itinerary = context.get('current_itinerary', None)
        existing_itinerary_data = context.get('current_itinerary_data') or {}
        
        print(f"   From: {from_location} -> To: {to_location}")
        print(f"   Hotels: {selected_hotels}")
        print(f"   Transport: {selected_transport}")
        print(f"   Destinations: {selected_destinations}")
        print(f"   Duration: {duration_days} days")
        print(f"   Budget: Rs.{budget}")
        print(f"   Existing itinerary: {'Yes' if existing_itinerary else 'No'}")
        
        # Determine if this is an update request or new generation
        is_update_request = existing_itinerary is not None and message.lower() not in ['generate', 'create', 'make']
        dynamic_replan_keywords = [
            'replan', 're-plan', 'weather', 'forecast', 'rain', 'storm',
            'delay', 'delayed', 'disruption', 'reschedule', 'backup plan'
        ]
        is_dynamic_replan_request = bool(existing_itinerary) and any(
            keyword in message.lower() for keyword in dynamic_replan_keywords
        )
        
        # Build conversation history for context
        conversation_history = context.get('conversation_history', [])
        recent_chat = ""
        for msg in conversation_history[-8:]:
            if isinstance(msg, dict):
                role = msg.get('role', 'user')
                content = msg.get('content', '')[:300]
                recent_chat += f"{role}: {content}\n"
        
        itinerary_state = existing_itinerary_data if isinstance(existing_itinerary_data, dict) else {}

        if is_dynamic_replan_request:
            if not itinerary_state:
                itinerary_state = _build_itinerary_state(
                    from_location=from_location,
                    to_location=to_location,
                    stay_city=stay_city,
                    start_date=start_date,
                    end_date=end_date,
                    duration_days=duration_days,
                    selected_destinations=_normalize_string_list(selected_destinations),
                    selected_hotels=_normalize_string_list(selected_hotels),
                    selected_transport=_normalize_string_list(selected_transport),
                    budget=budget,
                    travelers=travelers,
                    itinerary_text=existing_itinerary or '',
                )

            print('   Running dynamic weather-aware replanning...')
            replan_result = _run_dynamic_replan(
                message=message,
                itinerary_text=existing_itinerary or '',
                itinerary_state=itinerary_state,
                recent_chat=recent_chat,
            )
            ai_response = replan_result['response']
            itinerary_state = replan_result['itinerary_state']
            risk_summary = replan_result['risk_summary']
        elif is_update_request:
            # Update existing itinerary based on user's request
            prompt = f"""You are Triplix, an expert travel planning AI. The user wants to MODIFY their existing itinerary.

**User's Request:** {message}

**Recent Conversation:**
{recent_chat}

**Current Itinerary:**
{existing_itinerary[:8000] if existing_itinerary else 'No itinerary yet'}

**Trip Details:**
- From: {from_location} to {to_location}
- Duration: {duration_days} days
- Travelers: {travelers} person(s)
- Budget: ₹{budget}
- Dates: {start_date.split('T')[0] if 'T' in str(start_date) and 'T' in start_date else start_date} to {end_date.split('T')[0] if 'T' in str(end_date) and 'T' in end_date else end_date}
- Selected Hotels: {', '.join(selected_hotels) if selected_hotels else 'None yet'}
- Selected Transport: {', '.join(selected_transport) if selected_transport else 'None yet'}
- Selected Places: {', '.join(selected_destinations) if selected_destinations else 'None yet'}

**Instructions:**
1. Understand EXACTLY what the user wants to change — they may ask in casual, informal language
2. If they want to change a hotel → swap it in the itinerary and adjust costs
3. If they want to change transport → update departure/arrival in the plan
4. If they want to add/remove activities → adjust the day schedule intelligently (find the best day/time slot)
5. If they want to swap days → rearrange the day order
6. If they want budget changes → adjust hotel/activity recommendations to fit
7. If they ask to add something new (spa, scuba, trek, temple, market, nightlife, etc.) → find the best day to fit it, adjust timing of other activities, and update the budget
8. If they say things like "I also want to...", "can we add...", "what about...", "how about..." → treat as additions to the plan
9. If they say "instead of X do Y" or "replace X with Y" → swap the activity/place
10. If they want more of something (adventure, relaxation, food, etc.) → add relevant activities and reduce less relevant ones
11. If they want less of something → remove those activities and suggest alternatives
12. If they mention timing preferences (morning, evening, etc.) → adjust the schedule
13. Keep the overall structure but apply ALL requested changes
14. Recalculate costs if prices change
15. Use emojis for visual appeal
16. At the end, briefly summarize what you changed

Provide the COMPLETE UPDATED itinerary (not just the changes). Make sure it's well-formatted."""

            print(f"   Updating existing itinerary...")
            model = genai.GenerativeModel('gemini-2.5-flash')
            response_obj = model.generate_content(prompt)
            ai_response = response_obj.text

            itinerary_state = _build_itinerary_state(
                from_location=from_location,
                to_location=to_location,
                stay_city=stay_city,
                start_date=start_date,
                end_date=end_date,
                duration_days=duration_days,
                selected_destinations=_normalize_string_list(selected_destinations),
                selected_hotels=_normalize_string_list(selected_hotels),
                selected_transport=_normalize_string_list(selected_transport),
                budget=budget,
                travelers=travelers,
                itinerary_text=ai_response,
            )
            risk_summary = itinerary_state.get('risky_days', [])
        else:
            # Create new comprehensive itinerary
            prompt = f"""You are a travel planning expert. Create a detailed {duration_days}-day itinerary for a trip from {from_location} to {to_location}.

**Trip Details:**
- From: {from_location}
- To: {to_location} (stay city)
- Duration: {duration_days} days
- Travelers: {travelers} person(s)
- Budget: ₹{budget}
- Dates: {start_date.split('T')[0] if 'T' in start_date else start_date} to {end_date.split('T')[0] if 'T' in end_date else end_date}

**Selected Options:**
- Hotels: {', '.join(selected_hotels) if selected_hotels else 'Budget-friendly hotels in ' + to_location}
- Transport: {', '.join(selected_transport) if selected_transport else 'Most convenient option'}
- Places to Visit: {', '.join(selected_destinations) if selected_destinations else 'Popular attractions in ' + to_location}

**Please create a day-by-day itinerary with:**
1. Daily schedule (morning, afternoon, evening)
2. Specific timings and activities
3. Estimated costs for each activity
4. Travel tips and recommendations
5. Restaurant suggestions for meals
6. Transportation between places

Format it in a clear, easy-to-read structure with emojis for visual appeal."""

            print(f"   Creating new itinerary from {from_location} to {to_location}...")

            model = genai.GenerativeModel('gemini-2.5-flash')
            response_obj = model.generate_content(prompt)
            ai_response = response_obj.text

            itinerary_state = _build_itinerary_state(
                from_location=from_location,
                to_location=to_location,
                stay_city=stay_city,
                start_date=start_date,
                end_date=end_date,
                duration_days=duration_days,
                selected_destinations=_normalize_string_list(selected_destinations),
                selected_hotels=_normalize_string_list(selected_hotels),
                selected_transport=_normalize_string_list(selected_transport),
                budget=budget,
                travelers=travelers,
                itinerary_text=ai_response,
            )
            risk_summary = itinerary_state.get('risky_days', [])
        
        print(f"[MANAGER] Generated itinerary ({len(ai_response)} chars)")
        
        return {
            "success": True,
            "response": ai_response,
            "agent": "manager",
            "is_update": is_update_request,
            "is_dynamic_replan": is_dynamic_replan_request,
            "replan": {
                "triggered": is_dynamic_replan_request,
                "risk_summary": risk_summary,
            },
            "itinerary": {
                "from": from_location,
                "to": to_location,
                "duration_days": duration_days,
                "total_cost_estimate": budget,
                "destinations": selected_destinations,
                "hotels": selected_hotels,
                "transport": selected_transport,
                "content": ai_response,  # Store the full itinerary for future updates
                "state": itinerary_state,
            },
            "data": {
                "itinerary_state": itinerary_state,
                "risk_summary": risk_summary,
            }
        }
        
    except Exception as e:
        print(f"[MANAGER ERROR] {e}")
        import traceback
        traceback.print_exc()
        return {
            "success": False,
            "error": str(e),
            "response": "I apologize, but I encountered an error creating your itinerary. However, I've saved all your selections!"
        }


@app.post("/api/itinerary/replan")
def replan_itinerary(request: AgentRequest):
    try:
        context = request.context or {}
        itinerary_text = context.get('current_itinerary', '')
        itinerary_state = context.get('current_itinerary_data') or context.get('itinerary_state') or {}

        if not itinerary_text:
            return {
                "success": False,
                "response": "No itinerary found to re-plan yet. Generate an itinerary first.",
                "error": "missing_itinerary"
            }

        if not itinerary_state:
            itinerary_state = _build_itinerary_state(
                from_location=context.get('from', 'Unknown'),
                to_location=context.get('to', context.get('stay_city', 'Unknown')),
                stay_city=context.get('stay_city', context.get('to', 'Unknown')),
                start_date=context.get('start_date', ''),
                end_date=context.get('end_date', ''),
                duration_days=context.get('duration_days', 3),
                selected_destinations=_normalize_string_list(context.get('selected_destinations', [])),
                selected_hotels=_normalize_string_list(context.get('selected_hotels', [])),
                selected_transport=_normalize_string_list(context.get('selected_transport', [])),
                budget=context.get('budget'),
                travelers=context.get('travelers'),
                itinerary_text=itinerary_text,
            )

        replan_result = _run_dynamic_replan(
            message=request.message,
            itinerary_text=itinerary_text,
            itinerary_state=itinerary_state,
            recent_chat='',
        )

        return {
            "success": True,
            "response": replan_result['response'],
            "agent": "dynamic_replanner",
            "replan": {
                "triggered": True,
                "risk_summary": replan_result['risk_summary'],
            },
            "itinerary": {
                "content": replan_result['response'],
                "state": replan_result['itinerary_state'],
            },
            "data": {
                "itinerary_state": replan_result['itinerary_state'],
                "risk_summary": replan_result['risk_summary'],
            }
        }
    except Exception as e:
        print(f"[REPLAN ERROR] {e}")
        return {
            "success": False,
            "error": str(e),
            "response": "I hit an error while re-planning your itinerary."
        }

_flight_schedule_cache: Dict[str, Any] = {}


@app.get("/api/flights/schedule")
def flight_schedule(origin: str, destination: str, date: str = ""):
    """Scheduled flights on a route, for the "which flight did you book?" step.

    Uses Gemini WITH Google Search grounding — not plain generation. That
    distinction is the whole point: asked cold, the model invents plausible
    flight numbers (it returned 6E 6541 / 6E 718 / QP 1361 for BLR-RPR, none
    of which match reality). Grounded, it returns 6E-405 and 6E-978, which are
    the same flights Aviasales' fare cache independently lists, cited to
    easemytrip/makemytrip/cleartrip.

    Exists because Aviasales' price cache is nearly empty on regional routes —
    BLR-RPR has one cached fare across all dates — so it can't supply
    candidates for a booking confirmation.

    Results are suggestions to help someone recognise the flight they already
    booked, NOT an availability or price source. Never present them as
    bookable.
    """
    key = f"{origin}_{destination}_{date}".lower()
    cached = _flight_schedule_cache.get(key)
    if cached is not None:
        return {"status": "success", "flights": cached, "source": "cache"}

    if not GOOGLE_API_KEY:
        return {"status": "success", "flights": [], "reason": "no_api_key"}

    when = f"on {date}" if date else ""
    prompt = (
        f"List scheduled passenger flights from {origin} to {destination} {when}. "
        "Return ONLY a JSON array, no prose. Each item must have exactly these "
        'keys: "airline" (name), "flight_number" (e.g. "6E 405"), '
        '"departure_time" ("HH:MM", 24-hour, local), "arrival_time" ("HH:MM"), '
        '"stops" (integer). Include only flights supported by your sources; '
        "return fewer rather than guessing."
    )

    try:
        from google import genai as genai_client
        from google.genai import types as genai_types

        client = genai_client.Client(api_key=GOOGLE_API_KEY)

        def _call():
            return client.models.generate_content(
                model="gemini-2.5-flash",
                contents=prompt,
                config=genai_types.GenerateContentConfig(
                    tools=[genai_types.Tool(
                        google_search=genai_types.GoogleSearch())],
                    # Reasoning off. This task is "read the search results and
                    # format them as JSON" — there is nothing to reason about,
                    # and it dominated the latency: 7-18s with thinking on
                    # versus a steady ~2.8s off, still grounded either way.
                    thinking_config=genai_types.ThinkingConfig(
                        thinking_budget=0),
                ),
            )

        # Grounded search is slow and highly variable — measured between 6s and
        # 37s on the same route. The client prefetches this while the user is
        # away on the partner site, so the wait is usually hidden; the cap only
        # stops a pathological call from hanging a worker.
        with ThreadPoolExecutor(max_workers=1) as executor:
            response = executor.submit(_call).result(timeout=45)

        text = (response.text or "").strip()
        if text.startswith("```"):
            text = text.split("```")[1]
            if text.startswith("json"):
                text = text[4:]
            text = text.strip()

        start, end = text.find("["), text.rfind("]")
        if start == -1 or end == -1:
            return {"status": "success", "flights": [], "reason": "unparseable"}

        raw = json.loads(text[start:end + 1])
        # Grounding is reported inconsistently: sometimes as source chunks,
        # sometimes only as the queries the model ran. Either proves it went
        # to the web rather than answering from memory.
        meta = (response.candidates[0].grounding_metadata
                if response.candidates else None)
        grounded = bool(meta and (getattr(meta, 'grounding_chunks', None)
                                  or getattr(meta, 'web_search_queries', None)))

        # Ungrounded output is exactly the fabrication case this endpoint
        # exists to avoid, so it's discarded rather than returned.
        if not grounded:
            print(f"[SCHEDULE] Ungrounded reply for {origin}->{destination}; discarding")
            return {"status": "success", "flights": [], "reason": "ungrounded"}

        flights = []
        for item in raw:
            number = str(item.get("flight_number", "")).strip()
            if not number:
                continue
            flights.append({
                "airline": str(item.get("airline", "")).strip(),
                "flight_number": number,
                "departure_time": str(item.get("departure_time", "")).strip(),
                "arrival_time": str(item.get("arrival_time", "")).strip(),
                "stops": int(item.get("stops") or 0),
            })

        _flight_schedule_cache[key] = flights
        print(f"[SCHEDULE] {len(flights)} grounded flights {origin}->{destination}")
        return {"status": "success", "flights": flights, "source": "grounded"}

    except Exception as e:
        print(f"[SCHEDULE] {type(e).__name__}: {e}")
        return {"status": "success", "flights": [], "reason": "error"}


@app.get("/hotels")
async def get_hotels(
    city: str = "",
    min_price: float = 0,
    max_price: float = 0,
    type: str = "",
    amenities: str = "",
):
    """Query-string hotel search, which is what the Flutter client calls.

    ApiService.searchHotels issues GET /hotels?city=... — a route that never
    existed here, so every call 404'd. The client treats that as a failure and
    falls through to its Aviasales handoff, which made a plain bug look like a
    slow redirect: the wait was a failed request, not the partner.

    Delegates to the POST handler so both entry points return the same shape
    and the same "no real hotels" semantics.
    """
    budget = max_price if max_price and max_price > 0 else 25000
    return await search_hotels(HotelSearchRequest(
        message=f"Find hotels in {city}" if city else "Find hotels",
        context={"city": city or "Goa", "budget": budget},
    ))


@app.post("/api/hotel/search")
async def search_hotels(request: HotelSearchRequest):
    try:
        city = request.context.get('city', 'Goa')
        budget = request.context.get('budget', 25000)
        message = request.message
        
        print(f"\n[HOTEL SEARCH] Search: {city}, Rs.{budget}")
        
        has_special = any(word in message.lower() for word in ['near', 'airport', 'beach', 'luxury', 'special'])
        has_special_request = 'special request:' in message.lower()

        # ── Try Amadeus live prices first ──
        if _amadeus_credentials_ready() and not has_special_request:
            check_in = (
                _parse_iso_date(request.context.get('check_in_date'))
                or _parse_iso_date(request.context.get('departure_date'))
                or (datetime.now().date() + timedelta(days=7)).isoformat()
            )
            check_out = (
                _parse_iso_date(request.context.get('check_out_date'))
                or _parse_iso_date(request.context.get('return_date'))
                or (datetime.fromisoformat(check_in) + timedelta(days=1)).date().isoformat()
            )

            if check_out <= check_in:
                check_out = (datetime.fromisoformat(check_in) + timedelta(days=1)).date().isoformat()

            amadeus_hotels = _fetch_amadeus_hotels(city=city, budget=budget, check_in=check_in, check_out=check_out)
            if amadeus_hotels:
                print(f"[AMADEUS SUCCESS] Live hotel offers: {len(amadeus_hotels)}")
                return {
                    'status': 'success',
                    'powered_by': 'Amadeus Hotel Offers',
                    'ai_used': False,
                    'hotels': amadeus_hotels,
                    'count': len(amadeus_hotels),
                    'live_prices': True,
                    'check_in_date': check_in,
                    'check_out_date': check_out,
                }

        # No in-app hotel inventory.
        #
        # The CSV held 65 rows across 15 cities with invented prices, so it
        # could only ever answer for a handful of destinations and the numbers
        # never matched what the user saw on clicking through. Rather than
        # serve that, hotel search returns nothing and the client hands off to
        # Aviasales, where the inventory and prices are real.
        #
        # hotels_india.csv is still read at startup for the trip-planner
        # endpoint (see the hotels_df use around line 2680); only hotel search
        # stopped using it.
        print(f"[HOTELS] Redirect-only: no in-app inventory for {city}")
        return {
            'status': 'success',
            'powered_by': 'none',
            'ai_used': False,
            'hotels': [],
            'count': 0,
            'message': f'Hotels for {city} are booked on Aviasales.',
        }

        # Gemini invents hotels — names, prices, ratings, amenities — for any
        # city missing from the CSV. Two reasons that's off by default:
        #
        #   1. Nothing it returns is bookable. The user is shown properties
        #      that may not exist, at prices nobody will honour.
        #   2. It is by far the slowest path in the app: 43-47s for Durg and
        #      Raipur, against ~2s for a CSV city. Since the client falls back
        #      to an Aviasales redirect when a search returns nothing, that
        #      whole wait sits between the tap and the redirect.
        #
        # Returning empty instead hands the user straight to Aviasales, where
        # the hotels are real and bookable. Set HOTELS_ALLOW_AI_GENERATED=1 to
        # restore the old behaviour for an offline demo.
        if not HOTELS_ALLOW_AI_GENERATED:
            print(f"[HOTELS] No real hotels for {city}; AI generation disabled")
            return {
                'status': 'success',
                'powered_by': 'none',
                'ai_used': False,
                'hotels': [],
                'count': 0,
                'message': f'No hotel data for {city}.',
            }

        # Use Gemini
        print(f"[GEMINI] Using Gemini AI...")
        prompt = f"""Find 5-8 hotels in {city}, India under ₹{budget}/night. Request: {message}

Return JSON with 'hotels' array. Each hotel must have:
- name: string
- type: string (Hotel/Resort/Hostel/etc.)
- price_per_night: number
- rating: number (1-5)
- amenities: array of strings
- description: detailed description (2-3 sentences)
- why_recommended: why this hotel is good for the user (2-3 sentences)
- nearby_attractions: array of 3-5 nearby attractions

Format: {{"hotels": [{{"name": "...", "type": "...", "price_per_night": 5000, "rating": 4.2, "amenities": ["WiFi", "Pool"], "description": "...", "why_recommended": "...", "nearby_attractions": ["Attraction1", "Attraction2"]}}]}}"""
        
        model = genai.GenerativeModel('gemini-2.5-flash')
        response = model.generate_content(prompt)
        text = response.text
        
        if '```json' in text:
            text = text.split('```json')[1].split('```')[0]
        elif '```' in text:
            text = text.split('```')[1].split('```')[0]
        
        result = json.loads(text.strip())
        hotels = result.get('hotels', [])
        
        # Photos for every hotel in one parallel pass, rather than a blocking
        # pair of Google calls inside the loop below.
        ai_images = get_hotel_images_bulk(
            [h.get('name', '') for h in hotels if 'image_url' not in h], city)

        # Ensure all required fields are present
        for hotel in hotels:
            if 'description' not in hotel:
                hotel['description'] = _create_hotel_description(hotel['name'], hotel.get('type', 'Hotel'), hotel.get('amenities', []), city, hotel.get('rating', 4.0))
            if 'why_recommended' not in hotel:
                hotel['why_recommended'] = _create_recommendation(hotel['name'], hotel.get('type', 'Hotel'), hotel.get('amenities', []), city, hotel.get('price_per_night', 5000), hotel.get('rating', 4.0))
            if 'nearby_attractions' not in hotel:
                hotel['nearby_attractions'] = _get_nearby_attractions(city)
            if 'image_url' not in hotel:
                hotel['image_url'] = ai_images.get(hotel.get('name', '')) or ''
        
        print(f"[GEMINI SUCCESS] Gemini: {len(hotels)} hotels")
        
        return {'status': 'success', 'powered_by': 'Gemini AI', 'ai_used': True, 'hotels': hotels, 'count': len(hotels)}
        
    except Exception as e:
        print(f"[ERROR] Error: {e}")
        return {"status": "error", "message": str(e)}

@app.post("/api/hotel/images")
def get_hotel_images(request: HotelSearchRequest):
    try:
        hotel_name = request.context.get('hotel_name', '')
        city = request.context.get('city', 'Goa')

        print(f"\n🖼️ Fetching images for: {hotel_name}, {city}")

        # Use Gemini to generate specific image search terms
        prompt = f"""
        Generate 10 specific search terms for finding authentic photos of "{hotel_name}" hotel in {city}, India.
        Focus on unique features like:
        - Hotel exterior and architecture
        - Lobby and reception
        - Rooms and suites
        - Restaurants and dining areas
        - Pool and spa areas
        - Unique amenities or nearby attractions

        Return ONLY a JSON array of specific search terms.
        Format: ["luxury hotel lobby {city}", "{hotel_name} presidential suite", "{hotel_name} infinity pool", ...]
        """

        model = genai.GenerativeModel('gemini-2.5-flash')
        response = model.generate_content(prompt)
        text = response.text

        if '```json' in text:
            text = text.split('```json')[1].split('```')[0]
        elif '```' in text:
            text = text.split('```')[1].split('```')[0]

        search_terms = json.loads(text.strip())

        # Generate image URLs using Google Places API for real photos
        image_urls = []
        for term in search_terms[:5]:
            try:
                search_url = "https://places.googleapis.com/v1/places:searchText"
                headers = {
                    'Content-Type': 'application/json',
                    'X-Goog-Api-Key': GOOGLE_PLACES_API_KEY,
                    'X-Goog-FieldMask': 'places.photos'
                }
                resp = requests.post(search_url, headers=headers,
                    json={"textQuery": f"{term}", "maxResultCount": 1},
                    timeout=5
                ).json()
                places = resp.get('places', [])
                if places and places[0].get('photos'):
                    for photo in places[0]['photos'][:2]:
                        photo_name = photo.get('name', '')
                        if photo_name:
                            media_url = f"https://places.googleapis.com/v1/{photo_name}/media?maxWidthPx=800&skipHttpRedirect=true&key={GOOGLE_PLACES_API_KEY}"
                            try:
                                media_resp = requests.get(media_url, timeout=5).json()
                                direct_url = media_resp.get('photoUri', '')
                                if direct_url:
                                    image_urls.append(direct_url)
                            except:
                                pass
            except:
                pass

        # Ensure we have enough images with fallbacks
        hotel_fallbacks = [
            "https://images.unsplash.com/photo-1566073771259-6a8506099945?w=800&h=600&fit=crop",
            "https://images.unsplash.com/photo-1582719508461-905c673771fd?w=800&h=600&fit=crop",
            "https://images.unsplash.com/photo-1542314831-068cd1dbfeeb?w=800&h=600&fit=crop",
            "https://images.unsplash.com/photo-1551882547-ff40c63fe5fa?w=800&h=600&fit=crop",
            "https://images.unsplash.com/photo-1520250497591-112f2f40a3f4?w=800&h=600&fit=crop",
            "https://images.unsplash.com/photo-1571896349842-33c89424de2d?w=800&h=600&fit=crop",
            "https://images.unsplash.com/photo-1455587734955-081b22074882?w=800&h=600&fit=crop",
            "https://images.unsplash.com/photo-1564501049412-61c2a3083791?w=800&h=600&fit=crop",
            "https://images.unsplash.com/photo-1578683010236-d716f9a3f461?w=800&h=600&fit=crop",
            "https://images.unsplash.com/photo-1445019980597-93fa8acb246c?w=800&h=600&fit=crop",
        ]
        while len(image_urls) < 10:
            image_urls.append(hotel_fallbacks[len(image_urls) % len(hotel_fallbacks)])

        return {
            'status': 'success',
            'hotel_name': hotel_name,
            'city': city,
            'images': image_urls[:10],
            'powered_by': 'Gemini AI + Google Places'
        }

    except Exception as e:
        print(f"❌ Image fetch error: {e}")
        # Return fallback images
        fallback_images = [
            "https://images.unsplash.com/photo-1566073771259-6a8506099945?w=800&h=600&fit=crop",
            "https://images.unsplash.com/photo-1582719508461-905c673771fd?w=800&h=600&fit=crop",
            "https://images.unsplash.com/photo-1542314831-068cd1dbfeeb?w=800&h=600&fit=crop",
            "https://images.unsplash.com/photo-1551882547-ff40c63fe5fa?w=800&h=600&fit=crop",
            "https://images.unsplash.com/photo-1520250497591-112f2f40a3f4?w=800&h=600&fit=crop",
            "https://images.unsplash.com/photo-1571896349842-33c89424de2d?w=800&h=600&fit=crop",
            "https://images.unsplash.com/photo-1455587734955-081b22074882?w=800&h=600&fit=crop",
            "https://images.unsplash.com/photo-1564501049412-61c2a3083791?w=800&h=600&fit=crop",
            "https://images.unsplash.com/photo-1578683010236-d716f9a3f461?w=800&h=600&fit=crop",
            "https://images.unsplash.com/photo-1445019980597-93fa8acb246c?w=800&h=600&fit=crop",
        ]

        return {
            'status': 'fallback',
            'hotel_name': hotel_name,
            'city': city,
            'images': fallback_images,
            'message': 'Using curated hotel images'
        }

@app.post("/api/analyze-preferences")
def analyze_preferences(request: dict):
    """
    Analyze user preferences and provide AI-powered travel recommendations
    Used by the AI Assistant page in Flutter app
    """
    try:
        print(f"\n🤖 [AI ASSISTANT] ANALYZE PREFERENCES REQUEST:")
        
        # Extract all preference data from request
        destination = request.get('destination', {})
        budget = request.get('budget', {})
        activities = request.get('activities', {})
        transport = request.get('transport', {})
        allocation = request.get('allocation', {})
        context = request.get('context', {})
        
        # Build comprehensive message from user preferences
        message_parts = []
        
        # Destination preferences
        if destination:
            location_types = destination.get('location_types', [])
            climate = destination.get('climate', '')
            experience = destination.get('experience_level', '')
            
            if location_types:
                message_parts.append(f"Preferred locations: {', '.join(location_types)}")
            if climate:
                message_parts.append(f"Climate preference: {climate}")
            if experience:
                message_parts.append(f"Experience level: {experience}")
        
        # Budget information
        if budget:
            amount = budget.get('amount', 0)
            num_people = budget.get('num_people', 1)
            tier = budget.get('tier', 'mid_range')
            
            if amount > 0:
                message_parts.append(f"Budget: ₹{amount:,} for {num_people} person(s)")
                message_parts.append(f"Budget tier: {tier}")
        
        # Activities
        if activities:
            selected = activities.get('selected', [])
            intensity = activities.get('intensity', 'moderate')
            
            if selected:
                message_parts.append(f"Activities: {', '.join(selected)}")
                message_parts.append(f"Activity intensity: {intensity}")
        
        # Transport preferences
        if transport:
            modes = transport.get('modes', [])
            travel_class = transport.get('class', 'economy')
            
            if modes:
                message_parts.append(f"Transport modes: {', '.join(modes)}")
                message_parts.append(f"Travel class: {travel_class}")
        
        # Context and special requirements
        if context:
            dietary = context.get('dietary_requirements', [])
            accessibility = context.get('accessibility_needs', [])
            companions = context.get('travel_companions', '')
            special = context.get('special_requests', '')
            
            if dietary:
                message_parts.append(f"Dietary: {', '.join(dietary)}")
            if accessibility:
                message_parts.append(f"Accessibility needs: {', '.join(accessibility)}")
            if companions:
                message_parts.append(f"Traveling with: {companions}")
            if special:
                message_parts.append(f"Special occasion: {special}")
        
        # Build prompt for Gemini
        full_context = "\n".join(message_parts)
        
        prompt = f"""You are a helpful travel assistant. Based on the following user preferences, provide personalized travel recommendations:

{full_context}

Please provide:
1. A comprehensive travel plan summary
2. Recommended destinations
3. Suggested accommodations
4. Activity recommendations
5. Budget breakdown advice
6. Travel tips specific to their preferences

Format your response in a friendly, conversational tone."""

        print(f"   📝 Generated prompt with {len(message_parts)} preference points")
        
        # Call Gemini AI for analysis
        model = genai.GenerativeModel('gemini-2.5-flash')
        response = model.generate_content(prompt)
        ai_response = response.text
        
        print(f"   ✅ AI Analysis complete ({len(ai_response)} chars)")
        
        # Structure the response for Flutter app
        return {
            "success": True,
            "summary": {
                "title": "AI Travel Analysis Complete",
                "content": ai_response
            },
            "insights": {
                "recommendations": [
                    "Personalized recommendations based on your preferences",
                    "Budget-friendly options within your range",
                    "Activities matching your interests"
                ],
                "warnings": []
            },
            "next_steps": [
                "Review the detailed recommendations above",
                "Explore the swipe feature to discover destinations",
                "Set up your budget tracker for better planning",
                "Book your preferred accommodations and activities"
            ]
        }
        
    except Exception as e:
        print(f"   ❌ Error analyzing preferences: {e}")
        import traceback
        traceback.print_exc()
        return {
            "success": False,
            "error": str(e),
            "summary": {
                "title": "Analysis Error",
                "content": f"I encountered an error while analyzing your preferences. Please try again. Error: {str(e)}"
            },
            "insights": {
                "recommendations": [],
                "warnings": ["Please try again or contact support if the issue persists"]
            },
            "next_steps": []
        }

@app.post("/api/transport/search")
def search_transport_for_swipe(request: dict):
    """
    AI-powered transport suggestions for swipe feature
    Generates realistic flight/train/bus options with actual-looking numbers
    """
    try:
        from_city = request.get('from_city', '')
        to_city = request.get('to_city', '')
        budget_range = request.get('budget', 'moderate')
        
        print(f"\n✈️ [TRANSPORT SEARCH] Generating AI transport suggestions: {from_city} -> {to_city}, Budget: {budget_range}")
        
        # Create AI prompt for transport generation
        transport_prompt = f"""Generate realistic transport options from {from_city} to {to_city} in India.
        
Please provide EXACTLY 6 transport options in JSON format:
- 2 flights (use real airline names like IndiGo, Air India, SpiceJet with flight numbers like 6E-2031, AI-7821, SG-8456)
- 3 trains (use real train names like Rajdhani Express, Shatabdi Express, Duronto Express with numbers like 12432, 12010, 12213)
- 1 luxury bus (use operators like Volvo Multi-Axle AC, Mercedes Benz Sleeper)

Make the timings realistic for the route distance:
- Short routes (< 500km): Flights 1-2 hours, Trains 8-12 hours, Bus 10-15 hours
- Medium routes (500-1000km): Flights 2-3 hours, Trains 12-18 hours, Bus 15-20 hours
- Long routes (> 1000km): Flights 3-4 hours, Trains 18-24 hours, Bus 20-30 hours

Return ONLY valid JSON array (no markdown, no explanation):
[
  {{
    "type": "flight",
    "carrier": "IndiGo",
    "number": "6E-2031",
    "departure_time": "06:30 AM",
    "arrival_time": "08:45 AM",
    "duration": "2h 15min",
    "class": "Economy",
    "price": 10000,
    "description": "Non-stop flight, In-flight meals"
  }},
  ...
]

Budget context: {budget_range}
- If budget is "budget/low": Prioritize trains and buses, lower flight prices
- If budget is "moderate/medium": Mix of all options with reasonable prices
- If budget is "luxury/high": Premium flights, AC First class trains, luxury buses"""

        # Call Gemini AI
        model = genai.GenerativeModel("gemini-2.5-flash")
        response = model.generate_content(transport_prompt)
        response_text = response.text.strip()
        
        # Clean response
        if response_text.startswith('```json'):
            response_text = response_text[7:]
        if response_text.startswith('```'):
            response_text = response_text[3:]
        if response_text.endswith('```'):
            response_text = response_text[:-3]
        response_text = response_text.strip()
        
        # Parse JSON
        transport_options = json.loads(response_text)
        
        # Convert to Flutter format
        flutter_suggestions = []
        for idx, option in enumerate(transport_options):
            transport_type = option.get('type', 'flight')
            carrier = option.get('carrier', 'Unknown')
            number = option.get('number', '')
            departure = option.get('departure_time', '')
            arrival = option.get('arrival_time', '')
            duration = option.get('duration', '')
            price = option.get('price', 0)
            travel_class = option.get('class', 'Economy')
            description = option.get('description', '')
            
            # Create title based on type
            if transport_type == 'flight':
                title = f"{carrier} {number}"
                subtitle = f"{from_city} -> {to_city}"
            elif transport_type == 'train':
                title = f"{carrier} {number}"
                subtitle = f"{from_city} -> {to_city}"
            else:  # bus
                title = carrier
                subtitle = f"{from_city} -> {to_city}"
            
            # Get transport icon emoji
            icon = "✈️" if transport_type == "flight" else "🚂" if transport_type == "train" else "🚌"
            
            flutter_suggestions.append({
                'id': f'transport_{idx+1}',
                'type': transport_type,
                'title': title,
                'subtitle': subtitle,
                'description': f"{icon} {departure} - {arrival} ({duration})\n{travel_class} | {description}",
                'price': f"₹{price:,}",
                'image': _get_transport_image(transport_type, carrier),
                'stage': 'transport',
                'details': {
                    'carrier': carrier,
                    'number': number,
                    'departure_time': departure,
                    'arrival_time': arrival,
                    'duration': duration,
                    'class': travel_class,
                    'from_city': from_city,
                    'to_city': to_city
                }
            })
        
        print(f"   ✅ Generated {len(flutter_suggestions)} AI-powered transport options")
        
        return {
            'status': 'success',
            'suggestions': flutter_suggestions,
            'from_city': from_city,
            'to_city': to_city,
            'count': len(flutter_suggestions),
            'powered_by': 'Gemini AI'
        }
        
    except json.JSONDecodeError as je:
        print(f"   ❌ JSON Parse Error: {je}")
        print(f"   Raw response: {response_text[:500]}")
        # Return fallback hardcoded options
        return _get_fallback_transport(from_city, to_city)
        
    except Exception as e:
        print(f"   ❌ Transport search error: {e}")
        import traceback
        traceback.print_exc()
        return _get_fallback_transport(from_city, to_city)


def _get_transport_image(transport_type: str, carrier: str):
    """Get a relevant image URL for transport based on type.
    
    Google Places search for carrier names (e.g. 'IndiGo flight India')
    returns random storefront/office photos, not actual planes or trains.
    Use curated, type-specific Unsplash images instead for reliable results.
    """
    cache_key = f"transport_{transport_type}_{carrier}"
    if cache_key in _photo_cache:
        return _photo_cache[cache_key]

    # Curated transport images by type — guaranteed to show real vehicles
    fallback = {
        'flight': [
            "https://images.unsplash.com/photo-1436491865332-7a61a109db05?w=800&h=600&fit=crop",
            "https://images.unsplash.com/photo-1569154941061-e231b4725ef1?w=800&h=600&fit=crop",
            "https://images.unsplash.com/photo-1556388158-158ea5ccacbd?w=800&h=600&fit=crop",
            "https://images.unsplash.com/photo-1529074606757-b27d20274956?w=800&h=600&fit=crop",
        ],
        'train': [
            "https://images.unsplash.com/photo-1540746238299-83c4b1673953?w=800&h=600&fit=crop",
            "https://images.unsplash.com/photo-1474487548417-781cb71495f3?w=800&h=600&fit=crop",
            "https://images.unsplash.com/photo-1532105956626-9569c03602f6?w=800&h=600&fit=crop",
            "https://images.unsplash.com/photo-1555396273-367ea4eb4db5?w=800&h=600&fit=crop",
        ],
        'bus': [
            "https://images.unsplash.com/photo-1544620347-c4fd4a3d5957?w=800&h=600&fit=crop",
            "https://images.unsplash.com/photo-1570125909232-eb263c188f7e?w=800&h=600&fit=crop",
        ],
    }
    images = fallback.get(transport_type, fallback['flight'])
    idx = abs(hash(carrier)) % len(images)
    url = images[idx]
    _photo_cache[cache_key] = url
    return url


def _get_fallback_transport(from_city: str, to_city: str):
    """Fallback transport when AI fails"""
    return {
        'status': 'fallback',
        'suggestions': [
            {
                'id': 'transport_1',
                'type': 'flight',
                'title': 'IndiGo 6E-2031',
                'subtitle': f'{from_city} -> {to_city}',
                'description': '✈️ 06:30 AM - 08:45 AM (2h 15min)\nEconomy | Non-stop, In-flight meals',
                'price': '₹10,000',
                'image': 'https://images.unsplash.com/photo-1436491865332-7a61a109db05?w=800&h=600&fit=crop',
                'stage': 'transport',
                'details': {
                    'carrier': 'IndiGo',
                    'number': '6E-2031',
                    'departure_time': '06:30 AM',
                    'arrival_time': '08:45 AM',
                    'duration': '2h 15min',
                    'class': 'Economy',
                    'from_city': from_city,
                    'to_city': to_city
                }
            },
            {
                'id': 'transport_2',
                'type': 'flight',
                'title': 'Air India AI-7821',
                'subtitle': f'{from_city} -> {to_city}',
                'description': '✈️ 02:15 PM - 04:25 PM (2h 10min)\nEconomy | Non-stop, Complimentary meals',
                'price': '₹8,500',
                'image': 'https://images.unsplash.com/photo-1569154941061-e231b4725ef1?w=800&h=600&fit=crop',
                'stage': 'transport',
                'details': {
                    'carrier': 'Air India',
                    'number': 'AI-7821',
                    'departure_time': '02:15 PM',
                    'arrival_time': '04:25 PM',
                    'duration': '2h 10min',
                    'class': 'Economy',
                    'from_city': from_city,
                    'to_city': to_city
                }
            },
            {
                'id': 'transport_3',
                'type': 'train',
                'title': 'Rajdhani Express 12432',
                'subtitle': f'{from_city} -> {to_city}',
                'description': '🚂 05:30 PM - 11:45 AM+1 (18h 15min)\n2AC | Meals included, Premium service',
                'price': '₹3,500',
                'image': 'https://images.unsplash.com/photo-1540746238299-83c4b1673953?w=800&h=600&fit=crop',
                'stage': 'transport',
                'details': {
                    'carrier': 'Rajdhani Express',
                    'number': '12432',
                    'departure_time': '05:30 PM',
                    'arrival_time': '11:45 AM+1',
                    'duration': '18h 15min',
                    'class': '2AC',
                    'from_city': from_city,
                    'to_city': to_city
                }
            },
            {
                'id': 'transport_4',
                'type': 'train',
                'title': 'Shatabdi Express 12010',
                'subtitle': f'{from_city} -> {to_city}',
                'description': '🚂 06:00 AM - 09:15 PM (15h 15min)\nCC | Meals, Comfortable seating',
                'price': '₹2,500',
                'image': 'https://images.unsplash.com/photo-1474487548417-781cb71495f3?w=800&h=600&fit=crop',
                'stage': 'transport',
                'details': {
                    'carrier': 'Shatabdi Express',
                    'number': '12010',
                    'departure_time': '06:00 AM',
                    'arrival_time': '09:15 PM',
                    'duration': '15h 15min',
                    'class': 'CC',
                    'from_city': from_city,
                    'to_city': to_city
                }
            },
            {
                'id': 'transport_5',
                'type': 'train',
                'title': 'Duronto Express 12213',
                'subtitle': f'{from_city} -> {to_city}',
                'description': '🚂 11:30 PM - 05:45 PM+1 (18h 15min)\n3AC | Overnight journey, Meals available',
                'price': '₹3,000',
                'image': 'https://images.unsplash.com/photo-1532105956626-9569c03602f6?w=800&h=600&fit=crop',
                'stage': 'transport',
                'details': {
                    'carrier': 'Duronto Express',
                    'number': '12213',
                    'departure_time': '11:30 PM',
                    'arrival_time': '05:45 PM+1',
                    'duration': '18h 15min',
                    'class': '3AC',
                    'from_city': from_city,
                    'to_city': to_city
                }
            },
            {
                'id': 'transport_6',
                'type': 'bus',
                'title': 'Volvo Multi-Axle AC',
                'subtitle': f'{from_city} -> {to_city}',
                'description': '🚌 06:00 PM - 02:00 PM+1 (20h)\nSleeper | WiFi, Charging points, Onboard restroom',
                'price': '₹2,000',
                'image': 'https://images.unsplash.com/photo-1544620347-c4fd4a3d5957?w=800&h=600&fit=crop',
                'stage': 'transport',
                'details': {
                    'carrier': 'Volvo Multi-Axle AC',
                    'number': 'VOLVO-AC-101',
                    'departure_time': '06:00 PM',
                    'arrival_time': '02:00 PM+1',
                    'duration': '20h',
                    'class': 'Sleeper',
                    'from_city': from_city,
                    'to_city': to_city
                }
            }
        ],
        'from_city': from_city,
        'to_city': to_city,
        'count': 6,
        'message': 'Using curated transport options'
    }

@app.post("/api/travel/search")
def search_travel(request: TravelBookingRequest):
    try:
        mode = request.mode.lower()
        from_city = request.from_city.lower()
        to_city = request.to_city.lower() if request.to_city else None
        departure_date = request.departure_date
        return_date = request.return_date
        passengers = request.passengers
        travel_class = request.travel_class.lower()
        preferences = request.preferences
        extras = request.extras
        travel_type = request.travel_type.lower()
        accessibility = request.accessibility
        duration_hours = request.duration_hours

        print(f"\n🚗 Travel Search: {mode} from {from_city}" + (f" to {to_city}" if to_city else "") + f", {passengers} passengers, {travel_class} class")

        # Route to appropriate handler based on mode
        if mode == "flight":
            return _search_flights(from_city, to_city, departure_date, return_date, passengers, travel_class, preferences, extras, travel_type, accessibility)
        elif mode == "train":
            return _search_trains(from_city, to_city, departure_date, return_date, passengers, travel_class, preferences, extras, travel_type, accessibility)
        elif mode == "bus":
            return _search_buses(from_city, to_city, departure_date, return_date, passengers, travel_class, preferences, extras, travel_type, accessibility)
        elif mode == "car_rental":
            return _search_car_rentals(from_city, departure_date, return_date, passengers, travel_class, preferences, extras, duration_hours, accessibility)
        elif mode == "taxi":
            return _search_taxis(from_city, to_city, departure_date, passengers, travel_class, preferences, extras, accessibility)
        elif mode == "bike_scooter":
            return _search_bikes(from_city, to_city, departure_date, passengers, travel_class, preferences, extras, duration_hours, accessibility)
        else:
            return {"status": "error", "message": f"Unsupported travel mode: {mode}"}

    except Exception as e:
        print(f"❌ Travel search error: {e}")
        return {"status": "error", "message": str(e)}

@app.post("/api/flights/search")
def search_flights_direct(request: FlightSearchRequest):
    """Direct flight search endpoint (Amadeus -> CSV -> AI fallback)."""
    from_city = request.from_city.lower().strip()
    to_city = request.to_city.lower().strip()
    travel_class = (request.flight_class or 'economy').lower().strip()
    return _search_flights(
        from_city=from_city,
        to_city=to_city,
        departure_date=request.departure_date,
        return_date=request.return_date,
        passengers=max(1, int(request.passengers or 1)),
        travel_class=travel_class,
        preferences=request.preferences or [],
        extras=[],
        travel_type='round_trip' if request.return_date else 'one_way',
        accessibility=[],
    )

# ============================================================
# GOOGLE PLACES API (NEW) ENDPOINTS
# ============================================================

@app.get("/api/places/hotels")
def search_hotel_names(query: str, city: str = "", limit: int = 6):
    """Real hotel names matching a partial query, for the "which hotel did you
    book?" confirmation.

    Deliberately Google Places rather than an LLM: the user is naming a
    property they have actually booked, so every suggestion must be a real
    place. A model asked to complete "hotel cit" would happily invent
    "Hotel Citadel Grand", and the user would tap it.

    Tolerant of typos by design — Places does its own fuzzy matching, so
    "hotal citi lite" still finds "Hotel City Lite".
    """
    try:
        q = (query or "").strip()
        if len(q) < 2 or not GOOGLE_PLACES_API_KEY:
            return {"status": "success", "hotels": []}

        text_query = f"{q} hotel in {city}" if city else f"{q} hotel"
        field_mask = "places.displayName,places.formattedAddress,places.rating"
        resp = requests.post(
            "https://places.googleapis.com/v1/places:searchText",
            headers=_google_headers(field_mask),
            json={"textQuery": text_query,
                  "maxResultCount": max(1, min(limit, 10))},
            timeout=4,
        ).json()

        hotels = []
        for place in resp.get("places", []):
            name = str(place.get("displayName", {}).get("text", "")).strip()
            if not name:
                continue
            hotels.append({
                "name": name,
                "address": str(place.get("formattedAddress", "")).strip(),
                "rating": place.get("rating"),
            })

        return {"status": "success", "hotels": hotels}
    except Exception as e:
        print(f"[PLACES HOTELS] {e}")
        # Never fatal: the field stays free-text if lookup fails.
        return {"status": "error", "message": str(e), "hotels": []}


@app.post("/api/places/details")
def get_place_details(request: dict):
    """Get real Google Places details: photos, reviews, ratings, location (New API)"""
    try:
        place_name = request.get('name', '')
        city = request.get('city', '')
        query = f"{place_name} {city} India"

        print(f"\n📍 [PLACES] Getting details for: {query}")

        # Use Places API (New) - Text Search
        search_url = "https://places.googleapis.com/v1/places:searchText"
        field_mask = "places.id,places.displayName,places.formattedAddress,places.location,places.rating,places.userRatingCount,places.reviews,places.photos,places.websiteUri,places.nationalPhoneNumber,places.googleMapsUri,places.regularOpeningHours,places.types"
        
        search_resp = requests.post(search_url, 
            headers=_google_headers(field_mask),
            json={"textQuery": query, "maxResultCount": 1}
        ).json()

        places_list = search_resp.get('places', [])
        if not places_list:
            return {"status": "not_found", "message": f"No place found for '{query}'"}

        result = places_list[0]

        # Build photo URLs (new format)
        photos = []
        for photo in result.get('photos', [])[:10]:
            photo_name = photo.get('name', '')
            if photo_name:
                photos.append(f"https://places.googleapis.com/v1/{photo_name}/media?maxWidthPx=800&key={GOOGLE_PLACES_API_KEY}")

        # Format reviews
        reviews = []
        for review in result.get('reviews', [])[:5]:
            reviews.append({
                'author': review.get('authorAttribution', {}).get('displayName', 'Anonymous'),
                'rating': review.get('rating', 0),
                'text': review.get('text', {}).get('text', ''),
                'time': review.get('relativePublishTimeDescription', '')
            })

        location = result.get('location', {})

        display_name = result.get('displayName', {}).get('text', place_name)
        rating = result.get('rating', 0)
        print(f"   ✅ Found: {display_name} | Rating: {rating} | {len(photos)} photos | {len(reviews)} reviews")

        return {
            "status": "success",
            "place": {
                "name": display_name,
                "address": result.get('formattedAddress', ''),
                "rating": rating,
                "total_ratings": result.get('userRatingCount', 0),
                "lat": location.get('latitude', 0),
                "lng": location.get('longitude', 0),
                "photos": photos,
                "reviews": reviews,
                "website": result.get('websiteUri', ''),
                "phone": result.get('nationalPhoneNumber', ''),
                "google_maps_url": result.get('googleMapsUri', ''),
                "opening_hours": result.get('regularOpeningHours', {}).get('weekdayDescriptions', []),
                "types": result.get('types', [])
            }
        }

    except Exception as e:
        print(f"   ❌ Places error: {e}")
        return {"status": "error", "message": str(e)}


@app.post("/api/places/nearby")
def get_nearby_places(request: dict):
    """Find nearby restaurants, ATMs, attractions around a location (New API)"""
    try:
        lat = request.get('lat', 0)
        lng = request.get('lng', 0)
        place_type = request.get('type', 'restaurant')  # restaurant, atm, tourist_attraction, hospital, pharmacy
        city = request.get('city', '')
        radius = request.get('radius', 2000)  # meters

        print(f"\n🔍 [NEARBY] Searching {place_type}s near ({lat},{lng}) / {city}")

        # If no lat/lng but city provided, use text search to geocode
        if (lat == 0 and lng == 0) and city:
            geo_url = "https://places.googleapis.com/v1/places:searchText"
            geo_resp = requests.post(geo_url,
                headers=_google_headers("places.location"),
                json={"textQuery": f"{city}, India", "maxResultCount": 1}
            ).json()
            geo_places = geo_resp.get('places', [])
            if geo_places:
                loc = geo_places[0].get('location', {})
                lat, lng = loc.get('latitude', 0), loc.get('longitude', 0)

        if lat == 0 and lng == 0:
            return {"status": "error", "message": "Could not determine location. Provide lat/lng or a valid city."}

        # Places API (New) - Nearby Search
        nearby_url = "https://places.googleapis.com/v1/places:searchNearby"
        field_mask = "places.id,places.displayName,places.formattedAddress,places.location,places.rating,places.userRatingCount,places.photos,places.regularOpeningHours,places.types,places.priceLevel"

        nearby_resp = requests.post(nearby_url,
            headers=_google_headers(field_mask),
            json={
                "includedTypes": [place_type],
                "maxResultCount": 15,
                "locationRestriction": {
                    "circle": {
                        "center": {"latitude": lat, "longitude": lng},
                        "radius": float(radius)
                    }
                }
            }
        ).json()

        places = []
        for place in nearby_resp.get('places', []):
            photo_url = None
            if place.get('photos'):
                photo_name = place['photos'][0].get('name', '')
                if photo_name:
                    photo_url = f"https://places.googleapis.com/v1/{photo_name}/media?maxWidthPx=400&key={GOOGLE_PLACES_API_KEY}"

            loc = place.get('location', {})
            places.append({
                'name': place.get('displayName', {}).get('text', ''),
                'address': place.get('formattedAddress', ''),
                'rating': place.get('rating', 0),
                'total_ratings': place.get('userRatingCount', 0),
                'lat': loc.get('latitude', 0),
                'lng': loc.get('longitude', 0),
                'photo': photo_url,
                'open_now': place.get('regularOpeningHours', {}).get('openNow', None),
                'types': place.get('types', []),
                'price_level': place.get('priceLevel', None)
            })

        print(f"   ✅ Found {len(places)} nearby {place_type}s")

        return {
            "status": "success",
            "type": place_type,
            "count": len(places),
            "places": places
        }

    except Exception as e:
        print(f"   ❌ Nearby search error: {e}")
        return {"status": "error", "message": str(e)}


# ============================================================
# GOOGLE DIRECTIONS & DISTANCE MATRIX (Legacy API)
# ============================================================

@app.post("/api/maps/directions")
def get_directions(request: dict):
    """Get route directions between two cities with distance, duration, steps"""
    try:
        origin = request.get('origin', '')
        destination = request.get('destination', '')
        mode = request.get('mode', 'driving')  # driving, transit, walking

        print(f"\n🗺️ [DIRECTIONS] {origin} → {destination} ({mode})")

        directions_url = "https://maps.googleapis.com/maps/api/directions/json"
        resp = requests.get(directions_url, params={
            'origin': f"{origin}, India",
            'destination': f"{destination}, India",
            'mode': mode,
            'key': GOOGLE_PLACES_API_KEY
        }).json()

        if resp.get('status') != 'OK' or not resp.get('routes'):
            return {"status": "no_route", "message": resp.get('error_message', f"No route found from {origin} to {destination}")}

        route = resp['routes'][0]
        leg = route['legs'][0]

        steps = []
        for step in leg.get('steps', [])[:20]:
            steps.append({
                'instruction': step.get('html_instructions', '').replace('<b>', '').replace('</b>', '').replace('<div style="font-size:0.9em">', ' ').replace('</div>', ''),
                'distance': step['distance']['text'],
                'duration': step['duration']['text'],
                'travel_mode': step.get('travel_mode', mode)
            })

        print(f"   ✅ Distance: {leg['distance']['text']} | Duration: {leg['duration']['text']}")

        return {
            "status": "success",
            "origin": leg.get('start_address', origin),
            "destination": leg.get('end_address', destination),
            "distance": leg['distance']['text'],
            "duration": leg['duration']['text'],
            "distance_meters": leg['distance']['value'],
            "duration_seconds": leg['duration']['value'],
            "steps": steps,
            "overview_polyline": route.get('overview_polyline', {}).get('points', ''),
            "mode": mode
        }

    except Exception as e:
        print(f"   ❌ Directions error: {e}")
        return {"status": "error", "message": str(e)}


@app.post("/api/maps/distance")
def get_distance_matrix(request: dict):
    """Get distance and travel time between multiple cities"""
    try:
        origins = request.get('origins', [])
        destinations = request.get('destinations', [])

        if isinstance(origins, str):
            origins = [origins]
        if isinstance(destinations, str):
            destinations = [destinations]

        origins_str = "|".join([f"{o}, India" for o in origins])
        destinations_str = "|".join([f"{d}, India" for d in destinations])

        print(f"\n📏 [DISTANCE] {origins} → {destinations}")

        matrix_url = "https://maps.googleapis.com/maps/api/distancematrix/json"
        resp = requests.get(matrix_url, params={
            'origins': origins_str,
            'destinations': destinations_str,
            'key': GOOGLE_PLACES_API_KEY
        }).json()

        results = []
        for i, origin in enumerate(resp.get('origin_addresses', [])):
            for j, dest in enumerate(resp.get('destination_addresses', [])):
                element = resp['rows'][i]['elements'][j]
                if element.get('status') == 'OK':
                    results.append({
                        'origin': origin,
                        'destination': dest,
                        'distance': element['distance']['text'],
                        'duration': element['duration']['text'],
                        'distance_meters': element['distance']['value'],
                        'duration_seconds': element['duration']['value']
                    })

        return {"status": "success", "results": results}

    except Exception as e:
        print(f"   ❌ Distance matrix error: {e}")
        return {"status": "error", "message": str(e)}


# ============================================================
# GOOGLE TRANSLATE (via Gemini - no extra API needed)
# ============================================================

@app.post("/api/translate")
def translate_text(request: dict):
    """Translate text using Gemini AI + provide travel survival phrases"""
    try:
        text = request.get('text', '')
        source_lang = request.get('source', 'auto')
        target_lang = request.get('target', 'English')
        city = request.get('city', '')

        print(f"\n🌐 [TRANSLATE] '{text[:50]}...' → {target_lang}")

        if text and not city:
            # Simple translation
            prompt = f"""Translate the following text to {target_lang}. Return ONLY the translation, nothing else.

Text: {text}"""
            model = genai.GenerativeModel('gemini-2.5-flash')
            response = model.generate_content(prompt)
            return {
                "status": "success",
                "original": text,
                "translated": response.text.strip(),
                "target_language": target_lang
            }
        elif city:
            # Generate survival phrases for a destination
            prompt = f"""Generate 15 essential travel survival phrases for a tourist visiting {city}, India.
Include the local language translation (if applicable).

Return JSON format:
{{
  "city": "{city}",
  "local_language": "the main local language name",
  "phrases": [
    {{"english": "Hello", "local": "Namaste", "pronunciation": "nah-mah-stay", "category": "greeting"}},
    ...
  ]
}}

Categories: greeting, food, directions, emergency, shopping, transport, hotel
Include phrases for: hello, thank you, how much, where is, help, water, food, bathroom, hotel, train station, airport, too expensive, delicious, please, goodbye"""

            model = genai.GenerativeModel('gemini-2.5-flash')
            response = model.generate_content(prompt)
            text_resp = response.text
            if '```json' in text_resp:
                text_resp = text_resp.split('```json')[1].split('```')[0]
            elif '```' in text_resp:
                text_resp = text_resp.split('```')[1].split('```')[0]
            result = json.loads(text_resp.strip())
            return {"status": "success", **result}
        else:
            return {"status": "error", "message": "Provide 'text' to translate or 'city' for survival phrases"}

    except Exception as e:
        print(f"   ❌ Translation error: {e}")
        return {"status": "error", "message": str(e)}


# ============================================================
# GOOGLE CLOUD VISION API (via Gemini multimodal)
# ============================================================

@app.post("/api/vision/analyze")
def analyze_image(request: dict):
    """Analyze travel image: identify landmarks, extract text from boarding passes, menus"""
    try:
        image_url = request.get('image_url', '')
        analysis_type = request.get('type', 'landmark')  # landmark, boarding_pass, menu, document

        print(f"\n👁️ [VISION] Analyzing image: {analysis_type}")

        prompts = {
            'landmark': f"""Analyze this travel image. Identify:
1. The landmark or location shown
2. The city/country
3. Similar places the user might enjoy
4. Best time to visit
5. Entry fee (if known)

Return JSON: {{"landmark": "name", "city": "city", "country": "country", "description": "2 sentences", "similar_places": ["place1", "place2", "place3"], "best_time": "month range", "entry_fee": "approx cost"}}""",

            'boarding_pass': """Extract all information from this boarding pass/ticket:
Return JSON: {{"airline": "", "flight_number": "", "from": "", "to": "", "date": "", "time": "", "seat": "", "gate": "", "passenger_name": "", "booking_ref": ""}}""",

            'menu': """Translate this restaurant menu to English and categorize items:
Return JSON: {{"restaurant": "name if visible", "items": [{{"name": "dish name", "english_name": "translated", "price": "price", "category": "starter/main/dessert/drink", "vegetarian": true/false}}]}}""",

            'document': """Extract all text and key information from this travel document:
Return JSON: {{"document_type": "visa/passport/hotel_confirmation/etc", "key_info": {{"field1": "value1"}}, "full_text": "extracted text"}}"""
        }

        prompt = prompts.get(analysis_type, prompts['landmark'])

        # Use Gemini multimodal with image URL
        model = genai.GenerativeModel('gemini-2.5-flash')

        # Download image for Gemini
        import urllib.request
        img_data = urllib.request.urlopen(image_url).read()

        response = model.generate_content([
            prompt,
            {"mime_type": "image/jpeg", "data": img_data}
        ])

        text_resp = response.text
        if '```json' in text_resp:
            text_resp = text_resp.split('```json')[1].split('```')[0]
        elif '```' in text_resp:
            text_resp = text_resp.split('```')[1].split('```')[0]

        result = json.loads(text_resp.strip())

        print(f"   ✅ Vision analysis complete")
        return {"status": "success", "type": analysis_type, "result": result}

    except Exception as e:
        print(f"   ❌ Vision error: {e}")
        return {"status": "error", "message": str(e)}


# ============================================================
# SMART TRAVEL INSIGHTS (powered by Gemini)
# ============================================================

@app.post("/api/insights/best-time")
def get_best_time(request: dict):
    """AI-powered: Best time to visit, price predictions, seasonal tips"""
    try:
        city = request.get('city', '')
        print(f"\n📊 [INSIGHTS] Best time to visit {city}")

        prompt = f"""Provide travel insights for {city}, India.

Return JSON:
{{
  "city": "{city}",
  "best_months": ["month1", "month2", "month3"],
  "avoid_months": ["month1", "month2"],
  "peak_season": {{"months": "Nov-Feb", "hotel_price_increase": "40-60%", "crowd_level": "High"}},
  "off_season": {{"months": "Jun-Aug", "hotel_price_decrease": "30-50%", "crowd_level": "Low"}},
  "weather_summary": "2-3 sentence overview",
  "budget_tips": ["tip1", "tip2", "tip3"],
  "local_festivals": [{{"name": "festival", "month": "month", "description": "1 sentence"}}],
  "safety_rating": "Safe/Moderate/Caution",
  "safety_tips": ["tip1", "tip2"],
  "avg_daily_budget": {{"budget": "₹1500-2500", "mid_range": "₹3000-6000", "luxury": "₹8000-15000"}}
}}"""

        model = genai.GenerativeModel('gemini-2.5-flash')
        response = model.generate_content(prompt)
        text_resp = response.text
        if '```json' in text_resp:
            text_resp = text_resp.split('```json')[1].split('```')[0]
        elif '```' in text_resp:
            text_resp = text_resp.split('```')[1].split('```')[0]

        result = json.loads(text_resp.strip())
        print(f"   ✅ Insights generated for {city}")
        return {"status": "success", **result}

    except Exception as e:
        print(f"   ❌ Insights error: {e}")
        return {"status": "error", "message": str(e)}


@app.post("/api/insights/packing-list")
def get_packing_list(request: dict):
    """AI-generated packing list based on destination, duration, activities"""
    try:
        city = request.get('city', '')
        duration = request.get('duration_days', 3)
        activities = request.get('activities', [])
        month = request.get('month', 'current')

        print(f"\n🎒 [PACKING] List for {city}, {duration} days")

        prompt = f"""Generate a smart packing list for a {duration}-day trip to {city}, India in {month}.
Activities planned: {', '.join(activities) if activities else 'sightseeing, food, relaxation'}

Return JSON:
{{
  "essentials": ["item1", "item2"],
  "clothing": ["item1", "item2"],
  "toiletries": ["item1", "item2"],
  "electronics": ["item1", "item2"],
  "documents": ["item1", "item2"],
  "destination_specific": ["item1 (reason)", "item2 (reason)"],
  "pro_tips": ["tip1", "tip2"]
}}"""

        model = genai.GenerativeModel('gemini-2.5-flash')
        response = model.generate_content(prompt)
        text_resp = response.text
        if '```json' in text_resp:
            text_resp = text_resp.split('```json')[1].split('```')[0]
        elif '```' in text_resp:
            text_resp = text_resp.split('```')[1].split('```')[0]

        result = json.loads(text_resp.strip())
        return {"status": "success", "city": city, "duration_days": duration, **result}

    except Exception as e:
        print(f"   ❌ Packing list error: {e}")
        return {"status": "error", "message": str(e)}


@app.post("/api/activities/seasonal")
def get_seasonal_activities(request: dict):
    """AI-generated seasonal activities and attractions for a destination"""
    try:
        city = request.get('city', '')
        travel_date = request.get('travel_date', '')
        days = request.get('days', 3)
        count = request.get('count', 10)

        # Determine season from travel date or current month
        import datetime
        if travel_date:
            try:
                dt = datetime.datetime.fromisoformat(travel_date.replace('Z', '+00:00'))
                month = dt.strftime('%B')
            except:
                month = datetime.datetime.now().strftime('%B')
        else:
            month = datetime.datetime.now().strftime('%B')

        print(f"\n🎯 [ACTIVITIES] Seasonal for {city} in {month}, {days} days, {count} items")

        prompt = f"""You are a local travel expert for {city}, India.

The traveler is visiting in **{month}** for **{days} days**.

Generate exactly {count} real, specific PLACES and LANDMARKS to visit in and around {city} that are:
1. Best suited for {month} season (weather, festivals, seasonal events)
2. Actual real places with real names (NOT generic like "Local Markets" or "Food Trail")
3. Must be physical locations/destinations the traveler can go to (forts, palaces, temples, beaches, lakes, gardens, viewpoints, historical sites, etc.)
4. Include seasonal specialties (e.g., monsoon waterfalls, winter viewpoints, blooming gardens)
5. Mix of: heritage sites, nature spots, religious places, scenic viewpoints, parks, lakes, waterfalls, and unique landmarks

IMPORTANT: Do NOT include generic activities like "food tour", "shopping experience", "cooking class", or "nightlife". Only include real PLACES with specific names and locations.

Return ONLY valid JSON array. Each item must have:
- "id": unique_snake_case_id
- "title": real place/landmark name
- "description": 3 short lines separated by \\n (what it is, why visit, seasonal tip)
- "category": one of [monument, nature, temple, fort, palace, beach, lake, park, viewpoint, heritage, garden]
- "seasonal_rating": 1-5 (how good this place is to visit in {month})
- "best_time": "morning" or "afternoon" or "evening" or "anytime"

Example format:
[
  {{
    "id": "hawa_mahal",
    "title": "Hawa Mahal - Palace of Winds",
    "description": "Iconic pink sandstone palace\\n953 windows with intricate lattice\\nBest visited early morning for photos",
    "category": "monument",
    "seasonal_rating": 4,
    "best_time": "morning"
  }}
]

Return ONLY the JSON array, no markdown."""

        model = genai.GenerativeModel('gemini-2.5-flash')
        response = model.generate_content(prompt)
        text_resp = response.text
        if '```json' in text_resp:
            text_resp = text_resp.split('```json')[1].split('```')[0]
        elif '```' in text_resp:
            text_resp = text_resp.split('```')[1].split('```')[0]

        activities = json.loads(text_resp.strip())

        # Add image URLs and stage info using Google Places photos
        _dest_fallbacks = [
            "https://images.unsplash.com/photo-1506012787146-f92b2d7d6d96?w=800&h=600&fit=crop",
            "https://images.unsplash.com/photo-1507525428034-b723cf961d3e?w=800&h=600&fit=crop",
            "https://images.unsplash.com/photo-1469474968028-56623f02e42e?w=800&h=600&fit=crop",
            "https://images.unsplash.com/photo-1476514525535-07fb3b4ae5f1?w=800&h=600&fit=crop",
            "https://images.unsplash.com/photo-1501785888041-af3ef285b470?w=800&h=600&fit=crop",
        ]
        for idx, act in enumerate(activities):
            act['type'] = 'destination'
            act['stage'] = 'destinations'
            fallback_img = _dest_fallbacks[idx % len(_dest_fallbacks)]
            # Try to get real photo from Google Places
            title = act.get('title', '')
            try:
                search_url = "https://places.googleapis.com/v1/places:searchText"
                headers = {
                    'Content-Type': 'application/json',
                    'X-Goog-Api-Key': GOOGLE_PLACES_API_KEY,
                    'X-Goog-FieldMask': 'places.photos'
                }
                resp = requests.post(search_url, headers=headers,
                    json={"textQuery": f"{title} {city} India", "maxResultCount": 1},
                    timeout=5
                ).json()
                places = resp.get('places', [])
                if places and places[0].get('photos'):
                    photo_name = places[0]['photos'][0].get('name', '')
                    if photo_name:
                        media_url = f"https://places.googleapis.com/v1/{photo_name}/media?maxWidthPx=800&skipHttpRedirect=true&key={GOOGLE_PLACES_API_KEY}"
                        try:
                            media_resp = requests.get(media_url, timeout=5).json()
                            act['image'] = media_resp.get('photoUri', fallback_img)
                        except:
                            act['image'] = fallback_img
                    else:
                        act['image'] = fallback_img
                else:
                    act['image'] = fallback_img
            except:
                act['image'] = fallback_img

        print(f"   ✅ Generated {len(activities)} seasonal activities for {city} in {month}")
        return {
            "status": "success",
            "city": city,
            "month": month,
            "season_info": f"Activities best suited for {month} in {city}",
            "count": len(activities),
            "activities": activities
        }

    except Exception as e:
        print(f"   ❌ Seasonal activities error: {e}")
        import traceback
        traceback.print_exc()
        return {"status": "error", "message": str(e), "activities": []}


# ============================================================
# DESTINATION INTERESTS - AI-generated city-specific interests
# ============================================================
@app.post("/api/destination/interests")
def get_destination_interests(request: dict):
    """Get AI-generated city-specific interests and activities for onboarding."""
    try:
        city = request.get("city", "").strip()
        if not city:
            return {"status": "error", "message": "City is required", "categories": []}

        print(f"\n Generating interests for: {city}")

        prompt = f"""You are a travel expert. For the city "{city}" in India, generate the most relevant interest categories that a traveler can explore there.

Return EXACTLY this JSON (no markdown, no explanation):
{{
  "categories": [
    {{
      "id": "unique_id",
      "title": "Short Category Name",
      "icon": "icon_name",
      "activities": ["Interest Tag 1", "Interest Tag 2", ...]
    }}
  ]
}}

IMPORTANT RULES:
- Generate 6-8 categories relevant to {city}
- Each category should have 4-8 SHORT generic interest tags (1-3 words each) that are relevant to {city}
- Tags should be generic category labels like "Lake", "Museum", "Temple", "Garden", "Fort", "Market", "Street Food", "Cafe", "Pub", "Mall", "Park", "Palace", "Monument"
- Do NOT include specific place names - keep tags generic but relevant to what {city} actually has
- Do NOT use "Beach" or "Water Sports" for inland cities like Bangalore, Delhi, etc.
- icon_name must be one of: terrain, museum, spa, movie, forest, camera_alt, restaurant, shopping_bag, temple_hindu, nightlife, sports, local_activity, park, coffee, architecture

Example for Bangalore:
- "Nature & Parks" (icon: park): ["Lake", "Garden", "Park", "Hill Station", "Wildlife", "Nature Trail"]
- "Heritage" (icon: museum): ["Palace", "Fort", "Museum", "Monument", "Heritage Walk"]
- "Food & Drink" (icon: restaurant): ["Street Food", "Cafe", "Brewery", "Fine Dining", "Local Cuisine"]
- "Temples & Spiritual" (icon: temple_hindu): ["Temple", "Ashram", "Monastery"]

Example for Goa:
- "Beaches" (icon: terrain): ["Beach", "Water Sports", "Sunset Point", "Island"]
- "Nightlife" (icon: nightlife): ["Club", "Pub", "Beach Shack", "Casino", "Live Music"]
"""

        model = genai.GenerativeModel("gemini-2.5-flash")
        response = model.generate_content(prompt)
        text = response.text.strip()

        # Clean JSON
        if text.startswith("```"):
            text = text.split("```")[1]
            if text.startswith("json"):
                text = text[4:]
            text = text.strip()

        import json
        result = json.loads(text)
        categories = result.get("categories", [])

        # Map icon names to material icon identifiers
        icon_map = {
            "terrain": "terrain",
            "museum": "museum",
            "spa": "spa",
            "movie": "movie",
            "forest": "forest",
            "camera_alt": "camera_alt",
            "restaurant": "restaurant",
            "shopping_bag": "shopping_bag",
            "temple_hindu": "temple_hindu",
            "nightlife": "nightlife",
            "sports": "sports",
            "local_activity": "local_activity",
            "park": "park",
            "coffee": "coffee",
            "architecture": "architecture",
        }

        for cat in categories:
            cat["icon"] = icon_map.get(cat.get("icon", ""), "local_activity")

        print(f"   ✅ Generated {len(categories)} categories for {city}")
        return {
            "status": "success",
            "city": city,
            "categories": categories
        }

    except Exception as e:
        print(f"   ❌ Destination interests error: {e}")
        import traceback
        traceback.print_exc()
        fallback_categories = _build_destination_interest_fallback(city)
        if fallback_categories:
            print(f"   ♻️ Using CSV fallback categories for {city}")
            return {
                "status": "success",
                "city": city,
                "categories": fallback_categories,
                "source": "csv_fallback",
            }
        return {"status": "error", "message": str(e), "categories": []}


def _build_destination_interest_fallback(city: str):
    """Create deterministic onboarding interest categories from CSV data."""
    try:
        if not city:
            return []

        city_key = city.split(",")[0].strip().lower()
        if not city_key:
            return []

        filtered = destinations_df[
            destinations_df['city'].fillna('').str.lower() == city_key
        ]

        if filtered.empty:
            filtered = destinations_df[
                destinations_df['city'].fillna('').str.lower().str.contains(city_key)
            ]

        if filtered.empty:
            return []

        row = filtered.iloc[0]

        def _split_values(value):
            if value is None:
                return []
            return [item.strip() for item in str(value).split('|') if item and item.strip()]

        activities = _split_values(row.get('activities'))
        attraction_types = _split_values(row.get('nearby_attractions_type'))
        location_types = _split_values(row.get('location_type'))
        cuisine = _split_values(row.get('cuisine'))
        famous_for = str(row.get('famous_for', '')).strip()

        categories = []

        if activities:
            categories.append({
                "id": "top_activities",
                "title": "Top Activities",
                "icon": "local_activity",
                "activities": activities[:8],
            })

        if attraction_types:
            categories.append({
                "id": "popular_spots",
                "title": "Popular Spots",
                "icon": "camera_alt",
                "activities": attraction_types[:8],
            })

        if location_types:
            categories.append({
                "id": "travel_style",
                "title": "Travel Style",
                "icon": "terrain",
                "activities": location_types[:6],
            })

        if cuisine:
            categories.append({
                "id": "food_dining",
                "title": "Food & Dining",
                "icon": "restaurant",
                "activities": cuisine[:6],
            })

        if famous_for:
            categories.append({
                "id": "must_explore",
                "title": "Must Explore",
                "icon": "star",
                "activities": [famous_for],
            })

        return categories[:8]
    except Exception as fallback_error:
        print(f"   ❌ CSV fallback failed: {fallback_error}")
        return []


# ============================================================
# CITY DISAMBIGUATION - Resolve ambiguous city names
# ============================================================
@app.post("/api/destination/disambiguate")
def disambiguate_city(request: dict):
    """Check if a city name is ambiguous and return options if so."""
    try:
        city = request.get("city", "").strip()
        if not city:
            return {"status": "error", "message": "City is required"}

        print(f"\n🔍 Checking disambiguation for: {city}")

        prompt = f"""You are a geography expert. The user typed "{city}" as a travel destination.

Is this city name ambiguous? Could it refer to multiple well-known places?

Return EXACTLY this JSON (no markdown, no explanation):
{{
  "ambiguous": true or false,
  "options": [
    {{
      "name": "City, State/Region, Country",
      "description": "Brief 5-8 word description"
    }}
  ]
}}

RULES:
- If the city name clearly refers to only ONE well-known place (e.g., "Mumbai", "Paris", "Tokyo", "Bangalore"), set ambiguous=false and return just that one option
- If it could refer to multiple places (e.g., "Hyderabad" → India vs Pakistan, "Springfield" → multiple US states, "Portland" → Oregon vs Maine, "Cambridge" → UK vs USA), set ambiguous=true and list ALL matching places (max 5)
- Focus on places that are actual travel destinations
- Always include the state/region and country in the name
- For Indian cities, include the state (e.g., "Hyderabad, Telangana, India")
"""

        model = genai.GenerativeModel("gemini-2.5-flash")
        response = model.generate_content(prompt)
        text = response.text.strip()

        if text.startswith("```"):
            text = text.split("```")[1]
            if text.startswith("json"):
                text = text[4:]
            text = text.strip()

        import json
        result = json.loads(text)
        ambiguous = result.get("ambiguous", False)
        options = result.get("options", [])

        print(f"   {'⚠️ Ambiguous' if ambiguous else '✅ Clear'}: {len(options)} option(s)")
        return {
            "status": "success",
            "city": city,
            "ambiguous": ambiguous,
            "options": options
        }

    except Exception as e:
        print(f"   ❌ Disambiguation error: {e}")
        return {"status": "error", "message": str(e), "ambiguous": False, "options": []}


@app.get("/api/destination/suggestions")
def get_destination_suggestions(
    query: str,
    limit: int = 8,
    prefer_places: bool = False,
):
    """Destination autocomplete suggestions with AI-first mode.

    Set DESTINATION_SUGGESTIONS_AI_ONLY=TRUE to force AI-only suggestions.
    """
    print(
        f"[DESTINATION] Request: query={query}, limit={limit}, prefer_places={prefer_places}"
    )
    try:
        normalized_query = query.strip()
        if not normalized_query:
            return {
                "status": "success",
                "query": query,
                "suggestions": [],
            }

        safe_limit = max(1, min(limit, 10))
        suggestions = []
        seen_keys = set()
        query_key = normalized_query.lower()

        # Exact cache hit.
        now_ts = datetime.utcnow().timestamp()
        cached = _destination_suggestions_cache.get(query_key)
        if (
            not prefer_places
            and cached
            and now_ts - cached.get("ts", 0) <= _DESTINATION_CACHE_TTL_SECONDS
        ):
            return {
                "status": "success",
                "query": query,
                "suggestions": cached.get("suggestions", [])[:safe_limit],
                "source": "cache",
            }

        # Prefix cache reuse for incremental typing.
        if not prefer_places and len(query_key) >= 2:
            for i in range(len(query_key) - 1, 1, -1):
                prefix = query_key[:i]
                cached_prefix = _destination_suggestions_cache.get(prefix)
                if not cached_prefix:
                    continue
                if now_ts - cached_prefix.get("ts", 0) > _DESTINATION_CACHE_TTL_SECONDS:
                    continue

                prefix_suggestions = cached_prefix.get("suggestions", [])
                filtered = [
                    item for item in prefix_suggestions
                    if query_key in str(item.get("city", "")).lower()
                ][:safe_limit]

                if filtered:
                    _destination_suggestions_cache[query_key] = {
                        "ts": now_ts,
                        "suggestions": filtered,
                    }
                    return {
                        "status": "success",
                        "query": query,
                        "suggestions": filtered,
                        "source": "cache_prefix",
                    }

        def _append_ai_suggestions(max_count: int) -> None:
            """Append AI suggestions with strict timeout to protect autocomplete latency."""
            try:
                ai_prompt = (
                    f"Autocomplete travel destinations for query '{normalized_query}'. "
                    f"Return up to {max_count} items as strict JSON array only. "
                    "Each item: city, country, description, famous_for. "
                    "Prioritize prefix matches, deduplicate, keep text short."
                )

                def _generate_ai_suggestions():
                    model = genai.GenerativeModel("gemini-2.5-flash")
                    return model.generate_content(ai_prompt)

                # Hard timeout so typing does not feel blocked by LLM latency.
                executor = ThreadPoolExecutor(max_workers=1)
                future = executor.submit(_generate_ai_suggestions)
                try:
                    ai_response = future.result(timeout=2.5)
                finally:
                    executor.shutdown(wait=False, cancel_futures=True)

                ai_text = (ai_response.text or "").strip()

                if ai_text.startswith("```"):
                    ai_text = ai_text.split("```", 1)[1]
                    if ai_text.startswith("json"):
                        ai_text = ai_text[4:]
                    ai_text = ai_text.strip()
                    if "```" in ai_text:
                        ai_text = ai_text.split("```", 1)[0].strip()

                parsed_ai = json.loads(ai_text) if ai_text else []
                if isinstance(parsed_ai, dict):
                    parsed_ai = parsed_ai.get("suggestions", [])
                if not isinstance(parsed_ai, list):
                    parsed_ai = []

                for item in parsed_ai:
                    city = str(item.get("city", "")).strip()
                    country = str(item.get("country", "")).strip()
                    description = str(item.get("description", "")).strip()
                    famous_for = str(item.get("famous_for", "")).strip()

                    if not city:
                        continue

                    key = f"{city.lower()}|{country.lower()}"
                    if key in seen_keys:
                        continue
                    seen_keys.add(key)

                    suggestions.append({
                        "city": city,
                        "country": country,
                        "description": description,
                        "famous_for": famous_for,
                    })

                    if len(suggestions) >= safe_limit:
                        break

            except FuturesTimeoutError:
                print("   [INFO] AI autocomplete timed out; using non-AI suggestions")
            except Exception as ai_error:
                print(f"   [WARNING] AI suggestions unavailable: {ai_error}")

        if DESTINATION_SUGGESTIONS_AI_ONLY:
            _append_ai_suggestions(safe_limit)
            return {
                "status": "success",
                "query": query,
                "suggestions": suggestions,
                "source": "ai",
                "ai_only": True,
            }

        # Fallback 1: Google Places Autocomplete (dynamic, non-hardcoded)
        if GOOGLE_PLACES_API_KEY and len(suggestions) < safe_limit:
            try:
                field_mask = (
                    "suggestions.placePrediction.text.text,"
                    "suggestions.placePrediction.structuredFormat.mainText.text,"
                    "suggestions.placePrediction.structuredFormat.secondaryText.text"
                )
                response = requests.post(
                    "https://places.googleapis.com/v1/places:autocomplete",
                    headers=_google_headers(field_mask),
                    json={
                        "input": normalized_query,
                        "includedPrimaryTypes": ["(cities)"],
                        "includeQueryPredictions": False,
                    },
                    timeout=1.2,
                )

                if response.status_code == 200:
                    payload = response.json()
                    for item in payload.get("suggestions", []):
                        prediction = item.get("placePrediction", {})
                        structured = prediction.get("structuredFormat", {})
                        main_text = structured.get("mainText", {}).get("text", "").strip()
                        secondary_text = structured.get("secondaryText", {}).get("text", "").strip()

                        if not main_text:
                            fallback = prediction.get("text", {}).get("text", "").strip()
                            if fallback:
                                # Best effort split "City, Country" style labels.
                                parts = [part.strip() for part in fallback.split(',') if part.strip()]
                                main_text = parts[0] if parts else ""
                                secondary_text = ", ".join(parts[1:]) if len(parts) > 1 else ""

                        if not main_text:
                            continue

                        country = ""
                        if secondary_text:
                            secondary_parts = [p.strip() for p in secondary_text.split(',') if p.strip()]
                            country = secondary_parts[-1] if secondary_parts else secondary_text

                        key = f"{main_text.lower()}|{country.lower()}"
                        if key in seen_keys:
                            continue
                        seen_keys.add(key)

                        suggestions.append({
                            "city": main_text,
                            "country": country,
                            "description": secondary_text,
                            "famous_for": "",
                        })

                        if len(suggestions) >= safe_limit:
                            break
            except Exception as places_error:
                print(f"   [WARNING] Places autocomplete fallback to CSV: {places_error}")

        # Fallback 1b: Google Places Text Search for queries that autocomplete
        # genuinely misses.
        #
        # Deliberately NOT "< safe_limit": autocomplete reliably returns 5
        # results, so a request for 6 always looked one short and always paid
        # for a second network round trip — turning a ~0.5s lookup into ~2-3s
        # on every keystroke, purely to chase one extra row. Only worth it
        # when the first pass came back genuinely sparse.
        if (GOOGLE_PLACES_API_KEY and len(suggestions) < 3
                and len(normalized_query) >= 3):
            try:
                field_mask = (
                    "places.displayName.text,"
                    "places.formattedAddress,"
                    "places.types"
                )
                response = requests.post(
                    "https://places.googleapis.com/v1/places:searchText",
                    headers=_google_headers(field_mask),
                    json={
                        "textQuery": f"{normalized_query} city in India",
                        "maxResultCount": max(5, safe_limit * 2),
                    },
                    timeout=1.5,
                )

                if response.status_code == 200:
                    payload = response.json()
                    for place in payload.get("places", []):
                        display_name = str(place.get("displayName", {}).get("text", "")).strip()
                        formatted_address = str(place.get("formattedAddress", "")).strip()

                        if not display_name:
                            continue

                        country = ""
                        if formatted_address:
                            parts = [p.strip() for p in formatted_address.split(',') if p.strip()]
                            country = parts[-1] if parts else ""

                        key = f"{display_name.lower()}|{country.lower()}"
                        if key in seen_keys:
                            continue
                        seen_keys.add(key)

                        suggestions.append({
                            "city": display_name,
                            "country": country,
                            "description": formatted_address,
                            "famous_for": "",
                        })

                        if len(suggestions) >= safe_limit:
                            break
            except Exception as places_text_error:
                print(f"   [WARNING] Places text search fallback unavailable: {places_text_error}")

        # Fast path: when Places filled enough cards, return immediately.
        if len(suggestions) >= safe_limit:
            _destination_suggestions_cache[query_key] = {
                "ts": datetime.utcnow().timestamp(),
                "suggestions": suggestions[:safe_limit],
            }
            return {
                "status": "success",
                "query": query,
                "suggestions": suggestions,
                "source": "places",
            }

        # Fallback 2: local CSV (India-focused) when AI/Places are unavailable or insufficient.
        if len(suggestions) < safe_limit:
            search = normalized_query.lower()
            filtered = destinations_df[
                destinations_df['city'].fillna('').str.lower().str.contains(search)
            ].copy()

            if not filtered.empty:
                filtered['match_priority'] = filtered['city'].fillna('').str.lower().apply(
                    lambda city: 0 if city.startswith(search) else 1
                )
                filtered = filtered.sort_values(['match_priority', 'city'])

                for _, row in filtered.iterrows():
                    city = str(row.get('city', '')).strip()
                    if not city:
                        continue

                    key = f"{city.lower()}|india"
                    if key in seen_keys:
                        continue
                    seen_keys.add(key)

                    suggestions.append({
                        "city": city,
                        "country": "India",
                        "description": str(row.get('description', '')).strip(),
                        "famous_for": str(row.get('famous_for', '')).strip(),
                    })

                    if len(suggestions) >= safe_limit:
                        break

        # AI fallback: only fill missing slots, and only when query is meaningful.
        if DESTINATION_SUGGESTIONS_USE_AI_FILL and len(suggestions) < safe_limit and len(normalized_query) >= 3:
            _append_ai_suggestions(safe_limit - len(suggestions))

        # Fallback 3: emergency in-memory suggestions to avoid empty UI states.
        if len(suggestions) < safe_limit:
            emergency_cities = [
                ("Bilaspur", "India", "Chhattisgarh, India", "Achanakmar Wildlife Sanctuary"),
                ("Bilaspur (Himachal Pradesh)", "India", "Himachal Pradesh, India", "Naina Devi Temple"),
                ("Bikaner", "India", "Rajasthan, India", "Junagarh Fort"),
                ("Bhubaneswar", "India", "Odisha, India", "Lingaraj Temple"),
                ("Bhopal", "India", "Madhya Pradesh, India", "Upper Lake"),
                ("Raipur", "India", "Chhattisgarh, India", "Mahant Ghasidas Museum"),
                ("Raigarh", "India", "Chhattisgarh, India", "Kelo River views"),
                ("Ranchi", "India", "Jharkhand, India", "Hundru Falls"),
                ("Rajgir", "India", "Bihar, India", "Vishwa Shanti Stupa"),
                ("Rajkot", "India", "Gujarat, India", "Kaba Gandhi No Delo"),
                ("Ranikhet", "India", "Uttarakhand, India", "Pine forests"),
                ("Rameswaram", "India", "Tamil Nadu, India", "Ramanathaswamy Temple"),
                ("Rishikesh", "India", "Uttarakhand, India", "River rafting"),
                ("Rajasthan", "India", "India", "Forts and palaces"),
                ("Ratnagiri", "India", "Maharashtra, India", "Alphonso mangoes"),
            ]

            search = normalized_query.lower()
            ranked = sorted(
                emergency_cities,
                key=lambda item: (0 if item[0].lower().startswith(search) else 1, item[0]),
            )

            for city, country, description, famous_for in ranked:
                if search not in city.lower():
                    continue

                key = f"{city.lower()}|{country.lower()}"
                if key in seen_keys:
                    continue
                seen_keys.add(key)

                suggestions.append({
                    "city": city,
                    "country": country,
                    "description": description,
                    "famous_for": famous_for,
                })

                if len(suggestions) >= safe_limit:
                    break

        _destination_suggestions_cache[query_key] = {
            "ts": datetime.utcnow().timestamp(),
            "suggestions": suggestions[:safe_limit],
        }

        return {
            "status": "success",
            "query": query,
            "suggestions": suggestions,
        }

    except Exception as e:
        print(f"   [ERROR] Destination suggestions error: {e}")
        return {
            "status": "error",
            "query": query,
            "message": str(e),
            "suggestions": [],
        }


# ── Swipe Recommendations ───────────────────────────────────────────────

# In-memory store for bookings and swipe state (per session)
_bookings_store: Dict[str, list] = {}  # session_id -> list of bookings
_swipe_history: Dict[str, list] = {}   # session_id -> list of swipe actions


@app.post("/swipe/recommendations")
async def swipe_recommendations(request: Request):
    """Generate swipeable destination/hotel/activity cards using AI."""
    try:
        body = await request.json()
        card_type = body.get("type", "destination")  # hotel, travel, destination, attraction
        preferences = body.get("preferences", {})
        session_id = body.get("session_id", "default")

        # Use liked history to improve recommendations
        liked = [s for s in _swipe_history.get(session_id, []) if s.get("action") == "like"]
        liked_names = [s.get("card_data", {}).get("name", "") for s in liked[-5:]]

        type_instructions = {
            "destinations": "cities and travel destinations (e.g. Jaipur, Udaipur, Munnar, Rishikesh). Focus on PLACES/CITIES a traveler can visit, NOT activities or things to do.",
            "hotels": "hotels and resorts to stay at (e.g. Taj Mahal Palace, ITC Grand Chola). Focus on ACCOMMODATION options.",
            "travel": "travel/transport options like flights, trains, and buses between cities.",
            "attractions": "tourist attractions, activities, and experiences (e.g. scuba diving, temple visits, trekking, food tours). Focus on THINGS TO DO, not cities.",
        }
        type_desc = type_instructions.get(card_type, f"{card_type} options")

        prompt = f"""Generate 10 unique recommendations: {type_desc}
All recommendations must be real places/options in India.
User preferences: {json.dumps(preferences)}
{"Previously liked: " + ", ".join(liked_names) if liked_names else ""}

Return a JSON array of objects, each with these fields:
- id: unique string id
- name: the name of the {card_type.rstrip('s')} (city name for destinations, hotel name for hotels, activity name for attractions)
- type: "{card_type}"
- city: city/state where it is located
- description: 1-2 sentence description
- rating: number 1-5
- price_range: string like "$", "$$", "$$$"
- image_url: empty string
- tags: array of 3-5 relevant tags
- highlights: array of 2-3 key highlights

Return ONLY the JSON array, no markdown."""

        model = genai.GenerativeModel('gemini-2.5-flash')
        response = model.generate_content(prompt)
        text = response.text.strip()
        if text.startswith("```"):
            text = text.split("```")[1]
            if text.startswith("json"):
                text = text[4:]
            text = text.strip()
        cards = json.loads(text)

        # ── Enrich cards with real images ──────────────────────────────
        for card in cards:
            name = card.get("name", "")
            city = card.get("city", "")

            if card_type == "hotels":
                # Use Google Places API for real hotel photos
                card["image_url"] = get_hotel_image(name, city)
                card["image"] = card["image_url"]

            elif card_type == "destinations":
                # City/destination images from Unsplash keyed by city name
                dest_images = {
                    "jaipur": "https://images.unsplash.com/photo-1477587458883-47145ed94245?w=800&h=600&fit=crop",
                    "udaipur": "https://images.unsplash.com/photo-1602216056096-3b40cc0c9944?w=800&h=600&fit=crop",
                    "goa": "https://images.unsplash.com/photo-1512343879784-a960bf40e7f2?w=800&h=600&fit=crop",
                    "mumbai": "https://images.unsplash.com/photo-1570168007204-dfb528c6958f?w=800&h=600&fit=crop",
                    "delhi": "https://images.unsplash.com/photo-1587474260584-136574528ed5?w=800&h=600&fit=crop",
                    "varanasi": "https://images.unsplash.com/photo-1561361513-2d000a50f0dc?w=800&h=600&fit=crop",
                    "agra": "https://images.unsplash.com/photo-1564507592333-c60657eea523?w=800&h=600&fit=crop",
                    "shimla": "https://images.unsplash.com/photo-1597074866923-dc0589150358?w=800&h=600&fit=crop",
                    "manali": "https://images.unsplash.com/photo-1626621341517-bbf3d9990a23?w=800&h=600&fit=crop",
                    "kerala": "https://images.unsplash.com/photo-1602216056096-3b40cc0c9944?w=800&h=600&fit=crop",
                    "munnar": "https://images.unsplash.com/photo-1516815231560-8f41ec531527?w=800&h=600&fit=crop",
                    "rishikesh": "https://images.unsplash.com/photo-1583396060232-130a3ad8cf0e?w=800&h=600&fit=crop",
                    "darjeeling": "https://images.unsplash.com/photo-1622308644420-b20142dc993c?w=800&h=600&fit=crop",
                    "leh": "https://images.unsplash.com/photo-1626621341517-bbf3d9990a23?w=800&h=600&fit=crop",
                    "ladakh": "https://images.unsplash.com/photo-1626621341517-bbf3d9990a23?w=800&h=600&fit=crop",
                    "hampi": "https://images.unsplash.com/photo-1590050752117-238cb0fb12b1?w=800&h=600&fit=crop",
                    "mysore": "https://images.unsplash.com/photo-1600100397608-e1f6e0d0e6e4?w=800&h=600&fit=crop",
                    "ooty": "https://images.unsplash.com/photo-1573497491208-6b1acb260507?w=800&h=600&fit=crop",
                    "jodhpur": "https://images.unsplash.com/photo-1599661046289-e31897846e41?w=800&h=600&fit=crop",
                    "amritsar": "https://images.unsplash.com/photo-1609947017136-9daa5724150e?w=800&h=600&fit=crop",
                    "kolkata": "https://images.unsplash.com/photo-1558431382-27e303142255?w=800&h=600&fit=crop",
                    "pune": "https://images.unsplash.com/photo-1572782252655-9c8771392601?w=800&h=600&fit=crop",
                    "hyderabad": "https://images.unsplash.com/photo-1572104209055-4e21e6eb9fba?w=800&h=600&fit=crop",
                    "bangalore": "https://images.unsplash.com/photo-1596176530529-78163a4f7af2?w=800&h=600&fit=crop",
                    "chennai": "https://images.unsplash.com/photo-1582510003544-4d00b7f74220?w=800&h=600&fit=crop",
                }
                name_lower = name.lower()
                matched = None
                for key in dest_images:
                    if key in name_lower or key in city.lower():
                        matched = dest_images[key]
                        break
                if not matched:
                    # Generic India destination fallbacks
                    fallbacks = [
                        "https://images.unsplash.com/photo-1524492412937-b28074a5d7da?w=800&h=600&fit=crop",
                        "https://images.unsplash.com/photo-1506461883276-594a12b11cf3?w=800&h=600&fit=crop",
                        "https://images.unsplash.com/photo-1532664189809-02133fee698d?w=800&h=600&fit=crop",
                        "https://images.unsplash.com/photo-1514222134-b57cbb8ce073?w=800&h=600&fit=crop",
                        "https://images.unsplash.com/photo-1585135497273-1a86b09fe70e?w=800&h=600&fit=crop",
                    ]
                    matched = fallbacks[abs(hash(name)) % len(fallbacks)]
                card["image_url"] = matched
                card["image"] = matched

            elif card_type == "attractions":
                # Activity/attraction images based on tags or name keywords
                name_lower = name.lower()
                if any(w in name_lower for w in ["trek", "hike", "mountain", "climb"]):
                    img = "https://images.unsplash.com/photo-1551632811-561732d1e306?w=800&h=600&fit=crop"
                elif any(w in name_lower for w in ["beach", "surf", "snorkel", "scuba", "dive", "water"]):
                    img = "https://images.unsplash.com/photo-1507525428034-b723cf961d3e?w=800&h=600&fit=crop"
                elif any(w in name_lower for w in ["temple", "spiritual", "meditation", "yoga"]):
                    img = "https://images.unsplash.com/photo-1544735716-392fe2489ffa?w=800&h=600&fit=crop"
                elif any(w in name_lower for w in ["food", "cuisine", "eat", "cook", "street food"]):
                    img = "https://images.unsplash.com/photo-1504674900247-0877df9cc836?w=800&h=600&fit=crop"
                elif any(w in name_lower for w in ["safari", "wildlife", "tiger", "bird", "jungle"]):
                    img = "https://images.unsplash.com/photo-1549366021-9f761d450615?w=800&h=600&fit=crop"
                elif any(w in name_lower for w in ["fort", "palace", "heritage", "museum", "monument"]):
                    img = "https://images.unsplash.com/photo-1524492412937-b28074a5d7da?w=800&h=600&fit=crop"
                elif any(w in name_lower for w in ["raft", "kayak", "river", "adventure"]):
                    img = "https://images.unsplash.com/photo-1530866495561-507c83e3f088?w=800&h=600&fit=crop"
                elif any(w in name_lower for w in ["shop", "market", "bazaar"]):
                    img = "https://images.unsplash.com/photo-1555529669-e69e7aa0ba9a?w=800&h=600&fit=crop"
                else:
                    attraction_fallbacks = [
                        "https://images.unsplash.com/photo-1469474968028-56623f02e42e?w=800&h=600&fit=crop",
                        "https://images.unsplash.com/photo-1476514525535-07fb3b4ae5f1?w=800&h=600&fit=crop",
                        "https://images.unsplash.com/photo-1501785888041-af3ef285b470?w=800&h=600&fit=crop",
                        "https://images.unsplash.com/photo-1528543606781-2f6e6857f318?w=800&h=600&fit=crop",
                    ]
                    img = attraction_fallbacks[abs(hash(name)) % len(attraction_fallbacks)]
                card["image_url"] = img
                card["image"] = img

            elif card_type == "travel":
                # Transport images by type
                travel_type = card.get("type", "").lower()
                name_lower = name.lower()
                if any(w in name_lower + travel_type for w in ["flight", "air", "plane"]):
                    img = "https://images.unsplash.com/photo-1556388158-158ea5ccacbd?w=800&h=600&fit=crop"
                elif any(w in name_lower + travel_type for w in ["train", "rail", "express", "rajdhani"]):
                    img = "https://images.unsplash.com/photo-1474487548417-781cb71495f3?w=800&h=600&fit=crop"
                elif any(w in name_lower + travel_type for w in ["bus", "volvo"]):
                    img = "https://images.unsplash.com/photo-1570125909232-eb263c188f7e?w=800&h=600&fit=crop"
                elif any(w in name_lower + travel_type for w in ["taxi", "cab", "car"]):
                    img = "https://images.unsplash.com/photo-1549317661-bd32c8ce0afa?w=800&h=600&fit=crop"
                else:
                    img = "https://images.unsplash.com/photo-1469854523086-cc02fe5d8800?w=800&h=600&fit=crop"
                card["image_url"] = img
                card["image"] = img

        return {"status": "success", "cards": cards, "type": card_type, "count": len(cards)}
    except Exception as e:
        print(f"Swipe recommendations error: {e}")
        return {"status": "success", "cards": [], "type": card_type if 'card_type' in dir() else "destination", "count": 0}


@app.post("/swipe/action")
async def swipe_action(request: Request):
    """Record a swipe action (like/dislike)."""
    try:
        body = await request.json()
        session_id = body.get("session_id", "default")
        action = body.get("action", "dislike")
        card_id = body.get("card_id", "")
        card_type = body.get("type", "destination")
        card_data = body.get("card_data", {})

        if session_id not in _swipe_history:
            _swipe_history[session_id] = []

        _swipe_history[session_id].append({
            "card_id": card_id,
            "action": action,
            "type": card_type,
            "card_data": card_data,
            "timestamp": datetime.now().isoformat()
        })

        return {"status": "success", "action": action, "card_id": card_id}
    except Exception as e:
        return {"status": "error", "message": str(e)}


# ── Bookings ────────────────────────────────────────────────────────────

@app.post("/booking")
async def create_booking(request: Request):
    """Create a new booking."""
    try:
        body = await request.json()
        session_id = body.get("session_id", "default")

        booking = {
            "id": f"BK-{datetime.now().strftime('%Y%m%d%H%M%S')}-{len(_bookings_store.get(session_id, []))+1}",
            "type": body.get("type", "hotel"),
            "user_id": session_id,
            "booking_date": datetime.now().isoformat(),
            "check_in_date": body.get("check_in_date", datetime.now().isoformat()),
            "check_out_date": body.get("check_out_date"),
            "total_price": body.get("total_price", 0),
            "status": "confirmed",
            "details": body.get("details", {}),
            "qr_code": None,
            "pnr": f"PNR{datetime.now().strftime('%H%M%S')}",
            "added_to_calendar": False,
            "calendar_event_id": None,
        }

        if session_id not in _bookings_store:
            _bookings_store[session_id] = []
        _bookings_store[session_id].append(booking)

        return booking
    except Exception as e:
        return {"status": "error", "message": str(e)}


@app.get("/bookings")
async def get_bookings(request: Request):
    """Get all bookings for the session."""
    session_id = request.query_params.get("session_id", "default")
    bookings = _bookings_store.get(session_id, [])
    return {"bookings": bookings}


if __name__ == "__main__":
    import uvicorn
    # Single worker by default. Two reasons, both learned the hard way:
    #   1. Each worker is its own process with its own _photo_cache, so
    #      requests round-robin between a warm cache and a cold one — a
    #      repeated activity-image lookup was still paying the full ~7s
    #      about half the time.
    #   2. On Windows the listening socket doesn't survive being handed to
    #      spawned workers; startup intermittently died with
    #      "OSError: [WinError 10022] An invalid argument was supplied"
    #      and only recovered because the supervisor restarted the child.
    # Set UVICORN_WORKERS=2+ on Linux if you actually need the concurrency.
    worker_count = int(os.getenv("UVICORN_WORKERS", "1"))
    print("Starting Ultra-Simple Hotel Search Server...")
    print("Server will run on http://localhost:8001")
    print("Mode: CSV + Gemini AI + Google Places + Maps + Vision + Translate")
    print(f"Uvicorn workers: {worker_count}")
    if worker_count > 1:
        uvicorn.run("ultra_simple_server:app", host="0.0.0.0", port=8001, workers=worker_count)
    else:
        uvicorn.run(app, host="0.0.0.0", port=8001)
