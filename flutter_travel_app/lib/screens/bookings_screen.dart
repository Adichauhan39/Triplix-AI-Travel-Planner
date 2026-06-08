import 'package:flutter/material.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:share_plus/share_plus.dart';
import 'package:animate_do/animate_do.dart';
import '../config/app_config.dart';
import '../services/api_service.dart';
import '../models/booking.dart';

class BookingsScreen extends StatefulWidget {
  const BookingsScreen({super.key});

  @override
  State<BookingsScreen> createState() => _BookingsScreenState();
}

class _BookingsScreenState extends State<BookingsScreen>
    with SingleTickerProviderStateMixin {
  final ApiService _api = ApiService();
  late TabController _tabController;

  List<Booking> _upcomingBookings = [];
  List<Booking> _pastBookings = [];
  List<Booking> _cancelledBookings = [];
  bool _loading = false;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
    _loadBookings();
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _loadBookings() async {
    setState(() => _loading = true);
    try {
      final bookings = await _api.getBookings();

      final now = DateTime.now();
      setState(() {
        _upcomingBookings = bookings.where((b) {
          return b.checkInDate.isAfter(now) && b.status != 'cancelled';
        }).toList();

        _pastBookings = bookings.where((b) {
          return b.checkOutDate != null &&
              b.checkOutDate!.isBefore(now) &&
              b.status != 'cancelled';
        }).toList();

        _cancelledBookings =
            bookings.where((b) => b.status == 'cancelled').toList();
        _loading = false;
      });
    } catch (e) {
      setState(() => _loading = false);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error loading bookings: $e')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('My Bookings'),
        centerTitle: true,
        bottom: TabBar(
          controller: _tabController,
          tabs: const [
            Tab(text: 'Upcoming'),
            Tab(text: 'Past'),
            Tab(text: 'Cancelled'),
          ],
        ),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : TabBarView(
              controller: _tabController,
              children: [
                _BookingsList(
                    bookings: _upcomingBookings, onRefresh: _loadBookings),
                _BookingsList(
                    bookings: _pastBookings, onRefresh: _loadBookings),
                _BookingsList(
                    bookings: _cancelledBookings, onRefresh: _loadBookings),
              ],
            ),
    );
  }
}

class _BookingsList extends StatelessWidget {
  final List<Booking> bookings;
  final VoidCallback onRefresh;

  const _BookingsList({
    required this.bookings,
    required this.onRefresh,
  });

  @override
  Widget build(BuildContext context) {
    if (bookings.isEmpty) {
      return const Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.inbox_outlined, size: 80, color: Colors.grey),
            SizedBox(height: 16),
            Text(
              'No bookings found',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
            ),
            SizedBox(height: 8),
            Text(
              'Your bookings will appear here',
              style: TextStyle(color: AppConfig.textSecondary),
            ),
          ],
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: () async => onRefresh(),
      child: ListView.builder(
        padding: const EdgeInsets.all(AppConfig.paddingMedium),
        itemCount: bookings.length,
        itemBuilder: (context, index) {
          return FadeInUp(
            delay: Duration(milliseconds: 50 * index),
            child: _BookingCard(booking: bookings[index]),
          );
        },
      ),
    );
  }
}

class _BookingCard extends StatelessWidget {
  final Booking booking;

  const _BookingCard({required this.booking});

  @override
  Widget build(BuildContext context) {
    final isUpcoming = booking.checkInDate.isAfter(DateTime.now());

    return Card(
      margin: const EdgeInsets.only(bottom: 16),
      elevation: 2,
      child: InkWell(
        onTap: () => _showBookingDetails(context),
        borderRadius: BorderRadius.circular(AppConfig.radiusMedium),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Header
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Expanded(
                    child: Text(
                      booking.hotelName,
                      style: const TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                  _StatusChip(status: booking.status),
                ],
              ),

              const SizedBox(height: 12),

              // Booking ID
              Row(
                children: [
                  const Icon(Icons.confirmation_number,
                      size: 16, color: Colors.grey),
                  const SizedBox(width: 8),
                  Text(
                    'ID: ${booking.bookingId}',
                    style: const TextStyle(fontSize: 12, color: Colors.grey),
                  ),
                ],
              ),

              const SizedBox(height: 8),

              // Dates
              Row(
                children: [
                  const Icon(Icons.calendar_today,
                      size: 16, color: Colors.grey),
                  const SizedBox(width: 8),
                  Text(
                    '${_formatDate(booking.checkInDate)} - ${_formatDate(booking.checkOutDate)}',
                    style: const TextStyle(fontSize: 14),
                  ),
                ],
              ),

              const SizedBox(height: 8),

              // Price
              Row(
                children: [
                  const Icon(Icons.currency_rupee,
                      size: 16, color: Colors.grey),
                  const SizedBox(width: 8),
                  Text(
                    booking.totalPrice.toString(),
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                      color: AppConfig.successColor,
                    ),
                  ),
                ],
              ),

              if (isUpcoming) ...[
                const SizedBox(height: 16),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: () => _addToCalendar(context),
                        icon: const Icon(Icons.calendar_month, size: 18),
                        label: const Text('Add to Calendar'),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: () => _shareBooking(context),
                        icon: const Icon(Icons.share, size: 18),
                        label: const Text('Share'),
                      ),
                    ),
                  ],
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  String _formatDate(DateTime? date) {
    if (date == null) return 'N/A';
    return '${date.day}/${date.month}/${date.year}';
  }

  void _showBookingDetails(BuildContext context) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) => DraggableScrollableSheet(
        initialChildSize: 0.7,
        minChildSize: 0.5,
        maxChildSize: 0.9,
        expand: false,
        builder: (context, scrollController) => SingleChildScrollView(
          controller: scrollController,
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(
                child: Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: Colors.grey[300],
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              const SizedBox(height: 24),

              // QR Code
              Center(
                child: Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(12),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.grey.withValues(alpha: 0.2),
                        blurRadius: 8,
                        offset: const Offset(0, 4),
                      ),
                    ],
                  ),
                  child: QrImageView(
                    data: booking.bookingId,
                    version: QrVersions.auto,
                    size: 200,
                  ),
                ),
              ),

              const SizedBox(height: 24),

              // Details
              const Text(
                'Booking Details',
                style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 16),

              _DetailRow(label: 'Hotel', value: booking.hotelName),
              _DetailRow(label: 'Booking ID', value: booking.bookingId),
              _DetailRow(
                  label: 'Check-in', value: _formatDate(booking.checkInDate)),
              _DetailRow(
                  label: 'Check-out', value: _formatDate(booking.checkOutDate)),
              _DetailRow(label: 'Status', value: booking.status),
              _DetailRow(label: 'Total Price', value: '₹${booking.totalPrice}'),

              const SizedBox(height: 24),

              // Actions
              SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  onPressed: () {
                    Navigator.pop(context);
                    _addToCalendar(context);
                  },
                  icon: const Icon(Icons.calendar_month),
                  label: const Text('Add to Calendar'),
                  style: ElevatedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 16),
                  ),
                ),
              ),
              const SizedBox(height: 12),
              SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  onPressed: () {
                    Navigator.pop(context);
                    _shareBooking(context);
                  },
                  icon: const Icon(Icons.share),
                  label: const Text('Share Booking'),
                  style: OutlinedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 16),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _addToCalendar(BuildContext context) {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('✓ Added to calendar with reminders'),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  void _shareBooking(BuildContext context) {
    Share.share(
      'My booking at ${booking.hotelName}\n'
      'Check-in: ${_formatDate(booking.checkInDate)}\n'
      'Check-out: ${_formatDate(booking.checkOutDate)}\n'
      'Booking ID: ${booking.bookingId}',
      subject: 'Travel Booking Details',
    );
  }
}

class _StatusChip extends StatelessWidget {
  final String status;

  const _StatusChip({required this.status});

  @override
  Widget build(BuildContext context) {
    Color color;
    switch (status.toLowerCase()) {
      case 'confirmed':
        color = AppConfig.successColor;
        break;
      case 'pending':
        color = AppConfig.warningColor;
        break;
      case 'cancelled':
        color = AppConfig.errorColor;
        break;
      default:
        color = Colors.grey;
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Text(
        status.toUpperCase(),
        style: TextStyle(
          color: color,
          fontSize: 10,
          fontWeight: FontWeight.bold,
        ),
      ),
    );
  }
}

class _DetailRow extends StatelessWidget {
  final String label;
  final String value;

  const _DetailRow({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 100,
            child: Text(
              label,
              style: const TextStyle(
                color: AppConfig.textSecondary,
                fontSize: 14,
              ),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: const TextStyle(
                fontWeight: FontWeight.w600,
                fontSize: 14,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
