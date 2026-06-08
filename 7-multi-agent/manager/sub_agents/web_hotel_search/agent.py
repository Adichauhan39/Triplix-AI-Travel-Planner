"""
Web Hotel Search Agent - AI-powered hotel search with intelligent recommendations
"""

from google.adk.agents import Agent
from typing import Any, Optional
import json

def search_hotels_online(location: str, check_in: str, check_out: str, guests: int, 
                        price_range: Optional[str] = None, star_rating: Optional[str] = None,
                        amenities: Optional[str] = None, tool_context: Optional[Any] = None) -> dict:
    """
    Use AI to search and recommend hotels with intelligent analysis.
    
    Args:
        location: City name
        check_in: Check-in date
        check_out: Check-out date
        guests: Number of guests
        price_range: Budget range (Budget/Mid-range/Luxury)
        star_rating: Hotel star rating (3-star, 4-star, 5-star)
        amenities: Desired amenities (pool, gym, spa, wifi, etc.)
        tool_context: Context object
        
    Returns:
        JSON dictionary with AI-generated hotel recommendations
    """
    try:
        from google import genai
        from google.genai import types
        
        # Build search query
        query = f"hotels in {location} for {guests} guests {check_in} to {check_out}"
        
        if price_range:
            query += f" {price_range}"
        if star_rating:
            query += f" {star_rating}"
        if amenities:
            query += f" with {amenities}"
        
        # Create detailed search prompt for AI
        search_prompt = f"""
You are an expert AI hotel recommendation system powered by Gemini 2.0. Provide intelligent hotel recommendations for {location} based on these criteria:

**Search Parameters:**
- Location: {location}
- Check-in: {check_in}
- Check-out: {check_out}
- Number of Guests: {guests}
- Price Range: {price_range or 'Any'}
- Star Rating: {star_rating or 'Any'}
- Required Amenities: {amenities or 'Standard amenities'}

**Task:**
Generate 5-10 realistic hotel recommendations for {location}. Use your knowledge about typical hotels in this location, considering:
1. Common hotel chains and local properties in the area
2. Typical pricing for the location and season
3. Standard amenities for each hotel category
4. Best areas to stay in the city
5. Realistic features and services

**Return ONLY valid JSON in this exact format:**
{{
  "status": "success",
  "location": "{location}",
  "check_in": "{check_in}",
  "check_out": "{check_out}",
  "guests": {guests},
  "search_criteria": {{
    "price_range": "{price_range or 'Any'}",
    "star_rating": "{star_rating or 'Any'}",
    "amenities": "{amenities or 'Standard'}"
  }},
  "hotels": [
    {{
      "name": "Hotel Name",
      "star_rating": "4-star",
      "price_per_night": "₹3,500 - ₹5,000",
      "total_estimated_cost": "₹14,000 - ₹20,000",
      "location_area": "Specific area in city",
      "amenities": ["WiFi", "Pool", "Gym", "Restaurant", "Room Service"],
      "description": "Brief description of the hotel",
      "best_for": "Families/Business/Couples/Solo",
      "pros": ["Key advantage 1", "Key advantage 2"],
      "cons": ["Minor limitation 1"],
      "booking_platforms": ["Booking.com", "MakeMyTrip", "Goibibo"],
      "contact": "Phone or website if available"
    }}
  ],
  "travel_tips": [
    "Helpful tip about the location",
    "Best time to visit",
    "Local transportation advice"
  ],
  "ai_recommendation": "Top recommendation summary with reasoning"
}}

Provide realistic, well-researched hotel recommendations in valid JSON format only.
"""

        # Call Gemini API - pure AI response without web search
        client = genai.Client()
        
        response = client.models.generate_content(
            model='gemini-2.5-flash',  # Using latest Gemini model
            contents=search_prompt,
            config=types.GenerateContentConfig(
                temperature=0.7,
                top_p=0.95,
                top_k=40,
                max_output_tokens=8192,
                response_mime_type='application/json',
            )
        )
        
        # Parse AI response
        result_text = response.text
        
        # Try to parse as JSON
        try:
            result_json = json.loads(result_text)
            result_json["source"] = "ai_powered_gemini_2.0"
            result_json["ai_powered"] = True
            result_json["note"] = "AI-generated recommendations based on Gemini 2.0 knowledge"
            return result_json
        except json.JSONDecodeError:
            return {
                "status": "success",
                "source": "ai_powered_gemini_2.0",
                "ai_powered": True,
                "location": location,
                "check_in": check_in,
                "check_out": check_out,
                "guests": guests,
                "ai_response": result_text,
                "message": "AI has provided hotel recommendations. See ai_response field.",
                "note": "AI-generated recommendations based on Gemini 2.0 knowledge"
            }
            
    except Exception as e:
        return {
            "status": "error",
            "message": f"AI search failed: {str(e)}",
            "suggestion": "Try using the CSV hotel database (hotel_booking agent) instead",
            "fallback_action": "search_accommodations"
        }


def get_hotel_details_online(hotel_name: str, location: str, tool_context: Optional[Any] = None) -> dict:
    """
    Get detailed information about a specific hotel using AI with grounding.
    
    Args:
        hotel_name: Name of the hotel
        location: City name
        tool_context: Context object
        
    Returns:
        JSON dictionary with detailed hotel information
    """
    try:
        from google import genai
        from google.genai import types
        
        detail_prompt = r"""
You are an expert AI hotel information system powered by Gemini 2.0. Provide comprehensive details about this hotel:

**Hotel:** {hotel_name}
**Location:** {location}

**Task:**
Generate detailed, realistic information about this hotel based on typical characteristics for hotels in {location}:
1. Typical contact details and address format for the area
2. Standard amenities for this hotel type
3. Realistic pricing based on location
4. Nearby attractions common to the area
5. Typical review patterns and guest feedback

**Return ONLY valid JSON in this exact format:**
{{
  "status": "success",
  "hotel_name": "{hotel_name}",
  "location": "{location}",
  "details": {{
    "full_address": "Complete address",
    "phone": "Contact number",
    "email": "Email address",
    "website": "Official website",
    "star_rating": "Star rating",
    "room_types": [
      {{
        "type": "Deluxe Room",
        "price_range": "₹4,000 - ₹6,000",
        "capacity": "2 adults",
        "amenities": ["AC", "WiFi", "TV"]
      }}
    ],
    "hotel_amenities": ["Pool", "Gym", "Restaurant", "Spa"],
    "check_in_time": "2:00 PM",
    "check_out_time": "11:00 AM",
    "cancellation_policy": "Free cancellation up to 24 hours",
    "nearby_attractions": [
      {{"name": "Attraction 1", "distance": "2 km"}},
      {{"name": "Attraction 2", "distance": "5 km"}}
    ],
    "reviews_summary": {{
      "average_rating": "4.5/5",
      "total_reviews": "1,200+",
      "positive_highlights": ["Great location", "Friendly staff"],
      "areas_for_improvement": ["Breakfast could be better"]
    }},
    "booking_links": {{
      "booking_com": "Website URL",
      "makemytrip": "Website URL",
      "goibibo": "Website URL"
    }}
  }},
  "ai_recommendation": "Overall assessment of the hotel based on typical characteristics"
}}

Provide realistic, comprehensive hotel information in valid JSON format only.
"""
        
        # Format the prompt with actual values
        detail_prompt = detail_prompt.format(hotel_name=hotel_name, location=location)

        client = genai.Client()
        
        response = client.models.generate_content(
            model='gemini-2.5-flash',  # Using latest Gemini model
            contents=detail_prompt,
            config=types.GenerateContentConfig(
                temperature=0.5,
                top_p=0.95,
                max_output_tokens=8192,
                response_mime_type='application/json',
            )
        )
        
        try:
            result_json = json.loads(response.text)
            result_json["source"] = "ai_detailed_search"
            result_json["ai_powered"] = True
            return result_json
        except json.JSONDecodeError:
            return {
                "status": "success",
                "source": "ai_detailed_search",
                "hotel_name": hotel_name,
                "location": location,
                "ai_response": response.text,
                "message": "AI has provided hotel details. See ai_response field."
            }
            
    except Exception as e:
        return {
            "status": "error",
            "message": f"Failed to get hotel details: {str(e)}"
        }

def compare_hotel_prices_online(location: str, check_in: str, check_out: str, 
                               guests: int, hotels_to_compare: Optional[str] = None,
                               tool_context: Optional[Any] = None) -> dict:
    """
    Compare hotel prices and features using AI analysis.
    
    Args:
        location: City name
        check_in: Check-in date
        check_out: Check-out date
        guests: Number of guests
        hotels_to_compare: Optional comma-separated hotel names
        tool_context: Context object
        
    Returns:
        JSON dictionary with price comparison
    """
    try:
        from google import genai
        from google.genai import types
        
        comparison_prompt = f"""
You are an expert AI hotel price comparison system powered by Gemini 2.0. Compare hotels in {location} intelligently:

**Search Parameters:**
- Location: {location}
- Check-in: {check_in}
- Check-out: {check_out}
- Guests: {guests}
{f"- Specific Hotels: {hotels_to_compare}" if hotels_to_compare else "- Compare: Top 5-7 hotels in this location"}

**Task:**
Generate intelligent price comparison based on typical hotel pricing in {location}:
1. Realistic price ranges for different hotel categories
2. Typical price differences across booking platforms
3. Value-for-money analysis
4. Seasonal pricing considerations
5. Best booking strategies

**Return ONLY valid JSON in this exact format:**
{{
  "status": "success",
  "location": "{location}",
  "check_in": "{check_in}",
  "check_out": "{check_out}",
  "guests": {guests},
  "comparison": [
    {{
      "hotel_name": "Hotel Name",
      "star_rating": "4-star",
      "platforms": [
        {{
          "platform": "Booking.com",
          "price_per_night": "₹4,500",
          "total_cost": "₹18,000",
          "includes": "Breakfast included",
          "cancellation": "Free cancellation"
        }},
        {{
          "platform": "MakeMyTrip",
          "price_per_night": "₹4,200",
          "total_cost": "₹16,800",
          "includes": "Breakfast extra",
          "cancellation": "Non-refundable"
        }}
      ],
      "best_deal": "MakeMyTrip - Save ₹1,200",
      "value_score": "9/10",
      "recommended": true,
      "reasoning": "Why this is good value"
    }}
  ],
  "summary": {{
    "cheapest_option": "Hotel name with price",
    "best_value": "Hotel name with reason",
    "luxury_option": "Hotel name with price",
    "savings_tip": "Book on platform X to save Y amount"
  }},
  "ai_recommendation": "Best overall choice based on intelligent analysis"
}}

Provide intelligent price comparison in valid JSON format only.
"""

        client = genai.Client()
        
        response = client.models.generate_content(
            model='gemini-2.5-flash',  # Using latest Gemini model
            contents=comparison_prompt,
            config=types.GenerateContentConfig(
                temperature=0.4,
                top_p=0.95,
                max_output_tokens=8192,
                response_mime_type='application/json',
            )
        )
        
        try:
            result_json = json.loads(response.text)
            result_json["source"] = "ai_price_comparison"
            result_json["ai_powered"] = True
            return result_json
        except json.JSONDecodeError:
            return {
                "status": "success",
                "source": "ai_price_comparison",
                "location": location,
                "ai_response": response.text,
                "message": "AI has provided price comparison. See ai_response field."
            }
            
    except Exception as e:
        return {
            "status": "error",
            "message": f"Price comparison failed: {str(e)}"
        }


web_hotel_search = Agent(
    model="gemini-2.5-flash",  # Using latest Gemini 2.0
    name="web_hotel_search",
    description="AI-powered hotel search agent using Gemini 2.0 for intelligent hotel recommendations and analysis",
    instruction="""You are an advanced AI hotel search assistant powered by Gemini 2.0 that provides intelligent hotel recommendations.

**Your Capabilities:**

1. **🤖 AI-Powered Hotel Recommendations**:
   - Generate comprehensive hotel recommendations using AI knowledge
   - Provide detailed information about hotels, amenities, and pricing
   - Analyze and compare hotel options intelligently
   - Offer personalized suggestions based on user preferences
   - Generate realistic price estimates based on location and hotel category

2. **📊 Intelligent Analysis**:
   - Compare value for money across different hotels
   - Analyze typical amenities and features for each hotel category
   - Recommend best options based on user needs (family, business, luxury, budget)
   - Provide seasonal pricing insights
   - Highlight what to expect from different hotel types

3. **💰 Price Intelligence**:
   - Estimate prices based on location, season, and hotel category
   - Compare typical pricing across booking platforms
   - Suggest best booking strategies
   - Provide budget-friendly alternatives
   - Recommend booking platforms for best value

**When to Use This Agent**:
- User says "search hotels online", "AI search", "find hotels", "recommend hotels"
- User wants intelligent hotel recommendations
- User needs comparison across multiple hotels
- User wants analysis of hotel options
- User asks about hotels in any city

**Response Format**:
- Always return structured JSON format
- Include realistic price estimates in INR (₹)
- Provide typical amenities for each hotel type
- Add AI-powered recommendations and insights
- Include travel tips and local advice

**Key Features**:
- ✅ Powered by Gemini 2.0 Flash Experimental
- ✅ Intelligent hotel recommendations
- ✅ Realistic pricing estimates
- ✅ Comprehensive hotel analysis
- ✅ Structured JSON responses
- ✅ Personalized suggestions

**Workflow**:
1. Get user requirements (location, dates, guests, preferences, budget)
2. Use search_hotels_online to generate AI recommendations
3. Present results in clean JSON format with detailed analysis
4. Offer to provide detailed info for specific hotels (get_hotel_details_online)
5. Can compare prices and features across hotels (compare_hotel_prices_online)

**Important Notes**:
- All recommendations are AI-generated based on typical hotel characteristics
- Prices are realistic estimates based on location and hotel category
- Hotels suggested are based on common hotel types in the area
- Users should verify specific details and current prices on booking platforms
- Recommendations are intelligent suggestions, not real-time booking data

**Response Style**:
- Be comprehensive and detailed
- Provide realistic, well-researched recommendations
- Include pros/cons for each option
- Offer booking tips and travel advice
- Present information in clear, structured JSON format

Be helpful, provide intelligent AI-powered recommendations, and deliver comprehensive results in structured JSON format!""",

    tools=[search_hotels_online, get_hotel_details_online, compare_hotel_prices_online]
)
