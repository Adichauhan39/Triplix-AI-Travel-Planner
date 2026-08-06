import os
import requests
from typing import Dict, Any, List
from datetime import datetime
from dotenv import load_dotenv

# Load environment variables from .env file
load_dotenv()

def get_current_time() -> Dict[str, Any]:
    """
    Get the current date and time.
    
    Returns:
        Dict containing current datetime information
    """
    now = datetime.now()
    return {
        "current_date": now.strftime("%Y-%m-%d"),
        "current_time": now.strftime("%H:%M:%S"),
        "day_of_week": now.strftime("%A"),
        "timestamp": now.isoformat()
    }

def get_hotel_location_and_images(hotel_name: str, city: str) -> Dict[str, Any]:
    """
    Get location and images for a specific hotel using Google Places API.
    Returns ONLY Google Maps links and Google Places API image URLs.
    
    Args:
        hotel_name: Name of the hotel
        city: City where hotel is located
        
    Returns:
        Dict containing Google Maps link, address, coordinates, and Google Places photo URLs
    """
    api_key = os.getenv('GOOGLE_PLACES_API_KEY')
    
    if not api_key:
        print("\033[91m WARNING: GOOGLE_PLACES_API_KEY not found in environment \033[0m")
        return {
            "hotel_name": hotel_name,
            "city": city,
            "error": "Google Places API key not configured",
            "map_link": f"https://www.google.com/maps/search/{hotel_name.replace(' ', '+')}+{city.replace(' ', '+')}",
            "images": [],
            "address": "API key not configured - cannot fetch location",
            "message": "Please configure GOOGLE_PLACES_API_KEY in .env file"
        }
    
    print(f" Searching Google Places for: {hotel_name} in {city}")
    
    try:
        # Search for the place using Text Search
        search_url = "https://maps.googleapis.com/maps/api/place/textsearch/json"
        search_params = {
            "query": f"{hotel_name} {city}",
            "key": api_key
        }
        
        search_response = requests.get(search_url, params=search_params, timeout=10)
        search_data = search_response.json()
        
        print(f" Google Places API Response Status: {search_data.get('status')}")
        
        if search_data.get("status") != "OK" or not search_data.get("results"):
            print(f" No results found for {hotel_name}")
            return {
                "hotel_name": hotel_name,
                "city": city,
                "map_link": f"https://www.google.com/maps/search/{hotel_name.replace(' ', '+')}+{city.replace(' ', '+')}",
                "images": [],
                "address": "Hotel not found in Google Places",
                "coordinates": None,
                "message": f"Could not find exact match for '{hotel_name}' in Google Places. Try the Google Maps link above."
            }
        
        # Get the first result
        place = search_data["results"][0]
        place_id = place.get("place_id")
        
        print(f" Found place_id: {place_id}")
        
        # Get place details including photos
        details_url = "https://maps.googleapis.com/maps/api/place/details/json"
        details_params = {
            "place_id": place_id,
            "fields": "name,formatted_address,geometry,photos,rating,url",
            "key": api_key
        }
        
        details_response = requests.get(details_url, params=details_params, timeout=10)
        details_data = details_response.json()
        
        if details_data.get("status") != "OK":
            print(f" Details fetch failed: {details_data.get('status')}")
            raise Exception("Could not fetch place details")
        
        result = details_data.get("result", {})
        
        # Extract photos
        photo_urls = []
        if result.get("photos"):
            print(f" Found {len(result['photos'])} photos")
            for photo in result["photos"][:5]:  # Get up to 5 photos
                photo_reference = photo.get("photo_reference")
                if photo_reference:
                    # Generate photo URL
                    photo_url = f"https://maps.googleapis.com/maps/api/place/photo?maxwidth=800&photoreference={photo_reference}&key={api_key}"
                    photo_urls.append(photo_url)
        else:
            print("⚠️ No photos found for this hotel")
        
        # Extract location data
        geometry = result.get("geometry", {}).get("location", {})
        
        response_data = {
            "hotel_name": result.get("name", hotel_name),
            "city": city,
            "address": result.get("formatted_address", "Address not available"),
            "coordinates": {
                "latitude": geometry.get("lat"),
                "longitude": geometry.get("lng")
            } if geometry else None,
            "map_link": result.get("url", f"https://www.google.com/maps/search/?api=1&query={hotel_name.replace(' ', '+')}+{city.replace(' ', '+')}"),
            "images": photo_urls,
            "rating": result.get("rating"),
            "total_images": len(photo_urls),
            "message": f"✅ Found {len(photo_urls)} images from Google Places API"
        }
        
        print(f"✅ Successfully fetched data with {len(photo_urls)} images")
        return response_data
        
    except Exception as e:
        print(f"❌ Error fetching data: {str(e)}")
        return {
            "hotel_name": hotel_name,
            "city": city,
            "error": str(e),
            "map_link": f"https://www.google.com/maps/search/{hotel_name.replace(' ', '+')}+{city.replace(' ', '+')}",
            "images": [],
            "address": "Error fetching location data",
            "message": f"Error: {str(e)}. Please use the Google Maps link above."
        }

def get_hotel_images_by_search(search_query: str, num_images: int = 5) -> Dict[str, Any]:
    """
    Search for hotel images using Google Places API.
    Returns ONLY Google Places API photo URLs.
    
    Args:
        search_query: Search query (e.g., "luxury hotels Mumbai")
        num_images: Number of images to return (default 5)
        
    Returns:
        Dict with list of Google Places photo URLs
    """
    api_key = os.getenv('GOOGLE_PLACES_API_KEY')
    
    if not api_key:
        return {
            "query": search_query,
            "error": "Google Places API key not configured",
            "images": [],
            "message": "Please configure GOOGLE_PLACES_API_KEY in .env file"
        }
    
    print(f"🔍 Searching for images: {search_query}")
    
    try:
        # Search for places
        search_url = "https://maps.googleapis.com/maps/api/place/textsearch/json"
        search_params = {
            "query": search_query,
            "key": api_key
        }
        
        response = requests.get(search_url, params=search_params, timeout=10)
        data = response.json()
        
        if data.get("status") != "OK" or not data.get("results"):
            return {
                "query": search_query,
                "images": [],
                "message": f"No results found for '{search_query}'"
            }
        
        # Collect photo URLs from multiple places
        all_photo_urls = []
        for place in data["results"][:3]:  # Get photos from top 3 results
            if place.get("photos"):
                for photo in place["photos"]:
                    photo_reference = photo.get("photo_reference")
                    if photo_reference:
                        photo_url = f"https://maps.googleapis.com/maps/api/place/photo?maxwidth=800&photoreference={photo_reference}&key={api_key}"
                        all_photo_urls.append(photo_url)
                        if len(all_photo_urls) >= num_images:
                            break
            if len(all_photo_urls) >= num_images:
                break
        
        print(f"✅ Found {len(all_photo_urls)} images")
        
        return {
            "query": search_query,
            "images": all_photo_urls[:num_images],
            "total_found": len(all_photo_urls),
            "message": f"✅ Found {len(all_photo_urls)} images from Google Places API"
        }
        
    except Exception as e:
        print(f"❌ Error: {str(e)}")
        return {
            "query": search_query,
            "error": str(e),
            "images": [],
            "message": f"Error searching for images: {str(e)}"
        }