"""
Seed MongoDB Atlas with travel data from CSV files.

Usage:
    cd 7-multi-agent
    python seed_mongodb.py

Requires MONGODB_URI in .env (or defaults to localhost:27017).
"""
import os
import sys
import csv
import glob
from dotenv import load_dotenv
from pymongo import MongoClient
from pymongo.errors import ConnectionFailure

load_dotenv()

MONGODB_URI = os.getenv("MONGODB_URI", "mongodb://localhost:27017")
MONGODB_DB = os.getenv("MONGODB_DB", "triplix")

# Map CSV filenames → MongoDB collection names
CSV_TO_COLLECTION = {
    "hotels_india.csv": "hotels",
    "flights_india.csv": "flights",
    "trains_india.csv": "trains",
    "buses_india.csv": "buses",
    "car_rentals_india.csv": "car_rentals",
    "taxis_india.csv": "taxis",
    "bikes_india.csv": "bikes",
    "destinations_india.csv": "destinations",
    "travel_bookings_india.csv": "bookings",
}

# Fields that should be converted to float
NUMERIC_FIELDS = {
    "price", "price_per_night", "rating", "latitude", "longitude",
    "base_fare", "per_km_rate", "total_fare", "distance_km",
    "rental_price_per_day", "security_deposit",
}

# Fields that should be converted to int
INT_FIELDS = {
    "capacity", "seats_available", "total_seats", "rooms_available",
}

# Fields that should be parsed as lists (comma-separated in CSV)
LIST_FIELDS = {
    "amenities", "highlights", "facilities", "features",
    "cuisine_types", "languages_spoken",
}


def parse_value(key: str, value: str):
    """Convert a CSV string value to the appropriate Python type."""
    if not value or value.strip() == "":
        return None
    value = value.strip()

    if key in NUMERIC_FIELDS:
        try:
            cleaned = value.replace(",", "").replace("₹", "").replace("Rs.", "").strip()
            return float(cleaned)
        except ValueError:
            return value

    if key in INT_FIELDS:
        try:
            return int(float(value.replace(",", "")))
        except ValueError:
            return value

    if key in LIST_FIELDS:
        return [item.strip() for item in value.split(",") if item.strip()]

    # Boolean-ish
    if value.lower() in ("true", "yes"):
        return True
    if value.lower() in ("false", "no"):
        return False

    return value


def load_csv(filepath: str) -> list[dict]:
    """Read a CSV file and return list of dicts with typed values."""
    docs = []
    try:
        with open(filepath, "r", encoding="utf-8-sig") as f:
            reader = csv.DictReader(f)
            for row in reader:
                doc = {}
                for key, value in row.items():
                    if key is None:
                        continue
                    clean_key = key.strip().lower().replace(" ", "_")
                    doc[clean_key] = parse_value(clean_key, value)
                docs.append(doc)
    except Exception as e:
        print(f"  ⚠️  Error reading {filepath}: {e}")
    return docs


def create_indexes(db):
    """Create useful indexes for query performance."""
    print("\n📇 Creating indexes...")

    # Hotels
    db.hotels.create_index([("city", 1)])
    db.hotels.create_index([("city", 1), ("price_per_night", 1)])
    db.hotels.create_index([("name", "text")])

    # Flights
    db.flights.create_index([("from_city", 1), ("to_city", 1)])
    db.flights.create_index([("from_city", 1), ("to_city", 1), ("price", 1)])

    # Trains
    db.trains.create_index([("from_city", 1), ("to_city", 1)])

    # Buses
    db.buses.create_index([("from_city", 1), ("to_city", 1)])

    # Destinations
    db.destinations.create_index([("city", 1)])
    db.destinations.create_index([("name", "text", "description", "text")])

    # Bookings & Itineraries
    db.bookings.create_index([("user_id", 1), ("created_at", -1)])
    db.itineraries.create_index([("user_id", 1), ("created_at", -1)])

    # User preferences
    db.user_preferences.create_index([("user_id", 1)], unique=True)

    print("  ✅ Indexes created")


def seed():
    """Main seed function."""
    print(f"🌱 Seeding MongoDB: {MONGODB_URI}")
    print(f"   Database: {MONGODB_DB}\n")

    try:
        client = MongoClient(MONGODB_URI, serverSelectionTimeoutMS=5000)
        client.admin.command("ping")
        print("  ✅ Connected to MongoDB\n")
    except ConnectionFailure as e:
        print(f"  ❌ Cannot connect to MongoDB: {e}")
        print("  Make sure MONGODB_URI is set in your .env file.")
        print("  Example: MONGODB_URI=mongodb+srv://user:pass@cluster0.xxxxx.mongodb.net/triplix")
        sys.exit(1)

    db = client[MONGODB_DB]
    data_dir = os.path.join(os.path.dirname(__file__), "data")

    total_docs = 0
    for csv_file, collection_name in CSV_TO_COLLECTION.items():
        filepath = os.path.join(data_dir, csv_file)
        if not os.path.exists(filepath):
            print(f"  ⏭️  Skipping {csv_file} (not found)")
            continue

        docs = load_csv(filepath)
        if not docs:
            print(f"  ⏭️  Skipping {csv_file} (empty or parse error)")
            continue

        # Drop existing and re-insert
        db[collection_name].drop()
        db[collection_name].insert_many(docs)
        total_docs += len(docs)
        print(f"  📦 {collection_name}: {len(docs)} documents loaded from {csv_file}")

    create_indexes(db)

    print(f"\n🎉 Seed complete! {total_docs} total documents across {len(CSV_TO_COLLECTION)} collections.")
    print(f"   Database: {MONGODB_DB}")

    # Print collection stats
    print("\n📊 Collection stats:")
    for coll_name in sorted(db.list_collection_names()):
        count = db[coll_name].count_documents({})
        print(f"   {coll_name}: {count} docs")

    client.close()


if __name__ == "__main__":
    seed()
