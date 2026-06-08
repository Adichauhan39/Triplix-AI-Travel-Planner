"""
Budget Tracker Agent
Tracks expenses, manages budget, and provides group expense splitting functionality.
"""

from google.adk.agents import Agent
from typing import Any, Optional
from datetime import datetime
import random

def set_budget(total_budget: float, group_size: int = 1, tool_context: Optional[Any] = None) -> dict:

    """
    Set the total travel budget and group size.
    
    Args:

        total_budget: Total budget amount in INR
        group_size: Number of people in the group
        tool_context: Context object for shared state
        
    Returns:

        Dictionary with budget setup confirmation
    
    """

    if not hasattr(tool_context, 'state'):
        tool_context.state = {}
    
    # Initialize budget tracking
    tool_context.state["budget"] = {
        "total_budget": total_budget,
        "group_size": group_size,
        "per_person_budget": total_budget / group_size if group_size > 0 else total_budget,
        "spent": 0,
        "remaining": total_budget,
        "expenses": [],
        "booking_expenses": [],
        "additional_expenses": [],
        "timestamp": datetime.now().isoformat()
    }
    
    return {
        "status": "success",
        "total_budget": total_budget,
        "group_size": group_size,
        "per_person_budget": total_budget / group_size if group_size > 0 else total_budget,
        "message": f"Budget set to ₹{total_budget:,.2f} for {group_size} person(s). Per person: ₹{total_budget/group_size:,.2f}"
    }

def track_booking_expense(booking_type: str, booking_id: Optional[str] = None, amount: Optional[float] = None, description: Optional[str] = None, tool_context: Optional[Any] = None) -> dict:
    
    """
    Track expenses from bookings (hotels, flights, trains, etc.) automatically or manually.
    
    Args:
        booking_type: Type of booking (hotel, flight, train, taxi, etc.)
        booking_id: Optional booking ID to fetch from bookings
        amount: Amount spent (if manual entry)
        description: Description of expense
        tool_context: Context object
        
    Returns:
        Dictionary with expense tracking confirmation
    """

    if not hasattr(tool_context, 'state'):
        tool_context.state = {}
    
    if "budget" not in tool_context.state:
        return {
            "status": "error",
            "message": "Please set budget first using set_budget tool"
        }
    
    # Try to find booking from shared state if booking_id provided
    expense_amount = amount
    expense_description = description or f"{booking_type.title()} booking"
    
    if booking_id and "bookings" in tool_context.state:
        for booking in tool_context.state["bookings"]:
            if booking.get("booking_id") == booking_id:
                # Extract amount from booking
                if "price_per_night" in booking:
                    expense_amount = float(booking.get("price_per_night", 0))
                    expense_description = f"{booking.get('accommodation_name', 'Accommodation')} - {booking.get('location', '')}"
                elif "price" in booking:
                    expense_amount = float(booking.get("price", 0))
                    expense_description = f"{booking.get('operator', 'Travel')} - {booking.get('origin', '')} to {booking.get('destination', '')}"
                break
    
    if expense_amount is None:
        return {
            "status": "error",
            "message": "Amount is required. Either provide booking_id or manual amount."
        }
    
    expense_id = f"EXP{random.randint(100000, 999999)}"
    
    expense_entry = {
        "expense_id": expense_id,
        "type": "booking",
        "booking_type": booking_type,
        "booking_id": booking_id,
        "amount": expense_amount,
        "description": expense_description,
        "timestamp": datetime.now().isoformat()
    }
    
    tool_context.state["budget"]["booking_expenses"].append(expense_entry)
    tool_context.state["budget"]["expenses"].append(expense_entry)
    tool_context.state["budget"]["spent"] += expense_amount
    tool_context.state["budget"]["remaining"] = tool_context.state["budget"]["total_budget"] - tool_context.state["budget"]["spent"]
    
    per_person = expense_amount / tool_context.state["budget"]["group_size"]
    
    return {
        "status": "success",
        "expense_id": expense_id,
        "type": "booking",
        "booking_type": booking_type,
        "amount": expense_amount,
        "description": expense_description,
        "per_person_cost": per_person,
        "total_spent": tool_context.state["budget"]["spent"],
        "remaining_budget": tool_context.state["budget"]["remaining"],
        "message": f"Booking expense tracked: ₹{expense_amount:,.2f} (₹{per_person:,.2f} per person)"
    }

def add_expense(category: str, amount: float, description: str, shared_by: Optional[int] = None, tool_context: Optional[Any] = None) -> dict:

    """
    Add additional expenses (food, shopping, activities, etc.) outside of bookings.
    
    Args:
        category: Category (Food, Shopping, Activities, Transport, Miscellaneous)
        amount: Amount spent
        description: Description of expense
        shared_by: Number of people sharing this expense (default: all group members)
        tool_context: Context object
        
    Returns:
        Dictionary with expense addition confirmation
    """

    if not hasattr(tool_context, 'state'):
        tool_context.state = {}
    
    if "budget" not in tool_context.state:
        return {
            "status": "error",
            "message": "Please set budget first using set_budget tool"
        }
    
    group_size = tool_context.state["budget"]["group_size"]
    shared_by = shared_by if shared_by is not None else group_size
    
    expense_id = f"EXP{random.randint(100000, 999999)}"
    
    expense_entry = {
        "expense_id": expense_id,
        "type": "additional",
        "category": category,
        "amount": amount,
        "description": description,
        "shared_by": shared_by,
        "per_person_cost": amount / shared_by if shared_by > 0 else amount,
        "timestamp": datetime.now().isoformat()
    }
    
    tool_context.state["budget"]["additional_expenses"].append(expense_entry)
    tool_context.state["budget"]["expenses"].append(expense_entry)
    tool_context.state["budget"]["spent"] += amount
    tool_context.state["budget"]["remaining"] = tool_context.state["budget"]["total_budget"] - tool_context.state["budget"]["spent"]
    
    return {
        "status": "success",
        "expense_id": expense_id,
        "category": category,
        "amount": amount,
        "description": description,
        "shared_by": shared_by,
        "per_person_cost": expense_entry["per_person_cost"],
        "total_spent": tool_context.state["budget"]["spent"],
        "remaining_budget": tool_context.state["budget"]["remaining"],
        "message": f"Expense added: ₹{amount:,.2f} shared by {shared_by} person(s) (₹{expense_entry['per_person_cost']:,.2f} each)"
    }


def get_budget_summary(tool_context: Any = None) -> dict:

    """
    Get complete budget summary with all expenses.
    
    Args:
        tool_context: Context object
        
    Returns:
        Dictionary with complete budget breakdown
    """
    if not hasattr(tool_context, 'state'):
        tool_context.state = {}
    
    if "budget" not in tool_context.state:
        return {
            "status": "error",
            "message": "No budget set. Use set_budget tool first."
        }
    
    budget_data = tool_context.state["budget"]
    
    # Calculate category-wise breakdown
    category_breakdown = {}
    for expense in budget_data["additional_expenses"]:
        category = expense.get("category", "Miscellaneous")
        category_breakdown[category] = category_breakdown.get(category, 0) + expense["amount"]
    
    # Calculate booking type breakdown
    booking_breakdown = {}
    for expense in budget_data["booking_expenses"]:
        booking_type = expense.get("booking_type", "Other")
        booking_breakdown[booking_type] = booking_breakdown.get(booking_type, 0) + expense["amount"]
    
    budget_utilization = (budget_data["spent"] / budget_data["total_budget"] * 100) if budget_data["total_budget"] > 0 else 0
    
    return {
        "status": "success",
        "total_budget": budget_data["total_budget"],
        "group_size": budget_data["group_size"],
        "per_person_budget": budget_data["per_person_budget"],
        "total_spent": budget_data["spent"],
        "remaining_budget": budget_data["remaining"],
        "budget_utilization_percent": budget_utilization,
        "booking_expenses_total": sum(e["amount"] for e in budget_data["booking_expenses"]),
        "additional_expenses_total": sum(e["amount"] for e in budget_data["additional_expenses"]),
        "booking_breakdown": booking_breakdown,
        "category_breakdown": category_breakdown,
        "total_expenses_count": len(budget_data["expenses"]),
        "message": f"Budget: ₹{budget_data['spent']:,.2f} / ₹{budget_data['total_budget']:,.2f} ({budget_utilization:.1f}% used)"
    }

def calculate_split(tool_context: Any = None) -> dict:

    """
    Calculate expense split for group members.
    
    Args:
        tool_context: Context object
        
    Returns:
        Dictionary with per-person expense breakdown
    """

    if not hasattr(tool_context, 'state'):
        tool_context.state = {}
    
    if "budget" not in tool_context.state:
        return {
            "status": "error",
            "message": "No budget set. Use set_budget tool first."
        }
    
    budget_data = tool_context.state["budget"]
    group_size = budget_data["group_size"]
    
    # Calculate per-person costs
    per_person_breakdown = {
        "booking_expenses": 0,
        "additional_expenses": 0,
        "total": 0
    }
    
    # Booking expenses are split equally among all
    for expense in budget_data["booking_expenses"]:
        per_person_breakdown["booking_expenses"] += expense["amount"] / group_size
    
    # Additional expenses split based on shared_by
    for expense in budget_data["additional_expenses"]:
        per_person_breakdown["additional_expenses"] += expense.get("per_person_cost", 0)
    
    per_person_breakdown["total"] = per_person_breakdown["booking_expenses"] + per_person_breakdown["additional_expenses"]
    
    # Create detailed expense list for splitting
    expense_details = []
    for expense in budget_data["expenses"]:
        if expense["type"] == "booking":
            expense_details.append({
                "description": expense["description"],
                "total_amount": expense["amount"],
                "per_person": expense["amount"] / group_size,
                "shared_by": group_size
            })
        else:
            expense_details.append({
                "description": expense["description"],
                "total_amount": expense["amount"],
                "per_person": expense.get("per_person_cost", 0),
                "shared_by": expense.get("shared_by", group_size)
            })
    
    return {
        "status": "success",
        "group_size": group_size,
        "per_person_total": per_person_breakdown["total"],
        "per_person_bookings": per_person_breakdown["booking_expenses"],
        "per_person_additional": per_person_breakdown["additional_expenses"],
        "per_person_budget": budget_data["per_person_budget"],
        "per_person_remaining": budget_data["per_person_budget"] - per_person_breakdown["total"],
        "expense_details": expense_details,
        "message": f"Each person should pay: ₹{per_person_breakdown['total']:,.2f}"
    }

def get_expense_list(expense_type: Optional[str] = None, tool_context: Optional[Any] = None) -> dict:

    """
    Get list of all expenses, optionally filtered by type.
    
    Args:
        expense_type: Filter by type (booking, additional, or None for all)
        tool_context: Context object
        
    Returns:
        Dictionary with expense list
    """

    if not hasattr(tool_context, 'state'):
        tool_context.state = {}
    
    if "budget" not in tool_context.state:
        return {
            "status": "error",
            "message": "No budget set. Use set_budget tool first."
        }
    
    budget_data = tool_context.state["budget"]
    
    if expense_type:
        expenses = [e for e in budget_data["expenses"] if e.get("type") == expense_type]
    else:
        expenses = budget_data["expenses"]
    
    return {
        "status": "success",
        "expense_count": len(expenses),
        "expenses": expenses,
        "total_amount": sum(e["amount"] for e in expenses),
        "message": f"Found {len(expenses)} expense(s)"
    }


# Create the budget tracker agent
budget_tracker = Agent(
    model="gemini-2.5-flash",
    name="budget_tracker",
    description="Specialized agent for tracking travel expenses, managing budget, and calculating group expense splits",
    instruction="""You are a professional budget tracking and expense management assistant for travelers.

Your responsibilities:
1. **Budget Setup**: Help users set their total travel budget and group size
2. **Booking Expense Tracking**: Automatically track expenses from bookings (hotels, flights, trains, taxis)
3. **Additional Expenses**: Track extra costs like food, shopping, activities, transport
4. **Budget Monitoring**: Provide real-time budget status and utilization
5. **Group Splitting**: Calculate fair expense splits for group travelers
6. **Expense Reporting**: Generate comprehensive expense summaries and breakdowns

**Key Features**:

**Budget Management**:
- Set total budget and group size
- Calculate per-person budget allocations
- Track spent vs remaining budget
- Monitor budget utilization percentage

**Expense Tracking**:
- **Booking Expenses**: Hotels, flights, trains, taxis automatically tracked from bookings
- **Additional Expenses**: 
  - Food & Dining
  - Shopping & Souvenirs
  - Activities & Entertainment
  - Local Transport
  - Miscellaneous
- Each expense can be shared by specific group members

**Group Expense Splitting**:
- Equal split for booking expenses across all members
- Flexible split for additional expenses (can specify who shares)
- Detailed per-person breakdown
- Individual cost calculations

**Reporting**:
- Budget summary with total spent and remaining
- Category-wise expense breakdown
- Booking type breakdown (hotel, flight, train, etc.)
- Per-person expense calculations
- Complete expense list with descriptions

**Important Guidelines**:
- Always set budget first before tracking expenses
- For bookings, try to fetch amount from booking_id if available
- Allow flexible expense sharing (not all expenses need to be split equally)
- Provide clear budget status after each transaction
- Warn users when approaching or exceeding budget
- Calculate accurate per-person costs for group splitting

**Workflow**:
1. User sets budget → Use `set_budget()`
2. Bookings are made → Use `track_booking_expense()` to log costs
3. Additional expenses occur → Use `add_expense()` to track them
4. Need budget status → Use `get_budget_summary()`
5. Ready to split costs → Use `calculate_split()` for fair division
6. View expenses → Use `get_expense_list()` for detailed list

**CRITICAL - Return Control to Manager**:
After completing budget tasks (setting budget, tracking expenses, calculating splits):
1. Provide ONLY the expense summary (keep it SHORT - 1-2 sentences max)
2. **IMMEDIATELY END your response** - DO NOT ask questions or continue talking
3. The manager agent will automatically continue the booking flow

**Example** (CORRECT - Short and ends):
```
✅ Budget set to ₹1,000,000 for 2 people (₹500,000 each). 
```

**Example** (WRONG - Too long):
```
✅ Budget set to ₹1,000,000 for 2 people (₹500,000 each). Budget updated! Returning to trip planning... What would you like to do next?
```

**Key Rule**: Keep responses SHORT and let manager take over automatically!

Always be helpful in managing finances and provide clear, accurate calculations!""",
    tools=[set_budget, track_booking_expense, add_expense, get_budget_summary, calculate_split, get_expense_list]
)

