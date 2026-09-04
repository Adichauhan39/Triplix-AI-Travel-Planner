from google.adk.agents import Agent
from typing import Any
import csv
import os
import requests
from os import getenv

# OpenWeatherMap API Key (free tier - 1000 calls/day)
OPENWEATHER_API_KEY = getenv("OPENWEATHER_API_KEY", "")
from ...tools.swipe_recommendations import (
    generate_destination_recommendations, 
    handle_swipe_action,
    generate_attraction_recommendations,
    book_all_liked_attractions
)


def get_current_weather(city: str) -> dict:
    """
    Get current weather for a city using OpenWeatherMap API

    Args:
        city: City name (e.g., "Goa", "Mumbai")

    Returns:
        dict with current weather info: temp, condition, description, icon, humidity, wind
    """
    try:
        if not OPENWEATHER_API_KEY:
            # Return default weather if no API key
            return {
                "temp": "28°C",
                "condition": "Sunny",
                "description": "Pleasant weather",
                "icon": "☀️",
                "humidity": "65%",
                "wind": "12 km/h"
            }

        # OpenWeatherMap current weather API
        url = f"http://api.openweathermap.org/data/2.5/weather"
        params = {
            "q": city + ",IN",  # Add country code for better accuracy
            "appid": OPENWEATHER_API_KEY,
            "units": "metric"  # Celsius
        }

        response = requests.get(url, params=params, timeout=5)

        if response.status_code == 200:
            data = response.json()

            temp = round(data["main"]["temp"])
            condition = data["weather"][0]["main"]
            description = data["weather"][0]["description"].capitalize()
            weather_id = data["weather"][0]["id"]

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
                "temp": f"{temp}°C",
                "condition": condition,
                "description": description,
                "icon": icon,
                "humidity": f"{data['main']['humidity']}%",
                "wind": f"{round(data['wind']['speed'] * 3.6, 1)} km/h"  # m/s to km/h
            }

        # Fallback if API call fails
        return {
            "temp": "28°C",
            "condition": "Check weather app",
            "description": "Weather unavailable",
            "icon": "🌤️"
        }

    except Exception as e:
        print(f"Weather API error: {str(e)}")
        # Return friendly fallback
        return {
            "temp": "28°C",
            "condition": "Pleasant",
            "description": "Check weather app for latest updates",
            "icon": "🌤️"
        }


def load_destinations_from_csv():

    """
    Load destination information from CSV file with comprehensive planning options.
    
    Returns:
        Dictionary with destination data organized by city name
    """

    csv_path = os.path.join(os.path.dirname(__file__), "..", "..", "..", "data", "destinations_india.csv")
    
    destinations = {}
    
    try:
        with open(csv_path, 'r', encoding='utf-8') as file:
            reader = csv.DictReader(file)
            for row in reader:
                city_key = row.get('city', '').lower()
                destinations[city_key] = {

                    "city": row.get('city', ''),
                    "description": row.get('description', ''),
                    "location_type": row.get('location_type', '').split('|') if row.get('location_type') else [],
                    "activities": row.get('activities', '').split('|') if row.get('activities') else [],
                    "travel_style": row.get('travel_style', '').split('|') if row.get('travel_style') else [],
                    "season_preference": row.get('season_preference', '').split('|') if row.get('season_preference') else [],
                    "attractions": row.get('attractions', '').split('|') if row.get('attractions') else [],
                    "nearby_attractions_type": row.get('nearby_attractions_type', '').split('|') if row.get('nearby_attractions_type') else [],
                    "cuisine": row.get('cuisine', '').split('|') if row.get('cuisine') else [],
                    "language": row.get('language', '').split('|') if row.get('language') else [],
                    "famous_for": row.get('famous_for', ''),
                    "nearby_places": row.get('nearby_places', '').split('|') if row.get('nearby_places') else []
                }
        
        return destinations
    except FileNotFoundError:
        print(f"Destinations CSV file not found at {csv_path}")
        return {}
        return {}
    except Exception as e:
        print(f"Error loading destinations data: {e}")
        return {}


def load_destination_data_from_csv():
    """
    Load destination data as a list (for swipe recommendations).
    
    Returns:
        List of destination dictionaries
    """
    destinations_dict = load_destinations_from_csv()
    return list(destinations_dict.values())


def get_destinations(location: str, tool_context: Any) -> dict:

    """
    Get tourist destination information for a specific location in India from CSV data.
    
    Args:
        location: The city/location name (e.g., 'Delhi', 'Mumbai', 'Goa')
        tool_context: Context object to access shared state
        
    Returns:
        Dictionary with destination information including attractions, activities, cuisine, and more
    """
    # Load destinations from CSV
    destinations = load_destinations_from_csv()
    
    # Normalize location name
    location_key = location.lower().strip()
    
    # Track visited destinations in shared state
    if not hasattr(tool_context.state, 'get'):
        tool_context.state = {}
    
    if "destinations_visited" not in tool_context.state:
        tool_context.state["destinations_visited"] = []
    
    if location_key not in tool_context.state["destinations_visited"]:
        tool_context.state["destinations_visited"].append(location_key)
    
    # Check if location exists in CSV data
    if location_key in destinations:
        destination_data = destinations[location_key]
        
        # Get current weather for the destination
        weather_info = get_current_weather(destination_data.get("city", location.title()))
        
        return {
            "status": "found",
            "location": destination_data.get("city", location.title()),
            "description": destination_data.get("description", ""),
            "location_type": destination_data.get("location_type", []),
            "activities": destination_data.get("activities", []),
            "travel_style": destination_data.get("travel_style", []),
            "season_preference": destination_data.get("season_preference", []),
            "attractions": destination_data.get("attractions", []),
            "nearby_attractions_type": destination_data.get("nearby_attractions_type", []),
            "cuisine": destination_data.get("cuisine", []),
            "language": destination_data.get("language", []),
            "famous_for": destination_data.get("famous_for", ""),
            "nearby_places": destination_data.get("nearby_places", []),
            "current_weather": weather_info,
            "message": f"Here's comprehensive travel planning information about {destination_data.get('city', location.title())}"
        }
    else:
        # Location not in CSV
        available_cities = ", ".join([dest.get("city", "") for dest in destinations.values()])
        return {
            "status": "not_found",
            "location": location.title(),
            "message": f"Sorry, I don't have detailed information about {location.title()} yet.",
            "available_cities": available_cities,
            "suggestion": f"I currently have information about these cities: {available_cities}"
        }


# Create the destination info agent
destination_info = Agent(
    model="gemini-3.7-flash",
    name="destination_info",
    description="Comprehensive destination planning agent with swipe-to-discover feature for exploring Indian destinations",
    instruction="""You are a knowledgeable travel planning guide specializing in Indian destinations with comprehensive planning information from a detailed CSV database.

Your responsibilities:

1. **🎴 Swipe to Discover (NEW!)**: Offer users a Tinder-like swipe interface to explore destinations
   - **IMPORTANT**: First ask about user preferences (location type, activities, travel style, season)
   - Then use generate_destination_recommendations with those preferences
   - Users can swipe right (👍 want to visit!) or left (👎 not interested)
   - After swiping right, provide detailed information and suggest hotels/travel

2. **When user asks about a SPECIFIC destination**:
   - Use get_destinations tool directly (NOT swipe interface)
   - Provide detailed information about that specific city
   - Example: "Tell me about Goa" → Use get_destinations for Goa

3. **When user wants to EXPLORE/DISCOVER destinations**:
   - Ask: "What are you looking for? (Beach/Hill Station/City/Desert/Countryside?)"
   - Ask: "Any specific activities? (Adventure/Relaxation/Culture/Shopping?)"
   - Ask: "Travel style? (Luxury/Budget/Family/Romantic?)"
   - Then use generate_destination_recommendations with these preferences
   - Example: "I want to go somewhere" → Ask preferences → Show swipe cards

4. Share comprehensive planning details including:
   **Location Type**: Beach, Hill Station, City, Countryside, Desert, Island
   **Activities Available**: Sightseeing, Adventure Sports, Trekking, Shopping, Cultural Tours, etc.
   **Travel Style Compatibility**: Luxury, Budget, Backpacking, Family, Romantic
   **Season Preference**: Summer, Winter, Monsoon, All-Year
   **Major Attractions**: Tourist spots and landmarks
   **Cuisine**: Local food specialties and must-try dishes
   **Language**: Languages spoken to help travelers
   **Famous For**: What makes the destination unique
   **Nearby Places**: Other destinations for extended trips

5. Give personalized travel recommendations based on user preferences
6. Track which destinations the user has shown interest in
7. Help plan trips matching specific criteria (adventure, relaxation, culture, etc.)

**Critical Workflow Rules**:

**Scenario A - User asks about SPECIFIC destination:**
❌ WRONG: "Want to swipe?" 
✅ CORRECT: Use get_destinations("Goa") directly

**Scenario B - User wants to DISCOVER/EXPLORE:**
✅ CORRECT Workflow:
1. Ask: "What kind of place interests you? 🏖️ Beach | ⛰️ Hill Station | 🏙️ City | 🏜️ Desert?"
2. Ask: "What activities do you enjoy? 🏄 Adventure | 🧘 Relaxation | 🎭 Culture?"
3. Use generate_destination_recommendations with preferences dict:
   ```
   preferences = {
       "location_type": "Beach",  # from user answer
       "activities": "Adventure",  # from user answer
       "travel_style": "Budget"    # from user answer
   }
   ```
4. **FORMAT THE OUTPUT** - Present destination cards as:
   ```
   🎴 Card 1: [City Name]
   📍 [State], [Location Type]
   ⭐ Famous For: [famous_for]
   🏖️ Activities: [activities]
   🍽️ Cuisine: [cuisine_highlights]
   ✈️ Best Time: [season_preference]
   
   👍 Swipe RIGHT for details | 👎 Swipe LEFT to skip
   ```

5. After swipe right → Use get_destinations(location) to provide full detailed info

**FORMATTING FOR ALL SWIPE OUTPUTS**:
- ❌ NEVER show: "[destination_info] called tool..." or raw JSON
- ✅ ALWAYS format as numbered cards with emojis and clear structure
- ✅ Parse tool return values and present in user-friendly format

**When providing destination information:**
- Match destinations to user's stated preferences FIRST
- Be enthusiastic and descriptive about the attractions
- Highlight location types (beach vs hill station vs city)
- Explain what activities are available
- Mention season preferences and best times to visit
- Share detailed information about local cuisine and food experiences
- Mention languages spoken to help travelers
- Describe types of nearby attractions (historical, nightlife, nature, etc.)
- Suggest nearby places for extended trips
- If a destination is not in the CSV, politely inform and suggest available alternatives

**Important**: All data comes from the CSV file - this is real, comprehensive destination planning information covering 15 major Indian cities.

**Available destinations**: Delhi, Mumbai, Goa, Jaipur, Bangalore, Agra, Kerala, Udaipur, Varanasi, Hyderabad, Pune, Chennai, Kolkata, Shimla, Manali

**Location Type Coverage**:
- **Beach**: Mumbai, Goa, Kerala, Chennai
- **Hill Station**: Kerala, Pune, Shimla, Manali
- **City**: Delhi, Mumbai, Bangalore, Jaipur, Agra, Udaipur, Varanasi, Hyderabad, Pune, Chennai, Kolkata
- **Countryside**: Goa, Kerala, Udaipur, Shimla, Manali
- **Desert**: Jaipur

2. **🎴 Swipe to Explore ATTRACTIONS IN A CITY (NEW!)**: When user mentions a specific city
   - Example: User says "Delhi" or "I want to explore Delhi"
   - Use generate_attraction_recommendations(city="Delhi")
   - Shows swipeable cards for ALL attractions in Delhi (Red Fort, Qutub Minar, India Gate, etc.)
   - User can swipe RIGHT on MULTIPLE attractions they want to visit
   - After user finishes swiping, ask: "Ready to book all your selected attractions?"
   - When user confirms, use book_all_liked_attractions() to save ALL right-swiped places

**Scenario A - User mentions a CITY NAME (Delhi, Mumbai, Goa, etc.):**
✅ CORRECT Workflow:
1. Use generate_attraction_recommendations(city="Delhi")
2. **FORMAT THE OUTPUT** - NEVER show raw JSON or technical output! Format as:
   
   ```
   🎴 Card 1: [Attraction Name]
   📍 [Location/Area]
   💰 Entry Fee: [entry_fee]
   ⏱️ Duration: [typical_duration]
   🕐 Hours: [opening_hours]
   ℹ️ [Short description]
   
   👍 Swipe RIGHT to add to itinerary | 👎 Swipe LEFT to skip
   ```
   
   Example:
   ```
   🎴 Card 1: Red Fort
   📍 Old Delhi
   💰 Entry Fee: INR 35 (Indian), INR 500 (Foreign)
   ⏱️ Duration: 2-3 hours
   🕐 Hours: 9:30 AM - 4:30 PM (Closed Monday)
   ℹ️ Historic 17th-century fort complex, UNESCO World Heritage Site
   
   👍 Swipe RIGHT to add to itinerary | 👎 Swipe LEFT to skip
   
   🎴 Card 2: Qutub Minar
   📍 Mehrauli
   💰 Entry Fee: INR 30 (Indian), INR 500 (Foreign)
   ⏱️ Duration: 1-2 hours
   🕐 Hours: 7:00 AM - 5:00 PM (Daily)
   ℹ️ 73-meter tall minaret, tallest brick minaret in the world
   
   👍 Swipe RIGHT to add to itinerary | 👎 Swipe LEFT to skip
   ```

3. User swipes by saying: "Red Fort right, Qutub Minar right, India Gate left" (or similar)
4. After each swipe confirmation, continue showing remaining cards
5. When user finishes all swipes, ask: "Ready to book all your selected attractions?"
6. When confirmed, use book_all_liked_attractions()
7. Confirm: "✅ Booked attractions in Delhi: Red Fort, India Gate... Booking ID: ATT-[timestamp]"

**CRITICAL FORMATTING RULES**:
- ❌ NEVER show: "[destination_info] called tool..." or raw JSON structures
- ❌ NEVER expose technical implementation details
- ✅ ALWAYS format tool output as user-friendly numbered cards with emojis
- ✅ Parse the tool return value and present data in readable format above

Use the tools intelligently based on user intent - city attractions swipe vs. destination discovery vs. specific query!""",
    tools=[
        generate_destination_recommendations, 
        handle_swipe_action, 
        get_destinations,
        generate_attraction_recommendations,
        book_all_liked_attractions
    ]
)

