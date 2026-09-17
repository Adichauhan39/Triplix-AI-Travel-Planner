/// The trip's spending as a PDF, for the end of the trip.
///
/// The thing a group actually sends each other when a trip is over: who paid
/// what, what each person's share came to, and who still owes whom -- in one
/// file that does not need the app, a login or a signal to read.
///
/// Built on the device rather than on the server. It needs nothing the phone
/// does not already have, so it works with no connection, which is exactly
/// when somebody on the way home wants it.
///
/// The figures are passed in rather than worked out here. The columns and the
/// settlement are computed by the same functions the screens use, so the sheet
/// cannot quietly disagree with what everybody was looking at in the app.
library;

import 'dart:typed_data';

import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import 'expense_columns.dart';
import 'settle_up.dart';
import 'trip_sync.dart';

const _months = [
  'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
  'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'
];

String _date(DateTime at) {
  final local = at.toLocal();
  return '${local.day} ${_months[local.month - 1]} ${local.year}';
}

/// Builds the sheet.
///
/// [regularFont] and [boldFont] are TrueType bytes and must contain the rupee
/// sign. The PDF library's built-in fonts do not, so every amount would print
/// with a blank where the currency should be -- found out the hard way on the
/// render server with a missing arrow, and not repeated here.
Future<Uint8List> buildExpenseSheet({
  required String tripName,
  required List<TripExpense> approved,
  required List<PersonColumn> columns,
  required List<Debt> debts,
  required String Function(String uid) nameOf,
  required Uint8List regularFont,
  required Uint8List boldFont,
  DateTime? madeAt,
}) async {
  final regular = pw.Font.ttf(ByteData.sublistView(regularFont));
  final bold = pw.Font.ttf(ByteData.sublistView(boldFont));

  const teal = PdfColor.fromInt(0xFF1FA7C4);
  const ink = PdfColor.fromInt(0xFF0F172A);
  const muted = PdfColor.fromInt(0xFF64748B);
  const hairline = PdfColor.fromInt(0xFFE2E8F0);
  const good = PdfColor.fromInt(0xFF047857);

  final total = approved.fold<int>(0, (sum, row) => sum + row.paise);
  final title = tripName.trim().isEmpty ? 'Our trip' : tripName.trim();

  // Newest last, the way a list of receipts reads.
  final rows = [...approved]..sort((a, b) => a.at.compareTo(b.at));

  pw.Widget heading(String text) => pw.Padding(
        padding: const pw.EdgeInsets.only(top: 18, bottom: 6),
        child: pw.Text(text,
            style: pw.TextStyle(font: bold, fontSize: 13, color: ink)),
      );

  final doc = pw.Document(
    title: '$title - shared spending',
    author: 'Triplix',
  );

  doc.addPage(
    pw.MultiPage(
      pageFormat: PdfPageFormat.a4,
      margin: const pw.EdgeInsets.fromLTRB(36, 36, 36, 40),
      theme: pw.ThemeData.withFont(base: regular, bold: bold),
      // Page numbers, because a sheet that runs to three pages and gets
      // printed needs them to go back in order.
      footer: (context) => pw.Row(
        mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
        children: [
          pw.Text('Made with Triplix',
              style: const pw.TextStyle(fontSize: 8, color: muted)),
          pw.Text('Page ${context.pageNumber} of ${context.pagesCount}',
              style: const pw.TextStyle(fontSize: 8, color: muted)),
        ],
      ),
      build: (context) => [
        // ----------------------------------------------------------- title
        pw.Text(title,
            style: pw.TextStyle(font: bold, fontSize: 22, color: ink)),
        pw.SizedBox(height: 2),
        pw.Text(
          'Shared spending  ·  made ${_date(madeAt ?? DateTime.now())}',
          style: const pw.TextStyle(fontSize: 10, color: muted),
        ),
        pw.SizedBox(height: 14),
        pw.Container(
          padding: const pw.EdgeInsets.all(12),
          decoration: pw.BoxDecoration(
            color: const PdfColor.fromInt(0xFFF1F9FB),
            borderRadius: pw.BorderRadius.circular(6),
          ),
          child: pw.Row(
            children: [
              pw.Expanded(
                child: pw.Column(
                  crossAxisAlignment: pw.CrossAxisAlignment.start,
                  children: [
                    pw.Text('Spent in all',
                        style: const pw.TextStyle(fontSize: 9, color: muted)),
                    pw.Text(formatRupees(total),
                        style:
                            pw.TextStyle(font: bold, fontSize: 18, color: teal)),
                  ],
                ),
              ),
              pw.Text(
                '${approved.length} '
                '${approved.length == 1 ? 'expense' : 'expenses'}  ·  '
                '${columns.length} '
                '${columns.length == 1 ? 'person' : 'people'}',
                style: const pw.TextStyle(fontSize: 10, color: muted),
              ),
            ],
          ),
        ),

        // -------------------------------------------------- who owes whom
        // Before the detail, because it is the part people open this for.
        heading('Who owes whom'),
        if (debts.isEmpty)
          pw.Text('Everyone is square.',
              style: const pw.TextStyle(fontSize: 11, color: good))
        else
          for (final debt in debts)
            pw.Padding(
              padding: const pw.EdgeInsets.symmetric(vertical: 2),
              child: pw.Row(
                children: [
                  pw.Expanded(
                    child: pw.Text(
                        '${nameOf(debt.from)} owes ${nameOf(debt.to)}',
                        style: const pw.TextStyle(fontSize: 11)),
                  ),
                  pw.Text(formatRupees(debt.paise),
                      style: pw.TextStyle(font: bold, fontSize: 11)),
                ],
              ),
            ),

        // ------------------------------------------------------ each person
        heading('Each person'),
        pw.TableHelper.fromTextArray(
          headers: ['Person', 'Paid', 'Their share', 'Balance'],
          data: [
            for (final column in columns)
              [
                // The person's own name, never "You". The columns say "You"
                // for whoever is looking at the app, but this is a file sent
                // to the whole group -- and every reader is somebody else.
                nameOf(column.uid),
                formatRupees(column.paid),
                // Somebody outside the split is not given a share or a
                // balance: the settlement never pays them back, so a number
                // here would be one that never comes true.
                column.inSplit ? formatRupees(column.share) : '-',
                !column.inSplit
                    ? '-'
                    : column.balance == 0
                        ? 'square'
                        : '${column.balance > 0 ? '+' : '-'}'
                            '${formatRupees(column.balance.abs())}',
              ]
          ],
          headerStyle: pw.TextStyle(font: bold, fontSize: 10, color: ink),
          cellStyle: const pw.TextStyle(fontSize: 10),
          headerDecoration:
              const pw.BoxDecoration(color: PdfColor.fromInt(0xFFF8FAFC)),
          border: const pw.TableBorder(
            horizontalInside: pw.BorderSide(color: hairline, width: 0.5),
            bottom: pw.BorderSide(color: hairline, width: 0.5),
          ),
          headerAlignment: pw.Alignment.centerLeft,
          headerAlignments: {
            1: pw.Alignment.centerRight,
            2: pw.Alignment.centerRight,
            3: pw.Alignment.centerRight,
          },
          cellAlignments: {
            1: pw.Alignment.centerRight,
            2: pw.Alignment.centerRight,
            3: pw.Alignment.centerRight,
          },
          cellPadding:
              const pw.EdgeInsets.symmetric(horizontal: 6, vertical: 5),
        ),
        pw.SizedBox(height: 4),
        pw.Text(
          'Balance is what each person gets back (+) or still owes (-).',
          style: const pw.TextStyle(fontSize: 8, color: muted),
        ),

        // ---------------------------------------------------- every expense
        heading('Every expense'),
        if (rows.isEmpty)
          pw.Text('Nothing recorded.',
              style: const pw.TextStyle(fontSize: 11, color: muted))
        else
          pw.TableHelper.fromTextArray(
            headers: ['Date', 'What', 'Paid by', 'Split', 'Amount'],
            data: [
              for (final row in rows)
                [
                  _date(row.at),
                  row.note.isEmpty ? row.category : row.note,
                  nameOf(row.by),
                  // How it was divided, said plainly, because two rows that
                  // look identical can owe completely different things.
                  !row.shared
                      ? 'just theirs'
                      : row.shares.isNotEmpty
                          ? 'set amounts'
                          : row.sharedWith.isNotEmpty
                              ? 'between ${row.sharedWith.length}'
                              : 'everyone',
                  formatRupees(row.paise),
                ]
            ],
            headerStyle: pw.TextStyle(font: bold, fontSize: 9, color: ink),
            cellStyle: const pw.TextStyle(fontSize: 9),
            headerDecoration:
                const pw.BoxDecoration(color: PdfColor.fromInt(0xFFF8FAFC)),
            border: const pw.TableBorder(
              horizontalInside: pw.BorderSide(color: hairline, width: 0.5),
              bottom: pw.BorderSide(color: hairline, width: 0.5),
            ),
            columnWidths: {
              0: const pw.FixedColumnWidth(62),
              1: const pw.FlexColumnWidth(3),
              2: const pw.FlexColumnWidth(1.4),
              3: const pw.FlexColumnWidth(1.2),
              4: const pw.FixedColumnWidth(66),
            },
            headerAlignment: pw.Alignment.centerLeft,
            headerAlignments: {4: pw.Alignment.centerRight},
            cellAlignments: {4: pw.Alignment.centerRight},
            cellPadding:
                const pw.EdgeInsets.symmetric(horizontal: 5, vertical: 4),
          ),
      ],
    ),
  );

  return doc.save();
}
