# Destination Auto-Recommendation System Explained (BLR/Bangalore Example)

## 🎯 Overview
When you type "Bangalore" or "BLR" in the destination preferences screen, the app performs an intelligent 3-step process using **AI (Gemini)**, **Google Places API**, and **local CSV data** to recommend travel interests automatically.

---

## 📱 Frontend Flow (Flutter)

### Step 1: User Types City Name
**File:** `flutter_travel_app/lib/screens/destination_preferences_screen.dart`

```dart
// User types "bangalore" in the search field
_updateSuggestions(String query) {
  _suggestionDebounce?.cancel();
  _suggestionDebounce = Timer(
    const Duration(milliseconds: 250),  // Wait 250ms to avoid too many API calls
    () => _loadSuggestions(query),
  );
}
```

**Why debounce?** Prevents spamming the backend API while the user is still typing.

---

### Step 2: Get City Suggestions (Auto-Complete)
**Makes request:** `GET /api/destination/suggestions?query=bangalore&limit=8`

```dart
Future<void> _loadSuggestions(String query) async {
  final suggestions = await _adkService.getDestinationSuggestions(
    query: query,
    limit: 8,  // Show max 8 suggestions
  );
  
  // Display dropdown list of matching cities
  setState(() {
    _filteredSuggestions = suggestions;  // e.g., ["Bangalore, India", "Bangalore, USA"]
    _showSuggestions = suggestions.isNotEmpty;
  });
}
```

**What the user sees:** Dropdown of matching cities with country names

```
🔍 Search: "bangl..."
━━━━━━━━━━━━━━━━━━━━━━━
✓ Bangalore, India (most popular)
✓ Bangalore, USA (less common)
```

---

### Step 3: User Selects a Suggestion
**File:** `destination_preferences_screen.dart` line 73-88

```dart
Future<void> _selectSuggestion(Map<String, String> suggestion) async {
  final city = suggestion['city'] ?? '';  // "Bangalore"
  final country = suggestion['country'] ?? '';  // "India"
  final formatted = country.isEmpty ? city : '$city, $country';
  
  // Fill the text field
  _searchController.text = formatted;  // Now shows "Bangalore, India"
  
  // Hide dropdown
  _showSuggestions = false;
  
  // Fetch AI-generated interests for this city
  await _fetchCityInterests();
}
```

---

### Step 4: Fetch City Interests (AI Recommendations)

```dart
Future<void> _fetchCityInterests() async {
  final city = _searchController.text.trim();  // "Bangalore, India"
  
  // Step 4a: Check if this city name is ambiguous
  final disambResult = await _adkService.disambiguateCity(city: city);
  
  if (disambResult['ambiguous'] == true) {
    // Show dialog: "Did you mean Cambridge (UK) or Cambridge (USA)?"
    final picked = await _showDisambiguationDialog(city, options);
    if (picked == null) return;  // User cancelled
    resolvedCity = picked;
  }
  
  // Step 4b: Get AI-generated interests/activities for resolved city
  final result = await _adkService.getDestinationInterests(city: resolvedCity);
  
  setState(() {
    _aiCategories = result['categories'];  // ["Nature & Parks", "Heritage", "Food & Drink", ...]
    _loadedCity = resolvedCity;
  });
}
```

---

## 🖥️ Backend Flow (Python/FastAPI)

### Backend Endpoint 1: Get Suggestions
**File:** `7-multi-agent/ultra_simple_server.py` line 3969

```python
@app.get("/api/destination/suggestions")
def get_destination_suggestions(query: str, limit: int = 8):
    """Destination autocomplete suggestions using Google Places with CSV fallback."""
    
    # Example: query="bangl", limit=8
    suggestions = []
    
    # 🥇 PRIMARY: Google Places Autocomplete API (real-time, global)
    if GOOGLE_PLACES_API_KEY:
        response = requests.post(
            "https://places.googleapis.com/v1/places:autocomplete",
            headers=_google_headers(field_mask),
            json={
                "input": "bangl",
                "includedPrimaryTypes": ["(cities)"],  # Only return cities
            },
            timeout=2,
        )
        # Returns: ["Bangalore, India", "Bangalore, USA", "Banglamung, Thailand", ...]
    
    # 🥈 FALLBACK: Local CSV (when Google Places is slow/unavailable)
    if not suggestions:
        filtered = destinations_df[
            destinations_df['city'].str.lower().str.contains('bangl')
        ]
        for _, row in filtered.iterrows():
            suggestions.append({
                'city': row['city'],        # "Bangalore"
                'country': row['country'],  # "India"
                'description': row.get('description', ''),
                'famous_for': row.get('famous_for', ''),
            })
    
    return {
        'status': 'success',
        'suggestions': suggestions[:limit]
    }
```

**Response Example:**
```json
{
  "status": "success",
  "suggestions": [
    {
      "city": "Bangalore",
      "country": "India",
      "description": "Garden City",
      "famous_for": "IT Hub, Coffee, Tech"
    },
    {
      "city": "Bangalore",
      "country": "USA",
      "description": "Small town",
      "famous_for": ""
    }
  ]
}
```

---

### Backend Endpoint 2: Disambiguate City
**File:** `7-multi-agent/ultra_simple_server.py` line 3908

```python
@app.post("/api/destination/disambiguate")
def disambiguate_city(request: dict):
    """Check if a city name is ambiguous and return options if so."""
    
    city = request.get("city", "").strip()  # "Bangalore, India"
    
    # 🤖 Use Gemini AI to check ambiguity
    prompt = f"""You are a geography expert. Is "{city}" ambiguous?
    
    Return JSON:
    {{
      "ambiguous": true/false,
      "options": [
        {{
          "name": "Bangalore, Karnataka, India",
          "description": "Garden City, IT Hub"
        }}
      ]
    }}
    """
    
    model = genai.GenerativeModel("gemini-2.5-flash")
    response = model.generate_content(prompt)
    result = json.loads(response.text)
    
    return {
        "status": "success",
        "ambiguous": result['ambiguous'],  # Usually False for "Bangalore, India"
        "options": result['options']
    }
```

**Why AI?** Because Gemini knows:
- ✅ Cambridge = ambiguous (UK vs USA vs Canada)
- ✅ Bangalore = NOT ambiguous (when state/country provided)
- ✅ Hyderabad = ambiguous (Pakistan vs India)

---

### Backend Endpoint 3: Get AI-Generated Interests ⭐ **THIS IS THE MAGIC**
**File:** `7-multi-agent/ultra_simple_server.py` line 3811

```python
@app.post("/api/destination/interests")
def get_destination_interests(request: dict):
    """Get AI-generated city-specific interests and activities."""
    
    city = request.get("city", "").strip()  # "Bangalore"
    
    print(f"🏙️ Generating interests for: {city}")
    
    # 🤖 Gemini AI generates relevant travel categories for THIS CITY
    prompt = f"""You are a travel expert. For "{city}" in India, generate relevant interest categories.
    
    Return JSON:
    {{
      "categories": [
        {{
          "id": "nature_parks",
          "title": "Nature & Parks",
          "icon": "park",
          "activities": ["Lake", "Garden", "Park", "Hill Station", "Wildlife", "Nature Trail"]
        }},
        {{
          "id": "heritage",
          "title": "Heritage",
          "icon": "museum",
          "activities": ["Palace", "Fort", "Museum", "Monument", "Heritage Walk"]
        }},
        {{
          "id": "food_drink",
          "title": "Food & Drink",
          "icon": "restaurant",
          "activities": ["Street Food", "Cafe", "Brewery", "Fine Dining", "Local Cuisine"]
        }}
      ]
    }}
    
    RULES:
    - Generate 6-8 categories relevant to {city}
    - Do NOT use "Beach" or "Water Sports" for inland cities
    - Each category should have 4-8 short generic tags
    - icon_name must be one of: terrain, museum, park, restaurant, temple_hindu, nightlife, etc.
    """
    
    model = genai.GenerativeModel("gemini-2.5-flash")
    response = model.generate_content(prompt)
    result = json.loads(response.text)
    
    return {
        "status": "success",
        "city": city,
        "categories": result['categories']
    }
```

**Why Gemini AI?**
- **Smart:** Knows Bangalore should show "Nature & Parks" (lakes, gardens) NOT "Beaches"
- **Contextual:** Different for coastal cities (Goa → "Beaches", "Nightlife") vs hills (Shimla → "Trekking", "Adventure")
- **Customizable:** Can prompt-inject to avoid clichés and include local specialties
- **Fast:** Returns results in <2 seconds

---

## 📊 Example: Complete Flow for "Bangalore"

```
USER INPUT
    ↓
"b" → "ba" → "ban" → "bang" → "bangal" → "bangalo" → "bangalore"
    ↓ (debounce 250ms)
[FRONTEND] _loadSuggestions("bangalore")
    ↓
[API] GET /api/destination/suggestions?query=bangalore
    ↓
[BACKEND - Google Places]
    Input: "bangalore"
    Output: ["Bangalore, India", "Bangalore, USA", ...]
    ↓
[FRONTEND] Display dropdown ✓
    User clicks "Bangalore, India"
    ↓
[FRONTEND] _selectSuggestion()
    ↓
[FRONTEND] _fetchCityInterests()
    ↓
[API] POST /api/destination/disambiguate
    {city: "Bangalore, India"}
    ↓
[BACKEND - Gemini AI]
    Prompt: "Is 'Bangalore, India' ambiguous?"
    Response: {ambiguous: false, options: [{name: "Bangalore", description: "..."}]}
    ↓
[API] POST /api/destination/interests
    {city: "Bangalore, India"}
    ↓
[BACKEND - Gemini AI - THIS IS THE MAIN AI CALL]
    Prompt: "For Bangalore, generate 6-8 relevant interest categories"
    Response: {categories: [
        {title: "Nature & Parks", activities: ["Lake", "Garden", ...]},
        {title: "Heritage", activities: ["Palace", "Fort", ...]},
        {title: "Food & Drink", activities: ["Street Food", "Cafe", ...]},
        {title: "Temples & Spiritual", activities: ["Temple", "Ashram", ...]},
        {title: "Modern Shopping", activities: ["Mall", "Boutique", ...]},
        {title: "Nightlife", activities: ["Pub", "Club", "Live Music"]},
        ...
    ]}
    ↓
[FRONTEND] setState({_aiCategories = categories})
    ↓
USER SEES
    Interest cards with icons:
    🏞️ Nature & Parks        👻 Heritage
       Lake, Garden, Park       Palace, Fort, Museum
    
    🍽️ Food & Drink         🏛️ Temples & Spiritual
       Street Food, Cafe        Temple, Ashram
    
    🛍️ Modern Shopping      🌙 Nightlife
       Mall, Boutique           Pub, Club, Live Music
    
    (User can select which ones they're interested in)
```

---

## 🔑 Key Insights

### 1. **Smart CSV Fallback**
- Primary: Google Places API (real-time, global)
- Secondary: Local CSV (for offline or failed requests)
- CSV has pre-loaded data for Indian cities

### 2. **Why Different Cities Get Different Interests**

**Bangalore (Inland City):**
```json
{
  "categories": [
    {"title": "Nature & Parks", "icon": "park"},
    {"title": "Heritage", "icon": "museum"},
    {"title": "Food & Drink", "icon": "restaurant"}
  ]
}
```

**Goa (Coastal City):**
```json
{
  "categories": [
    {"title": "Beaches", "icon": "terrain"},
    {"title": "Water Sports", "icon": "sports"},
    {"title": "Nightlife", "icon": "nightlife"}
  ]
}
```

The prompt explicitly says:
> "Do NOT use 'Beach' or 'Water Sports' for inland cities like Bangalore, Delhi, etc."

### 3. **Real-time AI Generation**
- Not hardcoded! Every city gets fresh interests from Gemini
- Prompts are engineered to avoid clichés
- Response time: ~1-2 seconds per city

### 4. **User Selection Tracking**
```dart
final Set<String> _selectedActivities = {};

// User taps "Lake" under "Nature & Parks"
_selectedActivities.add("Lake");

// User taps "Coffee" under "Food & Drink"  
_selectedActivities.add("Coffee");

// Later saved to user preferences for personalized recommendations
```

---

## 🚀 Technology Stack

| Component | Technology | Purpose |
|-----------|-----------|---------|
| **Frontend** | Flutter (Dart) | Mobile UI |
| **API Calls** | HTTP/REST | Communication |
| **Suggestions** | Google Places API | Real-time city autocomplete |
| **AI/Recommendations** | Google Gemini 2.5 Flash | Smart interest generation |
| **Backend** | FastAPI (Python) | REST API server |
| **Fallback Data** | CSV (destinations_india.csv) | Offline city database |

---

## 💾 Data Flow

```
CSV File (destinations_india.csv)
    ↓ (loaded on startup)
    → destinations_df (pandas DataFrame)
    ↓ (when Google Places fails)
    → /api/destination/suggestions (fallback)

User Selection (e.g., "Lake", "Coffee", "Museum")
    ↓ (saved to state)
    → _selectedActivities (Set)
    ↓ (sent to backend on form submit)
    → user_preferences.destination_interests
    ↓ (used for personalized travel recommendations)
    → AI recommendations consider user interests
```

---

## 🎓 Summary

**For "Bangalore" Auto-Recommendation:**

1. **User types** → `_updateSuggestions()` debounces input
2. **Gets suggestions** → `GET /api/destination/suggestions` (Google Places or CSV)
3. **User selects** → `_selectSuggestion()` fills text field
4. **Disambiguates** → `POST /api/destination/disambiguate` (Gemini checks if ambiguous)
5. **Fetches interests** → `POST /api/destination/interests` (✨ **Gemini generates 6-8 smart categories**)
6. **Shows UI** → Interest cards appear (Nature, Heritage, Food, Temples, Shopping, Nightlife, etc.)
7. **User selects interests** → Saved to preferences for personalized travel planning

All powered by **Google Gemini 2.5 Flash** AI + **Google Places API** + **Local CSV fallback** ✨

