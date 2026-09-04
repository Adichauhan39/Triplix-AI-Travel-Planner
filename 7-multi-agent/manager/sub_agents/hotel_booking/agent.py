"""
Accommodation Booking Agent - Hotels, Hostels with comprehensive options from CSV
"""

from google.adk.agents import Agent
from typing import Any, Optional
import csv
import os
from datetime import datetime
from ...tools.swipe_recommendations import generate_hotel_recommendations, handle_swipe_action

def load_accommodations_from_csv() -> dict:
    """Load accommodations (hotels, hostels) from CSV file with all details."""
    accommodations_by_city = {}
    csv_path = os.path.join(os.path.dirname(__file__), '..', '..', '..', 'data', 'hotels_india.csv')
    
    try:

        with open(csv_path, 'r', encoding='utf-8') as file:
            reader = csv.DictReader(file)
            for row in reader:
                city = row['city'].lower().strip()
                if city not in accommodations_by_city:
                    accommodations_by_city[city] = []
                
                accommodation_info = {
                    'type': row.get('accommodation_type', 'Hotel'),
                    'name': row.get('name', ''),
                    'price_per_night': row.get('price_per_night', ''),
                    'rating': row.get('rating', ''),
                    'room_types': row.get('room_types', '').split('|') if row.get('room_types') else [],
                    'food_options': row.get('food_options', '').split('|') if row.get('food_options') else [],
                    'ambiance': row.get('ambiance', '').split('|') if row.get('ambiance') else [],
                    'extras': row.get('extras', '').split('|') if row.get('extras') else [],
                    'nearby_attractions': row.get('nearby_attractions', '').split('|') if row.get('nearby_attractions') else [],
                    'accessibility': row.get('accessibility', '').split('|') if row.get('accessibility') else []
                }
                accommodations_by_city[city].append(accommodation_info)
    except Exception as e:
        print(f"Error loading accommodations CSV: {str(e)}")
        return {}
    
    return accommodations_by_city


def search_accommodations(location: str, check_in: str, check_out: str, guests: int, accommodation_type: Optional[str] = None, room_type: Optional[str] = None, food_preference: Optional[str] = None, ambiance: Optional[str] = None, tool_context: Optional[Any] = None) -> dict:
    
    """
    Search accommodations (hotels, hostels) from CSV database with filters.
    
    Args:
        location: City name
        check_in: Check-in date
        check_out: Check-out date
        guests: Number of guests
        accommodation_type: Filter by type - "Hotel" or "Hostel"
        room_type: Preferred room type (Single, Double, Suite, Dormitory, etc.)
        food_preference: Food options (Veg, Non-Veg, Vegan, etc.)
        ambiance: Preferred ambiance (Luxury, Budget, Romantic, etc.)
        tool_context: Context object
        
    Returns:
        Dictionary with available accommodations
    """
    accommodations_db = load_accommodations_from_csv()
    location_key = location.lower().strip()
    
    if location_key in accommodations_db:
        results = accommodations_db[location_key]
        
        # Apply filters
        if accommodation_type:
            results = [acc for acc in results if acc['type'].lower() == accommodation_type.lower()]
        
        if room_type:
            results = [acc for acc in results if any(room_type.lower() in rt.lower() for rt in acc['room_types'])]
        
        if food_preference:
            results = [acc for acc in results if any(food_preference.lower() in food.lower() for food in acc['food_options'])]
        
        if ambiance:
            results = [acc for acc in results if any(ambiance.lower() in amb.lower() for amb in acc['ambiance'])]
        
        return {
            "status": "found",
            "location": location.title(),
            "check_in": check_in,
            "check_out": check_out,
            "guests": guests,
            "accommodations": results,
            "count": len(results),
            "message": f"Found {len(results)} accommodation(s) from CSV matching your criteria"
        }
    else:
        available = ", ".join([c.title() for c in sorted(accommodations_db.keys())])
        return {
            "status": "not_found",
            "location": location.title(),
            "message": f"No accommodations in CSV for {location.title()}",
            "available_cities": available
        }


def book_accommodation(accommodation_name: str, location: str, check_in: str, check_out: str, guests: int, room_type: Optional[str] = None, food_preference: Optional[str] = None, special_requests: Optional[str] = None, tool_context: Optional[Any] = None) -> dict:
   
    """
    Book accommodation from CSV and check for flights/travel.
    
    Args:

        accommodation_name: Name of hotel/hostel
        location: City name
        check_in: Check-in date
        check_out: Check-out date
        guests: Number of guests
        room_type: Type of room to book
        food_preference: Food preference
        special_requests: Any special requests (accessibility, pet, etc.)
        tool_context: Context object to access shared state
        
    Returns:
        Dictionary with booking confirmation and recommendations
    """
    import random
    
    accommodations_db = load_accommodations_from_csv()
    location_key = location.lower().strip()
    
    accommodation_exists = False
    accommodation_details = None
    
    if location_key in accommodations_db:
        for acc in accommodations_db[location_key]:
            if acc['name'].lower() == accommodation_name.lower():
                accommodation_exists = True
                accommodation_details = acc
                break
    
    if not accommodation_exists:
        return {"status": "error", "message": f"Accommodation '{accommodation_name}' not found in CSV for {location.title()}"}
    
    booking_id = f"BK{random.randint(100000, 999999)}"
    
    if not hasattr(tool_context.state, 'get'):
        tool_context.state = {}
    if "bookings" not in tool_context.state:
        tool_context.state["bookings"] = []
    
    accommodation_booking = {
        "booking_type": "hotel",
        "booking_id": booking_id,
        "accommodation_name": accommodation_name,
        "accommodation_type": accommodation_details['type'],
        "location": location,
        "check_in": check_in,
        "check_out": check_out,
        "guests": guests,
        "room_type": room_type,
        "food_preference": food_preference,
        "special_requests": special_requests,
        "price_per_night": accommodation_details['price_per_night'],
        "rating": accommodation_details['rating'],
        "timestamp": datetime.now().isoformat()
    }
    
    tool_context.state["bookings"].append(accommodation_booking)
    
    # Check for travel bookings (flights, trains, taxis) to this location
    has_travel = False
    travel_details = None
    for booking in tool_context.state["bookings"]:
        if booking.get("booking_type") in ["flight", "train", "taxi"]:
            if booking.get("destination", "").lower() == location.lower():
                has_travel = True
                travel_details = booking
                break
    
    visited = tool_context.state.get("destinations_visited", [])
    has_destination = location.lower() in visited
    
    recommendations = []
    if not has_travel:
        recommendations.append({
            "type": "travel",
            "message": f"Don't forget to book travel (flight/train/taxi) to {location.title()}! Would you like to see options?"
        })
    else:
        recommendations.append({
            "type": "travel_confirmed",
            "message": f"Great! You have {travel_details.get('booking_type', 'travel').title()} booked (ID: {travel_details.get('booking_id')})"
        })
    
    if not has_destination:
        recommendations.append({
            "type": "destination",
            "message": f"Want to explore tourist attractions and activities in {location.title()}?"
        })
    
    return {
        "status": "confirmed",
        "booking_id": booking_id,
        "accommodation_name": accommodation_name,
        "accommodation_type": accommodation_details['type'],
        "location": location.title(),
        "check_in": check_in,
        "check_out": check_out,
        "guests": guests,
        "room_type": room_type,
        "food_preference": food_preference,
        "price_per_night": accommodation_details['price_per_night'],
        "rating": accommodation_details['rating'],
        "extras": accommodation_details['extras'],
        "accessibility": accommodation_details['accessibility'],
        "has_travel": has_travel,
        "has_destination_info": has_destination,
        "recommendations": recommendations,
        "message": f"{accommodation_details['type']} booked successfully! Booking ID: {booking_id}"
    }

hotel_booking = Agent(
    model="gemini-3.7-flash",
    name="hotel_booking",
    description="Specialized agent for booking hotels and hostels with comprehensive options from CSV data and swipe-to-discover feature",
    instruction="""You are an accommodation booking assistant for India specializing in Hotels and Hostels.

**DATA SOURCE: CSV ONLY** - All accommodations come from data/hotels_india.csv

Your responsibilities:

1. **🎴 Swipe to Discover (NEW!)**: Offer users a Tinder-like swipe interface to browse accommodations
   - **REQUIRES**: location, check-in date, check-out date, number of guests
   - Use generate_hotel_recommendations ONLY after getting these details
   - Users can swipe right (👍 like it!) or left (👎 not interested)
   - After swiping right, proceed to book the selected accommodation

2. Search for accommodations (hotels, hostels) with detailed filtering options
3. Provide comprehensive information including:
   - **Room Types**: Single, Double, Deluxe, Suite, Dormitory, Family, Executive, View Room
   - **Food Options**: Veg/Non-Veg, Vegan, Gluten-Free, Continental, Indian, Chinese, Mediterranean, Buffet/À la carte
   - **Ambiance**: Luxury, Budget, Modern, Traditional, Romantic, Family-Friendly, Pet-Friendly, Eco-Friendly, Quiet, Party
   - **Extras**: Parking, WiFi, Pool, Gym, Spa, Airport Pickup, Early/Late Check-in, Event Hosting, Beach Access, Heritage Property
   - **Nearby Attractions**: Tourist spots close to the accommodation
   - **Accessibility**: Wheelchair Support, Elevator Access, Pet Facilities

4. Book accommodations and check if user has travel arrangements (flight/train/taxi)
5. Provide recommendations based on user's booking history

**Critical Workflow Rules**:

**Step 1 - Get Required Information:**
✅ ALWAYS ask user first:
   - "Which city are you looking for hotels in?" (location)
   - "When is your check-in date?" (check_in)
   - "When is your check-out date?" (check_out)
   - "How many guests?" (guests)

**Step 2 - Offer Swipe or List:**
After getting location/dates/guests, ask:
"Want to swipe through hotels? It's like Tinder for accommodations! 🏨 Or prefer a filtered list?"

**Step 3 - Generate Recommendations:**
- If swipe → Use generate_hotel_recommendations(location, check_in, check_out, guests)
- If list → Use search_accommodations(location, check_in, check_out, guests)

**Step 4 - Handle Selection:**
- After swipe right → Use handle_swipe_action → book_accommodation
- After list selection → book_accommodation directly

**Step 5 - Post-Booking:**
- Check for travel and provide recommendations

**Important Rules**:
- **NEVER call generate_hotel_recommendations without location/dates/guests**
- If user hasn't provided booking details, ASK for them first
- Always offer the swipe interface AFTER getting booking details
- If using traditional search, use search_accommodations tool to find options from CSV
- Never invent accommodations not in CSV
- If city not in CSV, show available cities
- Validate accommodation exists before booking
- After booking, check for travel bookings and recommend if missing
- Explain all available room types, food options, and extras clearly
- Consider special requests like accessibility needs or pet-friendly options

**Available cities**: Delhi, Mumbai, Bangalore, Jaipur, Goa, Kerala, Udaipur, Agra, Hyderabad, Pune, Chennai, Kolkata, Varanasi, Shimla, Manali

**CSV ONLY** - No web search, no external data! All information comes from the comprehensive CSV database.""",

    tools=[generate_hotel_recommendations, handle_swipe_action, search_accommodations, book_accommodation]

)

