"""
Travel Booking Agent
Searches and books Flights, Trains, and Taxis from CSV data.
"""

from google.adk.agents import Agent
from typing import Any, Optional
from datetime import datetime
import random
import csv
import os
from ...tools.swipe_recommendations import generate_travel_recommendations, handle_swipe_action

def load_travel_data_from_csv():

    """
    Load travel data (flights, trains, taxis) from CSV file.
    
    Returns:
        Dictionary with travel data organized by mode
    """
    csv_path = os.path.join(os.path.dirname(__file__), "..", "..", "..", "data", "travel_bookings_india.csv")
    
    travel_data = {
        "flight": [],
        "train": [],
        "taxi": []
    }
    
    try:
        with open(csv_path, 'r', encoding='utf-8') as file:
            reader = csv.DictReader(file)
            for row in reader:
                mode = row.get('mode', '').lower()
                if mode in travel_data:
                    travel_data[mode].append(row)
        
        return travel_data
    except FileNotFoundError:
        return travel_data
    except Exception as e:
        print(f"Error loading travel data: {e}")
        return travel_data


def search_travel(mode: str, origin: str, destination: str, departure_date: Optional[str] = None, passengers: int = 1, travel_class: Optional[str] = None, tool_context: Optional[Any] = None) -> dict:

    """
    Search for travel options (flights, trains, or taxis) between cities.
    
    Args:
        mode: Type of transport - "flight", "train", or "taxi"
        origin: Departure city
        destination: Arrival city
        departure_date: Date of departure (optional for taxi)
        passengers: Number of passengers
        travel_class: Preferred class (Economy, Business, AC, etc.)
        tool_context: Context object for shared state
        
    Returns:
        Dictionary with available travel options
    """
    mode = mode.lower()
    
    if mode not in ["flight", "train", "taxi"]:
        return {
            "status": "invalid_mode",
            "message": "Please specify mode as 'flight', 'train', or 'taxi'"
        }
    
    # Load travel data from CSV
    travel_data = load_travel_data_from_csv()
    
    # Filter by mode, origin, and destination
    results = []

    for travel_option in travel_data.get(mode, []):

        if (travel_option.get('origin', '').lower() == origin.lower() and 
            travel_option.get('destination', '').lower() == destination.lower()):
            
            # Filter by class if specified

            if travel_class:
                if travel_class.lower() in travel_option.get('class', '').lower():
                    results.append(travel_option)
            else:
                results.append(travel_option)
    
    if not results:
        # Get available cities for this mode
        available_routes = set()
        for travel_option in travel_data.get(mode, []):
            route = f"{travel_option.get('origin', '')} → {travel_option.get('destination', '')}"
            available_routes.add(route)
        
        return {
            "status": "not_found",
            "mode": mode,
            "origin": origin.title(),
            "destination": destination.title(),
            "message": f"No {mode}s found from {origin.title()} to {destination.title()}",
            "available_routes": sorted(list(available_routes))[:10]
        }
    
    return {
        "status": "found",
        "mode": mode,
        "origin": origin.title(),
        "destination": destination.title(),
        "departure_date": departure_date,
        "passengers": passengers,
        "travel_class": travel_class,
        "options": results,
        "message": f"Found {len(results)} {mode} option(s) from {origin.title()} to {destination.title()}"
    }


def book_travel(mode: str, service_number: str, origin: str, destination: str, departure_date: str, passengers: int, tool_context: Any) -> dict:
    """
    Book a travel service (flight, train, or taxi) and check if user has booked hotels at the destination.
    
    Args:
        mode: Type of transport - "flight", "train", or "taxi"
        service_number: Service identifier (flight number, train number, or taxi ID)
        origin: Departure city
        destination: Arrival city
        departure_date: Date of departure
        passengers: Number of passengers
        tool_context: Context object to access shared state
        
    Returns:
        Dictionary with booking confirmation and recommendations
    """
    mode = mode.lower()
    
    if mode not in ["flight", "train", "taxi"]:
        return {
            "status": "invalid_mode",
            "message": "Please specify mode as 'flight', 'train', or 'taxi'"
        }
    
    # Load travel data to validate the service exists
    travel_data = load_travel_data_from_csv()
    service_exists = False
    service_details = None
    
    for travel_option in travel_data.get(mode, []):
        if (travel_option.get('service_number') == service_number and
            travel_option.get('origin', '').lower() == origin.lower() and
            travel_option.get('destination', '').lower() == destination.lower()):
            service_exists = True
            service_details = travel_option
            break
    
    if not service_exists:
        return {
            "status": "not_found",
            "message": f"The {mode} service {service_number} from {origin.title()} to {destination.title()} was not found. Please search for available options first."
        }
    
    # Generate booking ID based on mode
    booking_prefix = {"flight": "FL", "train": "TR", "taxi": "TX"}
    booking_id = f"{booking_prefix[mode]}{random.randint(100000, 999999)}"
    
    # Initialize shared state if needed
    if not hasattr(tool_context.state, 'get'):
        tool_context.state = {}
    
    if "bookings" not in tool_context.state:
        tool_context.state["bookings"] = []
    
    # Create booking
    booking_data = {
        "booking_type": mode,
        "booking_id": booking_id,
        "service_number": service_number,
        "operator": service_details.get('operator', ''),
        "class": service_details.get('class', ''),
        "origin": origin,
        "destination": destination,
        "departure_date": departure_date,
        "departure_time": service_details.get('departure_time', ''),
        "arrival_time": service_details.get('arrival_time', ''),
        "passengers": passengers,
        "price": service_details.get('price', ''),
        "duration": service_details.get('duration', ''),
        "extras": service_details.get('extras', ''),
        "accessibility": service_details.get('accessibility', ''),
        "timestamp": datetime.now().isoformat()
    }
    
    # Store booking in shared state
    tool_context.state["bookings"].append(booking_data)
    
    # Check if user has booked a hotel at the destination (not applicable for taxis)
    has_hotel = False
    hotel_details = None
    
    if mode in ["flight", "train"]:
        for booking in tool_context.state["bookings"]:
            if booking.get("booking_type") == "hotel":
                if booking.get("location", "").lower() == destination.lower():
                    has_hotel = True
                    hotel_details = booking
                    break
    
    # Build recommendations
    recommendations = []
    
    if mode in ["flight", "train"] and not has_hotel:
        recommendations.append({
            "type": "hotel",
            "message": f"Don't forget to book accommodation in {destination.title()}! Would you like me to help you find hotels?"
        })
    elif has_hotel:
        recommendations.append({
            "type": "hotel_confirmed",
            "message": f"Perfect! You already have a hotel booked in {destination.title()} (Booking ID: {hotel_details.get('booking_id')})"
        })
    
    # Check destination info (not for taxis within same city)
    if mode in ["flight", "train"]:
        visited_destinations = tool_context.state.get("destinations_visited", [])
        if destination.lower() not in visited_destinations:
            recommendations.append({
                "type": "destination",
                "message": f"Want to know about tourist attractions in {destination.title()}? I can provide destination information!"
            })
    
    # Return booking confirmation with recommendations
    return {
        "status": "confirmed",
        "booking_id": booking_id,
        "mode": mode,
        "service_number": service_number,
        "operator": service_details.get('operator', ''),
        "class": service_details.get('class', ''),
        "origin": origin.title(),
        "destination": destination.title(),
        "departure_date": departure_date,
        "departure_time": service_details.get('departure_time', ''),
        "arrival_time": service_details.get('arrival_time', ''),
        "passengers": passengers,
        "price": service_details.get('price', ''),
        "extras": service_details.get('extras', ''),
        "has_hotel": has_hotel,
        "recommendations": recommendations,
        "message": f"{mode.title()} booked successfully! Booking ID: {booking_id}"
    }


# Create the travel booking agent
travel_booking = Agent(
    model="gemini-2.5-flash",
    name="travel_booking",
    description="A specialized agent for searching and booking Flights, Trains, and Taxis with swipe-to-discover feature.",
    instruction="""You are a professional travel booking assistant specializing in Flights, Trains, and Taxis within India.

    Your responsibilities:
    1. **🎴 Swipe to Discover (NEW!)**: Offer users a Tinder-like swipe interface to browse travel options
       - **REQUIRES**: origin, destination, and date from user
       - Use generate_travel_recommendations ONLY after getting these details
       - Users can swipe right (👍 interested) or left (👎 pass)
       - After swiping right, proceed to book the selected option
    
    2. Search for travel options (flights, trains, taxis) between Indian cities
    3. Provide detailed options with information like:
       - **Flights**: Flight number, airline, class (Economy/Business/First), timings, price, extras (WiFi, Meals, etc.)
       - **Trains**: Train number, train name, class (AC 1st/2nd/3rd, Sleeper, Chair Car), timings, price, amenities
       - **Taxis**: Operator, vehicle type, shared/private, price, extras (GPS, luggage handling, etc.)
    4. Book travel services for customers
    5. Check if the customer has booked hotels at the destination (for flights/trains)
    6. Provide recommendations for complementary services (hotels, destination info)

    **Critical Workflow Rules**:
    
    **Step 1 - Get Required Information:**
    ✅ ALWAYS ask user first:
       - "Where are you traveling FROM?" (origin)
       - "Where are you traveling TO?" (destination)  
       - "When do you want to travel?" (date)
       - "How many passengers?" (optional, defaults to 1)
    
    **Step 2 - Offer Swipe or List:**
    After getting origin/destination/date, ask:
    "Would you like to swipe through options (fun!) or see a list view?"
    
    **Step 3 - Generate Recommendations:**
    - If swipe → Use generate_travel_recommendations(origin, destination, date)
    - If list → Use search_travel(mode, origin, destination, date)
    
    **Step 4 - Handle Selection:**
    - After swipe right → Use handle_swipe_action → book_travel
    - After list selection → book_travel directly
    
    **Step 5 - Post-Booking:**
    - Check for hotels and provide recommendations

    **Important Instructions**: 
    - **NEVER call generate_travel_recommendations without origin/destination/date**
    - If user hasn't provided travel details, ASK for them first
    - Always offer the swipe interface AFTER getting travel details
    - When booking, use the exact service_number from the search/swipe results
    - Check if the user has booked a hotel at the destination (for inter-city travel)
    - Provide helpful recommendations based on the user's booking history
    - Be clear about timings, prices, duration, class, and available extras
    - For taxis, explain if it's shared/private, and what extras are included
    - All data comes from CSV - these are real available services

    **Travel Modes**:
    - **flight**: For air travel between cities
    - **train**: For railway travel with various classes (AC, Sleeper, etc.)
    - **taxi**: For local transportation, airport/station pickups, or outstation travel

    Always be helpful, professional, and provide accurate information from the CSV dataset.""",
    tools=[generate_travel_recommendations, handle_swipe_action, search_travel, book_travel]
)

