"""
MongoDB Data Layer for Triplix
Replaces CSV-based data access with MongoDB Atlas.
Provides async operations via Motor and sync fallback via PyMongo.
"""
import os
from typing import Any, Dict, List, Optional
from datetime import datetime

from motor.motor_asyncio import AsyncIOMotorClient
from pymongo import MongoClient
from pymongo.errors import ConnectionFailure

# ── Connection ──────────────────────────────────────────────────────────

MONGODB_URI = os.getenv("MONGODB_URI", "mongodb://localhost:27017")
MONGODB_DB = os.getenv("MONGODB_DB", "triplix")

_async_client: Optional[AsyncIOMotorClient] = None
_sync_client: Optional[MongoClient] = None


def get_async_client() -> AsyncIOMotorClient:
    """Get or create the async Motor client (for FastAPI endpoints)."""
    global _async_client
    if _async_client is None:
        _async_client = AsyncIOMotorClient(MONGODB_URI, serverSelectionTimeoutMS=5000)
    return _async_client


def get_sync_client() -> MongoClient:
    """Get or create the sync PyMongo client (for seed scripts / tools)."""
    global _sync_client
    if _sync_client is None:
        _sync_client = MongoClient(MONGODB_URI, serverSelectionTimeoutMS=5000)
    return _sync_client


def get_db(async_mode: bool = True):
    """Return the triplix database handle."""
    if async_mode:
        return get_async_client()[MONGODB_DB]
    return get_sync_client()[MONGODB_DB]


async def check_connection() -> bool:
    """Verify MongoDB connectivity."""
    try:
        client = get_async_client()
        await client.admin.command("ping")
        return True
    except ConnectionFailure:
        return False


async def close_connections():
    """Close all MongoDB clients."""
    global _async_client, _sync_client
    if _async_client:
        _async_client.close()
        _async_client = None
    if _sync_client:
        _sync_client.close()
        _sync_client = None


# ── Collection Names ────────────────────────────────────────────────────

COLLECTIONS = {
    "hotels": "hotels",
    "flights": "flights",
    "trains": "trains",
    "buses": "buses",
    "cars": "car_rentals",
    "taxis": "taxis",
    "bikes": "bikes",
    "destinations": "destinations",
    "bookings": "bookings",
    "itineraries": "itineraries",
    "user_preferences": "user_preferences",
}


# ── Hotel Operations ────────────────────────────────────────────────────

async def search_hotels(
    city: str,
    max_price: Optional[float] = None,
    min_rating: Optional[float] = None,
    limit: int = 10,
) -> List[Dict[str, Any]]:
    """Search hotels by city with optional filters."""
    db = get_db(async_mode=True)
    query: Dict[str, Any] = {
        "city": {"$regex": city, "$options": "i"}
    }
    if max_price is not None:
        query["price_per_night"] = {"$lte": max_price}
    if min_rating is not None:
        query["rating"] = {"$gte": min_rating}

    cursor = db[COLLECTIONS["hotels"]].find(query, {"_id": 0}).limit(limit)
    return await cursor.to_list(length=limit)


async def get_hotel_by_name(name: str) -> Optional[Dict[str, Any]]:
    """Find a specific hotel by name."""
    db = get_db(async_mode=True)
    return await db[COLLECTIONS["hotels"]].find_one(
        {"name": {"$regex": name, "$options": "i"}}, {"_id": 0}
    )


# ── Transport Operations ───────────────────────────────────────────────

async def search_flights(
    from_city: str,
    to_city: str,
    max_price: Optional[float] = None,
    limit: int = 10,
) -> List[Dict[str, Any]]:
    """Search flights between cities."""
    db = get_db(async_mode=True)
    query: Dict[str, Any] = {
        "from_city": {"$regex": from_city, "$options": "i"},
        "to_city": {"$regex": to_city, "$options": "i"},
    }
    if max_price is not None:
        query["price"] = {"$lte": max_price}
    cursor = db[COLLECTIONS["flights"]].find(query, {"_id": 0}).limit(limit)
    return await cursor.to_list(length=limit)


async def search_trains(
    from_city: str,
    to_city: str,
    max_price: Optional[float] = None,
    limit: int = 10,
) -> List[Dict[str, Any]]:
    """Search trains between cities."""
    db = get_db(async_mode=True)
    query: Dict[str, Any] = {
        "from_city": {"$regex": from_city, "$options": "i"},
        "to_city": {"$regex": to_city, "$options": "i"},
    }
    if max_price is not None:
        query["price"] = {"$lte": max_price}
    cursor = db[COLLECTIONS["trains"]].find(query, {"_id": 0}).limit(limit)
    return await cursor.to_list(length=limit)


async def search_buses(
    from_city: str,
    to_city: str,
    limit: int = 10,
) -> List[Dict[str, Any]]:
    """Search buses between cities."""
    db = get_db(async_mode=True)
    query = {
        "from_city": {"$regex": from_city, "$options": "i"},
        "to_city": {"$regex": to_city, "$options": "i"},
    }
    cursor = db[COLLECTIONS["buses"]].find(query, {"_id": 0}).limit(limit)
    return await cursor.to_list(length=limit)


# ── Destination Operations ──────────────────────────────────────────────

async def search_destinations(
    city: Optional[str] = None,
    category: Optional[str] = None,
    limit: int = 20,
) -> List[Dict[str, Any]]:
    """Search destinations/attractions."""
    db = get_db(async_mode=True)
    query: Dict[str, Any] = {}
    if city:
        query["city"] = {"$regex": city, "$options": "i"}
    if category:
        query["category"] = {"$regex": category, "$options": "i"}
    cursor = db[COLLECTIONS["destinations"]].find(query, {"_id": 0}).limit(limit)
    return await cursor.to_list(length=limit)


# ── Booking / Itinerary Persistence ────────────────────────────────────

async def save_itinerary(user_id: str, itinerary_data: Dict[str, Any]) -> str:
    """Save a generated itinerary to MongoDB."""
    db = get_db(async_mode=True)
    doc = {
        "user_id": user_id,
        "created_at": datetime.utcnow(),
        "updated_at": datetime.utcnow(),
        **itinerary_data,
    }
    result = await db[COLLECTIONS["itineraries"]].insert_one(doc)
    return str(result.inserted_id)


async def get_itinerary(user_id: str) -> Optional[Dict[str, Any]]:
    """Get the latest itinerary for a user."""
    db = get_db(async_mode=True)
    doc = await db[COLLECTIONS["itineraries"]].find_one(
        {"user_id": user_id},
        {"_id": 0},
        sort=[("created_at", -1)],
    )
    return doc


async def save_booking(booking_data: Dict[str, Any]) -> str:
    """Save a booking record."""
    db = get_db(async_mode=True)
    booking_data["created_at"] = datetime.utcnow()
    result = await db[COLLECTIONS["bookings"]].insert_one(booking_data)
    return str(result.inserted_id)


async def get_user_bookings(user_id: str) -> List[Dict[str, Any]]:
    """Get all bookings for a user."""
    db = get_db(async_mode=True)
    cursor = db[COLLECTIONS["bookings"]].find(
        {"user_id": user_id}, {"_id": 0}
    ).sort("created_at", -1)
    return await cursor.to_list(length=50)


async def save_user_preferences(user_id: str, preferences: Dict[str, Any]):
    """Upsert user travel preferences."""
    db = get_db(async_mode=True)
    await db[COLLECTIONS["user_preferences"]].update_one(
        {"user_id": user_id},
        {"$set": {**preferences, "updated_at": datetime.utcnow()}},
        upsert=True,
    )


async def get_user_preferences(user_id: str) -> Optional[Dict[str, Any]]:
    """Get stored user preferences."""
    db = get_db(async_mode=True)
    return await db[COLLECTIONS["user_preferences"]].find_one(
        {"user_id": user_id}, {"_id": 0}
    )


# ── Generic Query (for MCP / Agent tools) ──────────────────────────────

async def query_collection(
    collection: str,
    filter_dict: Dict[str, Any],
    projection: Optional[Dict[str, Any]] = None,
    limit: int = 20,
    sort: Optional[List] = None,
) -> List[Dict[str, Any]]:
    """Generic collection query — used by MCP server tools."""
    db = get_db(async_mode=True)
    proj = projection or {"_id": 0}
    cursor = db[collection].find(filter_dict, proj).limit(limit)
    if sort:
        cursor = cursor.sort(sort)
    return await cursor.to_list(length=limit)


async def aggregate_collection(
    collection: str,
    pipeline: List[Dict[str, Any]],
) -> List[Dict[str, Any]]:
    """Run a MongoDB aggregation pipeline — used by MCP server tools."""
    db = get_db(async_mode=True)
    cursor = db[collection].aggregate(pipeline)
    return await cursor.to_list(length=100)
