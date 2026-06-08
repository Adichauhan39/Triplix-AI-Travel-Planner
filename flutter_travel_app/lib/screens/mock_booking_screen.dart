import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'dart:math';

class MockBookingScreen extends StatefulWidget {
  final List<Map<String, dynamic>> acceptedHotels;
  final List<Map<String, dynamic>> acceptedTransport;
  final List<Map<String, dynamic>> acceptedDestinations;

  const MockBookingScreen({
    super.key,
    required this.acceptedHotels,
    required this.acceptedTransport,
    required this.acceptedDestinations,
  });

  @override
  State<MockBookingScreen> createState() => _MockBookingScreenState();
}

class _MockBookingScreenState extends State<MockBookingScreen>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _fadeAnimation;
  bool _isProcessing = true;
  String _currentStep = 'Verifying availability...';
  double _progress = 0.0;

  String? _bookingId;
  String? _pnr;
  final List<String> _hotelConfirmations = [];

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      duration: const Duration(milliseconds: 1500),
      vsync: this,
    );

    _fadeAnimation = CurvedAnimation(
      parent: _controller,
      curve: Curves.easeIn,
    );

    _controller.forward();
    _simulateBookingProcess();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _simulateBookingProcess() async {
    // Step 1: Verify availability
    setState(() {
      _currentStep = '🔍 Verifying availability...';
      _progress = 0.2;
    });
    await Future.delayed(const Duration(seconds: 2));

    // Step 2: Process payment
    setState(() {
      _currentStep = '💳 Processing payment...';
      _progress = 0.4;
    });
    await Future.delayed(const Duration(seconds: 2));

    // Step 3: Generate confirmations
    setState(() {
      _currentStep = '📝 Generating booking confirmations...';
      _progress = 0.6;
    });
    await Future.delayed(const Duration(seconds: 1));

    // Step 4: Sending emails
    setState(() {
      _currentStep = '📧 Sending confirmation emails...';
      _progress = 0.8;
    });
    await Future.delayed(const Duration(seconds: 1));

    // Generate booking details
    _bookingId = 'TRX${Random().nextInt(999999).toString().padLeft(6, '0')}';
    _pnr = 'PNR${Random().nextInt(999999).toString().padLeft(6, '0')}';

    for (int i = 0; i < widget.acceptedHotels.length; i++) {
      _hotelConfirmations
          .add('HTL${Random().nextInt(999999).toString().padLeft(6, '0')}');
    }

    // Step 5: Complete
    setState(() {
      _currentStep = '✅ Booking confirmed!';
      _progress = 1.0;
      _isProcessing = false;
    });
  }

  double _calculateTotalCost() {
    double total = 0;

    for (var hotel in widget.acceptedHotels) {
      final priceStr =
          hotel['price'].toString().replaceAll(RegExp(r'[^\d.]'), '');
      total += double.tryParse(priceStr) ?? 0;
    }

    for (var transport in widget.acceptedTransport) {
      final priceStr =
          transport['price'].toString().replaceAll(RegExp(r'[^\d.]'), '');
      total += double.tryParse(priceStr) ?? 0;
    }

    return total;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0A0E21),
      appBar: AppBar(
        title: const Text('Booking Confirmation'),
        backgroundColor: const Color(0xFF1D1E33),
        elevation: 0,
      ),
      body: _isProcessing ? _buildProcessingView() : _buildConfirmationView(),
    );
  }

  Widget _buildProcessingView() {
    return Center(
      child: FadeTransition(
        opacity: _fadeAnimation,
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            // Animated loading circle
            SizedBox(
              width: 120,
              height: 120,
              child: Stack(
                alignment: Alignment.center,
                children: [
                  CircularProgressIndicator(
                    value: _progress,
                    strokeWidth: 8,
                    backgroundColor: Colors.grey.shade800,
                    valueColor: const AlwaysStoppedAnimation<Color>(
                      Color(0xFF00D9FF),
                    ),
                  ),
                  Text(
                    '${(_progress * 100).toInt()}%',
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 24,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 40),
            Text(
              _currentStep,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 18,
                fontWeight: FontWeight.w500,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 20),
            const Text(
              'Please wait while we secure your booking',
              style: TextStyle(
                color: Colors.grey,
                fontSize: 14,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildConfirmationView() {
    final totalCost = _calculateTotalCost();

    return SingleChildScrollView(
      child: Padding(
        padding: const EdgeInsets.all(20.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Success animation
            Center(
              child: Container(
                width: 120,
                height: 120,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: Colors.green.withValues(alpha: 0.2),
                ),
                child: const Icon(
                  Icons.check_circle,
                  color: Colors.green,
                  size: 80,
                ),
              ),
            ),
            const SizedBox(height: 20),

            const Center(
              child: Text(
                '🎉 Booking Successful!',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 28,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
            const SizedBox(height: 10),

            Center(
              child: Text(
                'Your trip has been confirmed',
                style: TextStyle(
                  color: Colors.grey.shade400,
                  fontSize: 16,
                ),
              ),
            ),
            const SizedBox(height: 30),

            // Booking Reference Card
            _buildReferenceCard(),
            const SizedBox(height: 20),

            // Hotels Section
            if (widget.acceptedHotels.isNotEmpty) ...[
              _buildSectionTitle('🏨 Hotel Bookings'),
              ...widget.acceptedHotels.asMap().entries.map((entry) {
                return _buildHotelCard(
                    entry.value, _hotelConfirmations[entry.key]);
              }),
              const SizedBox(height: 20),
            ],

            // Transport Section
            if (widget.acceptedTransport.isNotEmpty) ...[
              _buildSectionTitle('✈️ Transport Bookings'),
              ...widget.acceptedTransport.map((transport) {
                return _buildTransportCard(transport);
              }),
              const SizedBox(height: 20),
            ],

            // Destinations Section
            if (widget.acceptedDestinations.isNotEmpty) ...[
              _buildSectionTitle('📍 Planned Destinations'),
              _buildDestinationsCard(),
              const SizedBox(height: 20),
            ],

            // Payment Summary
            _buildPaymentSummary(totalCost),
            const SizedBox(height: 30),

            // Action Buttons
            _buildActionButtons(),
            const SizedBox(height: 20),
          ],
        ),
      ),
    );
  }

  Widget _buildReferenceCard() {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFF00D9FF), Color(0xFF0066FF)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(15),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF00D9FF).withValues(alpha: 0.3),
            blurRadius: 15,
            offset: const Offset(0, 5),
          ),
        ],
      ),
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Booking ID',
                    style: TextStyle(
                      color: Colors.white70,
                      fontSize: 12,
                    ),
                  ),
                  const SizedBox(height: 5),
                  Row(
                    children: [
                      Text(
                        _bookingId ?? '',
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 20,
                          fontWeight: FontWeight.bold,
                          letterSpacing: 1.2,
                        ),
                      ),
                      const SizedBox(width: 10),
                      IconButton(
                        icon: const Icon(Icons.copy,
                            color: Colors.white, size: 18),
                        onPressed: () {
                          Clipboard.setData(
                              ClipboardData(text: _bookingId ?? ''));
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(content: Text('Booking ID copied!')),
                          );
                        },
                      ),
                    ],
                  ),
                ],
              ),
              const Icon(
                Icons.qr_code_2,
                color: Colors.white,
                size: 50,
              ),
            ],
          ),
          const Divider(color: Colors.white30, height: 30),
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Travel PNR',
                      style: TextStyle(
                        color: Colors.white70,
                        fontSize: 12,
                      ),
                    ),
                    const SizedBox(height: 5),
                    Text(
                      _pnr ?? '',
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
              ),
              IconButton(
                icon: const Icon(Icons.copy, color: Colors.white, size: 18),
                onPressed: () {
                  Clipboard.setData(ClipboardData(text: _pnr ?? ''));
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('PNR copied!')),
                  );
                },
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildSectionTitle(String title) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 15, top: 10),
      child: Text(
        title,
        style: const TextStyle(
          color: Colors.white,
          fontSize: 20,
          fontWeight: FontWeight.bold,
        ),
      ),
    );
  }

  Widget _buildHotelCard(Map<String, dynamic> hotel, String confirmationCode) {
    return Container(
      margin: const EdgeInsets.only(bottom: 15),
      padding: const EdgeInsets.all(15),
      decoration: BoxDecoration(
        color: const Color(0xFF1D1E33),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.green.withValues(alpha: 0.3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: Colors.green.withValues(alpha: 0.2),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: const Text(
                  'CONFIRMED',
                  style: TextStyle(
                    color: Colors.green,
                    fontSize: 10,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
              const Spacer(),
              Text(
                hotel['price']?.toString() ?? '',
                style: const TextStyle(
                  color: Color(0xFF00D9FF),
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Text(
            hotel['title']?.toString() ?? '',
            style: const TextStyle(
              color: Colors.white,
              fontSize: 16,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 5),
          Text(
            hotel['location']?.toString() ?? '',
            style: TextStyle(
              color: Colors.grey.shade400,
              fontSize: 14,
            ),
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              const Icon(Icons.confirmation_number,
                  color: Colors.grey, size: 16),
              const SizedBox(width: 5),
              Text(
                confirmationCode,
                style: const TextStyle(
                  color: Colors.grey,
                  fontSize: 12,
                  fontFamily: 'monospace',
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildTransportCard(Map<String, dynamic> transport) {
    return Container(
      margin: const EdgeInsets.only(bottom: 15),
      padding: const EdgeInsets.all(15),
      decoration: BoxDecoration(
        color: const Color(0xFF1D1E33),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.green.withValues(alpha: 0.3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: Colors.green.withValues(alpha: 0.2),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: const Text(
                  'CONFIRMED',
                  style: TextStyle(
                    color: Colors.green,
                    fontSize: 10,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
              const Spacer(),
              Text(
                transport['price']?.toString() ?? '',
                style: const TextStyle(
                  color: Color(0xFF00D9FF),
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Text(
            transport['title']?.toString() ?? '',
            style: const TextStyle(
              color: Colors.white,
              fontSize: 16,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 5),
          if (transport['details'] != null)
            Text(
              transport['details'].toString(),
              style: TextStyle(
                color: Colors.grey.shade400,
                fontSize: 14,
              ),
            ),
          const SizedBox(height: 10),
          Row(
            children: [
              const Icon(Icons.confirmation_number,
                  color: Colors.grey, size: 16),
              const SizedBox(width: 5),
              Text(
                _pnr ?? '',
                style: const TextStyle(
                  color: Colors.grey,
                  fontSize: 12,
                  fontFamily: 'monospace',
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildDestinationsCard() {
    return Container(
      padding: const EdgeInsets.all(15),
      decoration: BoxDecoration(
        color: const Color(0xFF1D1E33),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: widget.acceptedDestinations.map((dest) {
          return Padding(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: Row(
              children: [
                const Icon(Icons.location_on,
                    color: Color(0xFF00D9FF), size: 20),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    dest['title']?.toString() ?? '',
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 15,
                    ),
                  ),
                ),
              ],
            ),
          );
        }).toList(),
      ),
    );
  }

  Widget _buildPaymentSummary(double totalCost) {
    final taxes = totalCost * 0.12; // 12% GST
    final grandTotal = totalCost + taxes;

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: const Color(0xFF1D1E33),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFF00D9FF).withValues(alpha: 0.3)),
      ),
      child: Column(
        children: [
          const Text(
            '💰 Payment Summary',
            style: TextStyle(
              color: Colors.white,
              fontSize: 18,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 15),
          _buildPriceRow('Subtotal', '₹${totalCost.toStringAsFixed(2)}'),
          _buildPriceRow('Taxes & Fees (12%)', '₹${taxes.toStringAsFixed(2)}'),
          const Divider(color: Colors.grey, height: 20),
          _buildPriceRow(
            'Total Paid',
            '₹${grandTotal.toStringAsFixed(2)}',
            isTotal: true,
          ),
          const SizedBox(height: 10),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            decoration: BoxDecoration(
              color: Colors.green.withValues(alpha: 0.2),
              borderRadius: BorderRadius.circular(6),
            ),
            child: const Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.check_circle, color: Colors.green, size: 16),
                SizedBox(width: 5),
                Text(
                  'Payment Successful',
                  style: TextStyle(
                    color: Colors.green,
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPriceRow(String label, String amount, {bool isTotal = false}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            label,
            style: TextStyle(
              color: isTotal ? Colors.white : Colors.grey.shade400,
              fontSize: isTotal ? 18 : 15,
              fontWeight: isTotal ? FontWeight.bold : FontWeight.normal,
            ),
          ),
          Text(
            amount,
            style: TextStyle(
              color: isTotal ? const Color(0xFF00D9FF) : Colors.white,
              fontSize: isTotal ? 20 : 15,
              fontWeight: isTotal ? FontWeight.bold : FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildActionButtons() {
    return Column(
      children: [
        SizedBox(
          width: double.infinity,
          height: 50,
          child: ElevatedButton.icon(
            onPressed: () {
              // Download ticket functionality
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('Downloading tickets...')),
              );
            },
            icon: const Icon(Icons.download),
            label: const Text('Download Tickets'),
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF00D9FF),
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
          ),
        ),
        const SizedBox(height: 10),
        SizedBox(
          width: double.infinity,
          height: 50,
          child: OutlinedButton.icon(
            onPressed: () {
              // Share functionality
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('Sharing booking details...')),
              );
            },
            icon: const Icon(Icons.share),
            label: const Text('Share Booking'),
            style: OutlinedButton.styleFrom(
              foregroundColor: const Color(0xFF00D9FF),
              side: const BorderSide(color: Color(0xFF00D9FF)),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
          ),
        ),
        const SizedBox(height: 10),
        SizedBox(
          width: double.infinity,
          height: 50,
          child: TextButton(
            onPressed: () {
              Navigator.of(context).pop();
            },
            style: TextButton.styleFrom(
              foregroundColor: Colors.grey.shade400,
            ),
            child: const Text('Back to Home'),
          ),
        ),
      ],
    );
  }
}
