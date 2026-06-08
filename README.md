# ✈️ Triplix — Personalized Trip Planner with AI

> **One app. One conversation. Your entire trip — planned.**

> 🏆 Built for the [**Google Cloud Rapid Agent Hackathon**](https://rapid-agent.devpost.com/)

[![Google Cloud Rapid Agent Hackathon](https://img.shields.io/badge/Google%20Cloud-Rapid%20Agent%20Hackathon-4285F4?style=for-the-badge&logo=google-cloud&logoColor=white)](https://rapid-agent.devpost.com/)

![Flutter](https://img.shields.io/badge/Flutter-02569B?style=for-the-badge&logo=flutter&logoColor=white)
![Python](https://img.shields.io/badge/Python-3776AB?style=for-the-badge&logo=python&logoColor=white)
![FastAPI](https://img.shields.io/badge/FastAPI-009688?style=for-the-badge&logo=fastapi&logoColor=white)
![Gemini](https://img.shields.io/badge/Gemini%202.5%20Flash-EA4335?style=for-the-badge&logo=google&logoColor=white)
![Google ADK](https://img.shields.io/badge/Google%20ADK-34A853?style=for-the-badge&logo=google&logoColor=white)
![Cloud Run](https://img.shields.io/badge/Cloud%20Run-4285F4?style=for-the-badge&logo=google-cloud&logoColor=white)

---

## 🌐 Live Demo

| Component | URL |
|-----------|-----|
| **🚀 App** | [triplix-web-1026563611026.us-central1.run.app](https://triplix-web-1026563611026.us-central1.run.app) |
| **⚙️ API** | [triplix-server-1026563611026.us-central1.run.app](https://triplix-server-1026563611026.us-central1.run.app) |
| **📖 API Docs** | [Swagger UI](https://triplix-server-1026563611026.us-central1.run.app/docs) |

---

## 🎯 Problem Statement

Planning a trip in India means hours of research — browsing hotels on MakeMyTrip, checking flights on Google, tracking budgets on spreadsheets, and building itineraries manually. Travelers switch between 5-10 apps just to plan one vacation.

## 💡 Solution

**Triplix** uses **8 specialized Google ADK AI agents** powered by **Gemini 2.5 Flash** to plan your entire trip through a single conversation. Just say *"Plan a 3-day Goa trip for 2 people under ₹20,000"* and get hotels, flights, itineraries, and budget breakdowns instantly.

---

## ✨ Key Features

### 🤖 Multi-Agent AI Architecture (Google ADK)
8 specialized agents working together via Google Agent Development Kit:

| Agent | Purpose |
|-------|---------|
| **Hotel Booking** | Search & book hotels with real Google Places photos |
| **Travel Booking** | Flights, trains, buses, taxis with live pricing |
| **Destination Info** | City information, attractions, local tips |
| **Budget Tracker** | Auto-allocate & track expenses by category |
| **Swipe Recommendations** | AI-curated cards for discovery |
| **Itinerary Planner** | Day-by-day plans with timings & costs |
| **Web Hotel Search** | Real-time prices from booking platforms |
| **Checkpoint Analyzer** | Trip progress & preference learning |

### 👆 Swipe-to-Discover (Tinder for Travel)
- Swipe right to like hotels, destinations, attractions
- Swipe right on 2 items → **Compare side-by-side** or **Book both**
- Real hotel photos via Google Places API
- AI learns your preferences with every swipe

### 💬 Natural Language Chat
- Type or speak: *"Find me a beach resort in Goa under ₹5000"*
- Voice input with Speech-to-Text
- Context-aware multi-turn conversations

### 💰 Smart Budget Manager
- Set budget → AI auto-allocates across categories
- Type *"spent 2000 on hotel"* → auto-logs with category detection
- Real-time expense tracking with visual cards
- Per-person cost splitting for group travel

### 📋 AI Itinerary Generator
- Complete day-by-day plans with timings
- Restaurant recommendations, travel tips
- Share via QR code or text

### 📸 Trip Reel Creator
- Capture photos during your trip
- AI analyzes quality & composition
- Auto-generates shareable travel reels

---

## 🏗️ Architecture

```
┌─────────────────────────────────────────────────────┐
│                    Flutter Web App                    │
│               (Cloud Run + Nginx)                    │
└──────────────────────┬──────────────────────────────┘
                       │ REST API (HTTPS)
┌──────────────────────▼──────────────────────────────┐
│                  FastAPI Backend                      │
│               (Cloud Run + Docker)                   │
│                                                      │
│  ┌─────────────────────────────────────────────┐    │
│  │         Root Agent (Manager)                 │    │
│  │          Google ADK + Gemini 2.5 Flash       │    │
│  ├─────────┬──────────┬──────────┬─────────────┤    │
│  │ Hotel   │ Travel   │ Dest.   │ Budget      │    │
│  │ Booking │ Booking  │ Info    │ Tracker     │    │
│  ├─────────┼──────────┼──────────┼─────────────┤    │
│  │ Swipe   │Itinerary │Web Hotel│ Checkpoint  │    │
│  │ Recs    │ Planner  │ Search  │ Analyzer    │    │
│  └─────────┴──────────┴──────────┴─────────────┘    │
│                                                      │
│  ┌──────────┐  ┌──────────┐  ┌──────────────────┐  │
│  │ CSV Data │  │ MongoDB  │  │ Google APIs       │  │
│  │ (Hotels, │  │ Atlas    │  │ Places, Maps,     │  │
│  │ Flights) │  │          │  │ Vertex AI         │  │
│  └──────────┘  └──────────┘  └──────────────────┘  │
└─────────────────────────────────────────────────────┘
```

---

## 🛠️ Tech Stack

### Google Cloud Products
- **Google Gemini 2.5 Flash** — Core AI model for all agents
- **Google ADK** — Agent Development Kit for multi-agent orchestration
- **Google Vertex AI** — Model hosting and inference
- **Google Cloud Run** — Serverless hosting (frontend + backend)
- **Google Cloud Build** — CI/CD container builds
- **Google Artifact Registry** — Docker image storage
- **Google Cloud Storage** — Static asset hosting
- **Google Places API** — Real hotel/destination photos
- **Google Maps API** — Directions, distances, nearby places

### Other Technologies
- **Flutter** — Cross-platform frontend (Web, Android, iOS)
- **FastAPI** — Python backend framework
- **MongoDB Atlas** — Document database (optional)
- **Docker** — Containerization
- **Nginx** — Web server for frontend

---

## 🚀 Getting Started

### Prerequisites
- Python 3.11+
- Flutter 3.x
- Google Cloud SDK (`gcloud`)
- Google Cloud project with APIs enabled

### 1. Clone the Repository
```bash
git clone https://github.com/Adichauhan39/Triplix-AI-Travel-Planner.git
cd Triplix-AI-Travel-Planner
```

### 2. Backend Setup
```bash
cd 7-multi-agent
python -m venv .venv
.venv/Scripts/Activate.ps1  # Windows
# source .venv/bin/activate  # Linux/Mac

pip install -r requirements.txt

# Copy and configure environment variables
cp .env.example .env
# Edit .env with your API keys

# Run the server
python -m uvicorn ultra_simple_server:app --host 0.0.0.0 --port 8001
```

### 3. Frontend Setup
```bash
cd flutter_travel_app
flutter pub get
flutter run -d chrome
```

### 4. Deploy to Google Cloud
```bash
# Backend
cd 7-multi-agent
gcloud run deploy triplix-server --source . --region us-central1 --allow-unauthenticated

# Frontend
cd flutter_travel_app
flutter build web --no-tree-shake-icons
cd build/web
gcloud run deploy triplix-web --source . --region us-central1 --allow-unauthenticated
```

---

## 📁 Project Structure

```
Triplix-AI-Travel-Planner/
├── 7-multi-agent/                  # Python Backend
│   ├── ultra_simple_server.py      # FastAPI server (25+ endpoints)
│   ├── main.py                     # ADK entry point
│   ├── Dockerfile                  # Container config
│   ├── requirements.txt            # Python dependencies
│   ├── manager/
│   │   ├── agent.py                # Root agent orchestrator
│   │   ├── sub_agents/
│   │   │   ├── hotel_booking/      # Hotel search & booking
│   │   │   ├── travel_booking/     # Transport search
│   │   │   ├── destination_info/   # City & attraction info
│   │   │   ├── budget_tracker/     # Expense management
│   │   │   ├── swipe_recommendations/ # AI card generation
│   │   │   ├── itinerary/          # Trip planning
│   │   │   ├── web_hotel_search/   # Live hotel prices
│   │   │   └── checkpoint_analyzer/ # Preference learning
│   │   └── tools/                  # Shared agent tools
│   └── data/                       # CSV datasets
│
├── flutter_travel_app/             # Flutter Frontend
│   ├── lib/
│   │   ├── main.dart               # App entry point
│   │   ├── config/                 # App configuration
│   │   ├── models/                 # Data models
│   │   ├── providers/              # State management
│   │   ├── screens/                # UI screens
│   │   ├── services/               # API & business logic
│   │   └── widgets/                # Reusable components
│   └── pubspec.yaml                # Flutter dependencies
│
├── cloudbuild.yaml                 # Google Cloud Build config
└── README.md
```

---

## 🔌 API Endpoints (25+)

| Endpoint | Method | Description |
|----------|--------|-------------|
| `/api/health` | GET | Health check |
| `/api/manager` | POST | AI manager (main orchestrator) |
| `/api/hotel/search` | POST | Search hotels |
| `/api/transport/search` | POST | Search flights/trains/buses |
| `/swipe/recommendations` | POST | AI-generated swipe cards |
| `/swipe/action` | POST | Record swipe (like/dislike) |
| `/booking` | POST | Create booking |
| `/bookings` | GET | Get all bookings |
| `/api/maps/directions` | POST | Route directions |
| `/api/places/nearby` | POST | Nearby attractions |
| `/api/hotel/images` | POST | Hotel photos |
| `/api/analyze-preferences` | POST | AI preference analysis |
| `/docs` | GET | Swagger UI (full API docs) |

---

## 👤 Team

- **Aditya Chauhan** — Full Stack Developer
  - [GitHub](https://github.com/Adichauhan39)
  - Email: adichauhan39@gmail.com

---

## 📄 License

This project is licensed under the MIT License — see the [LICENSE](LICENSE) file for details.

---

## 🙏 Acknowledgments

- [Google Cloud Rapid Agent Hackathon](https://rapid-agent.devpost.com/)
- Google Gemini & Vertex AI team
- Google ADK (Agent Development Kit)
- Flutter & Dart community

---

<p align="center">
  <b>Triplix — One app. One conversation. Your entire trip — planned.</b>
</p>
