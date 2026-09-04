"""
Itinerary Planning Agent
Creates organized day-by-day itineraries from swiped attractions and bookings with SPECIFIC hotels, flights, restaurant recommendations, and WEATHER forecasts
"""
from google.adk.agents import Agent
from typing import Any, Optional
from datetime import datetime, timedelta
import json
import random
import requests
from os import getenv


# OpenWeatherMap API Key (free tier - 1000 calls/day)
OPENWEATHER_API_KEY = getenv("OPENWEATHER_API_KEY", "")  # Get from environment or use fallback


def get_weather_forecast(city: str, date: str) -> dict:
    """
    Get weather forecast for a specific city and date using OpenWeatherMap API
    
    Args:
        city: City name (e.g., "Goa", "Mumbai")
        date: Date in YYYY-MM-DD format
    
    Returns:
        dict with weather info: temp, condition, description, icon
    """
    try:
        if not OPENWEATHER_API_KEY:
            # Return default weather if no API key
            return {
                "temp": "25-30°C",
                "condition": "Partly Cloudy",
                "description": "Pleasant weather expected",
                "icon": "🌤️"
            }
        
        # OpenWeatherMap free 5-day forecast API
        url = f"http://api.openweathermap.org/data/2.5/forecast"
        params = {
            "q": city + ",IN",  # Add country code for better accuracy
            "appid": OPENWEATHER_API_KEY,
            "units": "metric",  # Celsius
            "cnt": 40  # 5 days * 8 (3-hour intervals)
        }
        
        response = requests.get(url, params=params, timeout=5)
        
        if response.status_code == 200:
            data = response.json()
            
            # Parse target date
            target_date = datetime.strptime(date, "%Y-%m-%d").date()
            
            # Find forecast closest to target date (at noon for better accuracy)
            closest_forecast = None
            min_time_diff = timedelta(days=999)
            
            for forecast in data.get("list", []):
                forecast_dt = datetime.fromtimestamp(forecast["dt"])
                forecast_date = forecast_dt.date()
                time_diff = abs((forecast_date - target_date).days)
                
                # Prefer noon time (12:00)
                if time_diff < min_time_diff.days or (time_diff == min_time_diff.days and forecast_dt.hour == 12):
                    min_time_diff = timedelta(days=time_diff)
                    closest_forecast = forecast
            
            if closest_forecast:
                temp = round(closest_forecast["main"]["temp"])
                temp_min = round(closest_forecast["main"]["temp_min"])
                temp_max = round(closest_forecast["main"]["temp_max"])
                condition = closest_forecast["weather"][0]["main"]
                description = closest_forecast["weather"][0]["description"].capitalize()
                weather_id = closest_forecast["weather"][0]["id"]
                
                # Map weather condition to emoji
                icon = "☀️"  # Default sunny
                if weather_id < 300:  # Thunderstorm
                    icon = "⛈️"
                elif weather_id < 400:  # Drizzle
                    icon = "🌦️"
                elif weather_id < 600:  # Rain
                    icon = "🌧️"
                elif weather_id < 700:  # Snow
                    icon = "🌨️"
                elif weather_id < 800:  # Atmosphere (fog, mist, etc.)
                    icon = "🌫️"
                elif weather_id == 800:  # Clear
                    icon = "☀️"
                elif weather_id == 801:  # Few clouds
                    icon = "🌤️"
                elif weather_id < 805:  # Clouds
                    icon = "☁️"
                
                return {
                    "temp": f"{temp_min}-{temp_max}°C",
                    "condition": condition,
                    "description": description,
                    "icon": icon,
                    "humidity": closest_forecast["main"]["humidity"],
                    "wind": round(closest_forecast["wind"]["speed"] * 3.6, 1)  # m/s to km/h
                }
        
        # Fallback if API call fails
        return {
            "temp": "25-30°C",
            "condition": "Check weather app",
            "description": "Weather forecast unavailable",
            "icon": "🌤️"
        }
        
    except Exception as e:
        print(f"Weather API error: {str(e)}")
        # Return friendly fallback
        return {
            "temp": "25-30°C",
            "condition": "Pleasant",
            "description": "Check weather app for latest updates",
            "icon": "🌤️"
        }


# Sample restaurant database for India (can be expanded or replaced with API)
RESTAURANTS_DATABASE = {
    "Mumbai": [
        {"name": "Trishna", "cuisine": "Seafood", "price": "₹₹₹", "rating": 4.5, "location": "Kala Ghoda"},
        {"name": "Britannia & Co", "cuisine": "Parsi", "price": "₹₹", "rating": 4.3, "location": "Ballard Estate"},
        {"name": "Bademiya", "cuisine": "Mughlai", "price": "₹₹", "rating": 4.4, "location": "Colaba"},
        {"name": "Leopold Cafe", "cuisine": "Continental", "price": "₹₹", "rating": 4.2, "location": "Colaba"},
        {"name": "Mahesh Lunch Home", "cuisine": "Seafood", "price": "₹₹₹", "rating": 4.6, "location": "Juhu"},
    ],
    "Delhi": [
        {"name": "Karim's", "cuisine": "Mughlai", "price": "₹₹", "rating": 4.5, "location": "Jama Masjid"},
        {"name": "Indian Accent", "cuisine": "Modern Indian", "price": "₹₹₹₹", "rating": 4.7, "location": "Lodhi Road"},
        {"name": "Paranthe Wali Gali", "cuisine": "North Indian", "price": "₹", "rating": 4.3, "location": "Chandni Chowk"},
        {"name": "Bukhara", "cuisine": "North Indian", "price": "₹₹₹₹", "rating": 4.8, "location": "Chanakyapuri"},
        {"name": "SodaBottleOpenerWala", "cuisine": "Parsi", "price": "₹₹", "rating": 4.4, "location": "Khan Market"},
    ],
    "Goa": [
        {"name": "Fisherman's Wharf", "cuisine": "Goan Seafood", "price": "₹₹₹", "rating": 4.5, "location": "Panjim"},
        {"name": "Vinayak Family Restaurant", "cuisine": "Goan", "price": "₹₹", "rating": 4.3, "location": "Assagao"},
        {"name": "Pousada by the Beach", "cuisine": "Continental", "price": "₹₹₹", "rating": 4.6, "location": "Calangute"},
        {"name": "Sublime", "cuisine": "Fusion", "price": "₹₹₹₹", "rating": 4.7, "location": "Morjim"},
        {"name": "Black Sheep Bistro", "cuisine": "European", "price": "₹₹₹", "rating": 4.5, "location": "Panjim"},
    ],
    "Bangalore": [
        {"name": "MTR", "cuisine": "South Indian", "price": "₹₹", "rating": 4.5, "location": "Lalbagh"},
        {"name": "Koshy's", "cuisine": "Continental", "price": "₹₹", "rating": 4.3, "location": "MG Road"},
        {"name": "Karavalli", "cuisine": "Coastal Indian", "price": "₹₹₹₹", "rating": 4.7, "location": "UB City"},
        {"name": "Vidyarthi Bhavan", "cuisine": "South Indian", "price": "₹", "rating": 4.4, "location": "Basavanagudi"},
        {"name": "The Only Place", "cuisine": "Steakhouse", "price": "₹₹₹", "rating": 4.5, "location": "Museum Road"},
    ],
    "Jaipur": [
        {"name": "Laxmi Mishthan Bhandar (LMB)", "cuisine": "Rajasthani", "price": "₹₹", "rating": 4.4, "location": "Johari Bazaar"},
        {"name": "Chokhi Dhani", "cuisine": "Rajasthani", "price": "₹₹₹", "rating": 4.6, "location": "Tonk Road"},
        {"name": "Suvarna Mahal", "cuisine": "Rajasthani Royal", "price": "₹₹₹₹", "rating": 4.8, "location": "Rambagh Palace"},
        {"name": "Rawat Mishthan Bhandar", "cuisine": "Sweets & Snacks", "price": "₹", "rating": 4.5, "location": "Sindhi Camp"},
        {"name": "Handi Restaurant", "cuisine": "Rajasthani", "price": "₹₹", "rating": 4.3, "location": "MI Road"},
    ],
    # Default restaurants for any city
    "default": [
        {"name": "Local Cafe", "cuisine": "Multi-Cuisine", "price": "₹₹", "rating": 4.0, "location": "City Center"},
        {"name": "Street Food Hub", "cuisine": "Street Food", "price": "₹", "rating": 4.2, "location": "Main Market"},
        {"name": "The Grand Restaurant", "cuisine": "Indian", "price": "₹₹₹", "rating": 4.4, "location": "Downtown"},
        {"name": "Cafe Delight", "cuisine": "Continental", "price": "₹₹", "rating": 4.1, "location": "Shopping District"},
        {"name": "Spice Route", "cuisine": "Indian", "price": "₹₹", "rating": 4.3, "location": "Near Hotel Area"},
    ]
}


def get_restaurant_recommendations(city: str, num_restaurants: int = 3) -> list[dict]:
    """Get restaurant recommendations for a specific city"""
    # Find matching city (case-insensitive partial match)
    city_lower = city.lower()
    restaurants = RESTAURANTS_DATABASE.get("default", [])
    
    for db_city in RESTAURANTS_DATABASE:
        if db_city.lower() in city_lower or city_lower in db_city.lower():
            restaurants = RESTAURANTS_DATABASE[db_city]
            break
    
    # Return random selection
    return random.sample(restaurants, min(num_restaurants, len(restaurants)))



def create_itinerary(
    attractions: list[dict],
    start_date: str,
    num_days: int,
    preferences: str = "",
    selected_hotels: list[dict] = None,
    selected_transport: list[dict] = None,
    city: str = ""
) -> dict:
    """
    Creates a day-by-day itinerary from selected attractions WITH SPECIFIC hotels, flights, and restaurant recommendations.
    
    Args:
        attractions: List of attraction dicts with keys: name, description, location, category
        start_date: Start date in YYYY-MM-DD format
        num_days: Number of days for the trip
        preferences: User preferences
        selected_hotels: List of user's confirmed hotel bookings
        selected_transport: List of user's confirmed transport bookings
        city: Destination city name for restaurant recommendations
    
    Returns:
        Dictionary containing organized itinerary with daily schedule INCLUDING specific hotels, flights, and restaurants
    """
    if not attractions:
        return {
            "status": "error",
            "message": "No attractions provided. Please swipe right on some places first!"
        }
    
    # Parse start date
    try:
        start = datetime.strptime(start_date, "%Y-%m-%d")
    except ValueError:
        return {
            "status": "error",
            "message": f"Invalid date format: {start_date}. Use YYYY-MM-DD"
        }
    
    # Get actual hotel and transport details
    confirmed_hotel = selected_hotels[0] if selected_hotels and len(selected_hotels) > 0 else None
    confirmed_transport = selected_transport[0] if selected_transport and len(selected_transport) > 0 else None
    
    # Get restaurant recommendations for the destination city
    restaurants = get_restaurant_recommendations(city, num_restaurants=num_days * 2)  # 2 meals per day
    
    # Organize attractions by day
    attractions_per_day = max(1, len(attractions) // num_days)
    
    itinerary = {
        "trip_title": f"{num_days}-Day {city} Trip",
        "start_date": start_date,
        "total_days": num_days,
        "total_attractions": len(attractions),
        "hotel": confirmed_hotel.get("title", "Hotel TBD") if confirmed_hotel else "Hotel TBD",
        "transport": confirmed_transport.get("title", "Transport TBD") if confirmed_transport else "Transport TBD",
        "preferences": preferences,
        "daily_schedule": []
    }
    
    attraction_index = 0
    restaurant_index = 0
    
    for day in range(num_days):
        day_date = start + timedelta(days=day)
        day_activities = []
        
        # DAY 1: ARRIVAL DAY - Include flight and hotel check-in
        if day == 0:
            # Morning: Flight arrival
            if confirmed_transport:
                day_activities.append({
                    "time": "08:00 AM",
                    "activity_type": "transport",
                    "icon": "✈️",
                    "name": f"Arrive via {confirmed_transport.get('title', 'Flight')}",
                    "description": confirmed_transport.get('description', 'Arrival flight'),
                    "details": f"Flight Number: {confirmed_transport.get('flight_number', 'TBD')}, Terminal: {confirmed_transport.get('from', 'Check details')}" if 'flight_number' in confirmed_transport else f"Departs: {confirmed_transport.get('from', 'TBD')}, Arrives: {confirmed_transport.get('to', city)}",
                    "location": f"{confirmed_transport.get('to', city)} Airport",
                    "estimated_duration": "Transfer to hotel: 1 hour"
                })
            
            # Late Morning: Hotel check-in
            if confirmed_hotel:
                day_activities.append({
                    "time": "11:00 AM",
                    "activity_type": "hotel",
                    "icon": "🏨",
                    "name": f"Check-in at {confirmed_hotel.get('title', 'Hotel')}",
                    "description": confirmed_hotel.get('description', 'Hotel accommodation'),
                    "details": f"Address: {confirmed_hotel.get('location', 'City Center')}, Rating: {confirmed_hotel.get('rating', 'N/A')}⭐, Price: {confirmed_hotel.get('price', 'TBD')}",
                    "location": confirmed_hotel.get('location', 'City Center'),
                    "estimated_duration": "Check-in: 30 mins, Freshen up: 1 hour"
                })
        
        # Lunch
        if restaurant_index < len(restaurants):
            lunch_restaurant = restaurants[restaurant_index]
            restaurant_index += 1
            day_activities.append({
                "time": "01:00 PM",
                "activity_type": "meal",
                "icon": "🍽️",
                "name": f"Lunch at {lunch_restaurant['name']}",
                "description": f"{lunch_restaurant['cuisine']} cuisine",
                "details": f"Rating: {lunch_restaurant['rating']}⭐, Price Range: {lunch_restaurant['price']}, Location: {lunch_restaurant['location']}",
                "location": lunch_restaurant['location'],
                "estimated_duration": "1-1.5 hours"
            })
        
        # Afternoon/Evening: Attractions (2-3 per day)
        time_slots = ["03:00 PM", "05:30 PM"]
        for time_slot in time_slots:
            if attraction_index < len(attractions):
                attraction = attractions[attraction_index]
                day_activities.append({
                    "time": time_slot,
                    "activity_type": "attraction",
                    "icon": "📍",
                    "name": attraction.get("name", "Unknown"),
                    "description": attraction.get("description", ""),
                    "details": f"Category: {attraction.get('category', 'General')}",
                    "location": attraction.get("location", ""),
                    "estimated_duration": "1.5-2 hours"
                })
                attraction_index += 1
        
        # Dinner
        if restaurant_index < len(restaurants):
            dinner_restaurant = restaurants[restaurant_index]
            restaurant_index += 1
        else:
            # Reuse restaurants if we run out
            dinner_restaurant = restaurants[restaurant_index % len(restaurants)] if restaurants else {
                "name": "Hotel Restaurant", "cuisine": "Multi-Cuisine", "price": "₹₹", 
                "rating": 4.0, "location": "Hotel"
            }
            restaurant_index += 1
        
        day_activities.append({
            "time": "08:00 PM",
            "activity_type": "meal",
            "icon": "🍴",
            "name": f"Dinner at {dinner_restaurant['name']}",
            "description": f"{dinner_restaurant['cuisine']} cuisine",
            "details": f"Rating: {dinner_restaurant['rating']}⭐, Price Range: {dinner_restaurant['price']}, Location: {dinner_restaurant['location']}",
            "location": dinner_restaurant['location'],
            "estimated_duration": "1.5-2 hours"
        })
        
        # Night: Return to hotel
        if confirmed_hotel:
            day_activities.append({
                "time": "10:00 PM",
                "activity_type": "hotel",
                "icon": "🛏️",
                "name": f"Return to {confirmed_hotel.get('title', 'Hotel')}",
                "description": "Rest and overnight stay",
                "details": f"Address: {confirmed_hotel.get('location', 'City Center')}",
                "location": confirmed_hotel.get('location', 'City Center'),
                "estimated_duration": "Overnight"
            })
        
        # LAST DAY: Add checkout and departure
        if day == num_days - 1:
            # Early morning: Add any remaining attractions
            remaining_time = "07:00 AM"
            remaining_count = 0
            while attraction_index < len(attractions) and remaining_count < 2:  # Max 2 early morning activities
                attraction = attractions[attraction_index]
                day_activities.insert(0, {  # Add at the beginning
                    "time": remaining_time,
                    "activity_type": "attraction",
                    "icon": "📍",
                    "name": attraction.get("name", "Unknown"),
                    "description": attraction.get("description", ""),
                    "details": f"Category: {attraction.get('category', 'General')}",
                    "location": attraction.get("location", ""),
                    "estimated_duration": "1 hour"
                })
                attraction_index += 1
                remaining_count += 1
                remaining_time = "09:00 AM"  # Next slot
                
            # Checkout
            if confirmed_hotel:
                day_activities.append({
                    "time": "11:00 AM",
                    "activity_type": "hotel",
                    "icon": "🏨",
                    "name": f"Check-out from {confirmed_hotel.get('title', 'Hotel')}",
                    "description": "End of stay",
                    "details": f"Address: {confirmed_hotel.get('location', 'City Center')}",
                    "location": confirmed_hotel.get('location', 'City Center'),
                    "estimated_duration": "30 mins"
                })
            
            # Departure transport
            if confirmed_transport:
                day_activities.append({
                    "time": "02:00 PM",
                    "activity_type": "transport",
                    "icon": "✈️",
                    "name": f"Depart via {confirmed_transport.get('title', 'Flight')}",
                    "description": "Return journey",
                    "details": f"Flight Number: {confirmed_transport.get('flight_number', 'TBD')}, Departs: {city}" if 'flight_number' in confirmed_transport else f"From: {city}, To: {confirmed_transport.get('from', 'Home')}",
                    "location": f"{city} Airport",
                    "estimated_duration": "Check-in 2 hours before flight"
                })
        
        # Get weather forecast for this day
        weather = get_weather_forecast(city, day_date.strftime("%Y-%m-%d"))
        
        itinerary["daily_schedule"].append({
            "day": day + 1,
            "date": day_date.strftime("%Y-%m-%d"),
            "day_name": day_date.strftime("%A"),
            "weather": weather,  # Add weather information
            "activities": day_activities
        })
    
    return {
        "status": "success",
        "itinerary": itinerary,
        "message": f"✅ Itinerary created for {num_days} days with {len(attractions)} attractions!"
    }


def add_to_itinerary(
    tool_context: dict,
    attraction_name: str,
    location: str = "",
    description: str = "",
    category: str = "General"
) -> dict:
    """
    Adds a single attraction to the user's itinerary collection.
    
    Args:
        tool_context: Context containing user's saved attractions
        attraction_name: Name of the attraction
        location: Location/city of the attraction
        description: Description of the attraction
        category: Category (e.g., Historical, Nature, Entertainment)
    
    Returns:
        Confirmation message with current count of saved attractions
    """
    if "saved_attractions" not in tool_context:
        tool_context["saved_attractions"] = []
    
    new_attraction = {
        "name": attraction_name,
        "location": location,
        "description": description,
        "category": category,
        "added_at": datetime.now().isoformat()
    }
    
    tool_context["saved_attractions"].append(new_attraction)
    
    return {
        "status": "success",
        "message": f"✅ Added '{attraction_name}' to your itinerary! Total saved: {len(tool_context['saved_attractions'])}",
        "total_saved": len(tool_context["saved_attractions"])
    }


def view_saved_attractions(tool_context: dict) -> dict:
    """
    Shows all attractions that have been saved for the itinerary.
    
    Returns:
        List of all saved attractions
    """
    saved = tool_context.get("saved_attractions", [])
    
    if not saved:
        return {
            "status": "empty",
            "message": "No attractions saved yet. Swipe right on some places to add them!",
            "attractions": []
        }
    
    return {
        "status": "success",
        "message": f"You have {len(saved)} attractions saved:",
        "attractions": saved
    }


def generate_final_itinerary(
    tool_context: dict,
    start_date: str = "",
    num_days: int = 0,
    preferences: str = ""
) -> dict:
    """
    Generates the complete itinerary from all saved attractions WITH SPECIFIC hotel, flight, and restaurant details.
    
    Args:
        tool_context: Context containing saved attractions, selected hotels, and transport
        start_date: Trip start date (YYYY-MM-DD)
        num_days: Number of days for the trip
        preferences: Any special preferences for organizing the itinerary
    
    Returns:
        Formatted itinerary with daily schedule INCLUDING specific bookings
    """
    saved = tool_context.get("saved_attractions", [])
    
    if not saved:
        return {
            "status": "error",
            "message": "No attractions to create itinerary from. Please swipe right on some places first!"
        }
    
    # Get context values
    if not start_date:
        start_date = tool_context.get("start_date", "2025-11-15")
    if not num_days or num_days == 0:
        num_days = tool_context.get("duration_days", 3)
    city = tool_context.get("to", tool_context.get("stay_city", "India"))
    
    # Get hotel and transport from context
    selected_hotels = tool_context.get("selected_hotels", [])
    selected_transport = tool_context.get("selected_transport", [])
    
    # Convert string lists to dict lists if needed
    if selected_hotels and isinstance(selected_hotels[0], str):
        selected_hotels = [{"title": h} for h in selected_hotels]
    if selected_transport and isinstance(selected_transport[0], str):
        selected_transport = [{"title": t} for t in selected_transport]
    
    itinerary_result = create_itinerary(
        saved, start_date, num_days, preferences,
        selected_hotels=selected_hotels,
        selected_transport=selected_transport,
        city=city
    )
    
    if itinerary_result.get("status") == "success":
        # Create suggestions for swipeable itinerary confirmation
        itinerary = itinerary_result["itinerary"]
        suggestions = []
        
        # Calculate end date
        start = datetime.strptime(start_date, "%Y-%m-%d")
        end_date = (start + timedelta(days=num_days-1)).strftime("%Y-%m-%d")
        
        # Add hotel booking suggestion
        if selected_hotels and len(selected_hotels) > 0:
            confirmed_hotel = selected_hotels[0]
            suggestions.append({
                "type": "hotel",
                "title": f"🏨 {confirmed_hotel.get('title', 'Hotel Booking')}",
                "description": confirmed_hotel.get('description', 'Your accommodation for the trip'),
                "location": confirmed_hotel.get('location', 'City Center'),
                "price": confirmed_hotel.get('price', 'TBD'),
                "rating": confirmed_hotel.get('rating', 'N/A'),
                "image": confirmed_hotel.get('image', ''),
                "details": f"Check-in: {start_date}, Check-out: {end_date}",
                "current_weather": get_weather_forecast(city, start_date)  # Current weather at destination
            })
        
        # Add transport booking suggestion
        if selected_transport and len(selected_transport) > 0:
            confirmed_transport = selected_transport[0]
            suggestions.append({
                "type": "transport",
                "title": f"✈️ {confirmed_transport.get('title', 'Transport Booking')}",
                "description": confirmed_transport.get('description', 'Your transportation for the trip'),
                "location": f"{confirmed_transport.get('from', 'Origin')} → {confirmed_transport.get('to', city)}",
                "price": confirmed_transport.get('price', 'TBD'),
                "rating": confirmed_transport.get('rating', 'N/A'),
                "image": confirmed_transport.get('image', ''),
                "details": f"Departure: {start_date}",
                "current_weather": get_weather_forecast(city, start_date)
            })
        
        # Add daily activity suggestions
        for day_schedule in itinerary["daily_schedule"]:
            day_num = day_schedule['day']
            day_name = day_schedule['day_name']
            date = day_schedule['date']
            weather = day_schedule.get('weather', {})
            
            # Create a summary of activities for this day
            activities_summary = []
            for activity in day_schedule["activities"]:
                activities_summary.append(f"{activity['time']}: {activity['name']}")
            
            suggestions.append({
                "type": "itinerary_day",
                "title": f"📅 Day {day_num}: {day_name}",
                "description": f"Activities planned for {date}",
                "location": city,
                "details": "\n".join(activities_summary[:3]),  # Show first 3 activities
                "current_weather": weather,  # Weather for this day
                "highlights": f"{len(day_schedule['activities'])} activities planned",
                "date": date
            })
        
        # Format the itinerary nicely for the message
        formatted = f"\n✈️ **{itinerary['trip_title']}**\n"
        formatted += f"📅 Start Date: {itinerary['start_date']}\n"
        formatted += f"🏨 Hotel: {itinerary['hotel']}\n"
        formatted += f"🚗 Transport: {itinerary['transport']}\n"
        formatted += f"📍 Total Attractions: {itinerary['total_attractions']}\n\n"
        formatted += "✅ **Swipe through the suggestions below to confirm your itinerary!**\n"
        
        return {
            "status": "success",
            "itinerary": itinerary,
            "formatted_itinerary": formatted,
            "message": formatted,
            "show_suggestions": True,
            "suggestions": suggestions
        }
    
    return itinerary_result


def clear_saved_attractions(tool_context: dict) -> dict:
    """
    Clears all saved attractions from the itinerary.
    
    Returns:
        Confirmation message
    """
    count = len(tool_context.get("saved_attractions", []))
    tool_context["saved_attractions"] = []
    
    return {
        "status": "success",
        "message": f"✅ Cleared {count} attractions from your itinerary. Start fresh!"
    }


# Create the itinerary agent
itinerary_agent = Agent(
    model="gemini-3.7-flash",
    name="itinerary_agent",
    description="Expert itinerary planning assistant that creates detailed day-by-day schedules with SPECIFIC hotel names, flight details, and restaurant recommendations",
    instruction="""You are an expert Itinerary Planning Assistant that helps users create organized travel plans with SPECIFIC details.

**Your Capabilities:**
1. **Add Attractions**: Save attractions that users swipe right on or manually add
2. **View Collection**: Show all saved attractions at any time
3. **Generate SPECIFIC Itinerary**: Create a complete day-by-day schedule with:
   - Actual confirmed hotel names (e.g., "Beach Paradise Resort")
   - Actual confirmed flight/transport details (e.g., "Air India AI-682")
   - Specific restaurant recommendations with names, cuisine, and ratings (e.g., "Fisherman's Wharf - Goan Seafood - 4.5⭐")
   - Detailed timings for check-in, check-out, meals, and activities
4. **Clear & Reset**: Remove all attractions to start planning a new trip

**How to Help Users:**

1. **When user swipes right on attractions:**
   - Automatically add each right-swiped attraction using `add_to_itinerary()`
   - Confirm each addition: "✅ Added [Attraction] to your itinerary!"
   - Keep track of the total count

2. **When user asks "what have I saved?" or "show my attractions":**
   - Use `view_saved_attractions()` to display the list
   - Show it in a clear, organized format

3. **When user says "create my itinerary" or "plan my trip":**
   - First, ask for:
     * Start date (YYYY-MM-DD format)
     * Number of days (e.g., 3 days, 5 days)
     * Any preferences (optional)
   - Then use `generate_final_itinerary()` to create the complete plan
   - Present the day-by-day schedule with SPECIFIC details:
     * Day 1: Flight arrival (with airline and flight number), Hotel check-in (with actual hotel name), Lunch at [Specific Restaurant Name], Attractions, Dinner at [Specific Restaurant Name]
     * Day 2-N: Breakfast, Attractions, Lunch at [Specific Restaurant Name], More Attractions, Dinner at [Specific Restaurant Name], Return to [Hotel Name]
     * Last Day: Checkout from [Hotel Name], Departure flight (with airline and flight number)

4. **When user wants to start over:**
   - Use `clear_saved_attractions()` to reset
   - Confirm: "All cleared! Ready to plan a new trip."

**Important Guidelines:**
- Always confirm when attractions are added
- Keep users informed of their saved count
- Ask for missing information (dates, days) before generating itinerary
- Make the final itinerary SPECIFIC with actual names (not generic "Hotel" or "Restaurant")
- Include meal recommendations for breakfast, lunch, and dinner with actual restaurant names
- Include hotel check-in/checkout with the actual confirmed hotel name
- Include flight/transport details with actual airline/operator names
- Make the itinerary easy to read, follow, and actionable
- Be enthusiastic and helpful about trip planning!

**Example Itinerary Output:**
Day 1 - Monday, 2025-11-15
✈️ 08:00 AM - Arrive via Air India AI-682
   Flight Number: AI-682, Departs: Mumbai, Arrives: Goa
🏨 11:00 AM - Check-in at Beach Paradise Resort
   Address: Calangute Beach, Rating: 4.5⭐, Price: ₹₹₹
🍽️ 01:00 PM - Lunch at Fisherman's Wharf
   Goan Seafood cuisine, Rating: 4.5⭐, Location: Panjim
📍 03:00 PM - Calangute Beach
   Beach relaxation and water sports
🍴 08:00 PM - Dinner at Black Sheep Bistro
   European cuisine, Rating: 4.5⭐, Location: Panjim

Remember: You're creating memorable travel experiences with SPECIFIC, actionable details! 🗺️✨
""",
    tools=[add_to_itinerary, view_saved_attractions, generate_final_itinerary, clear_saved_attractions]
)

