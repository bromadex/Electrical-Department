import 'package:electrical_department/tools/issue_form_pdf.dart';
import 'package:electrical_department/tools/issue_forms_repository.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('a tool issue form makes a PDF, also with tools still out', () async {
    final form = IssueForm.fromJson({
      'id': 'f1',
      'site_id': 's1',
      'code': 'TI-0001',
      'issued_at': '2026-10-27T08:00:00Z',
      'recipient_name': 'Tinashe Mademe',
      'recipient_role': 'Electrician',
      'company': 'Manhattan',
      'team_lead': 'Elia Manjawu',
      'status': 'part_returned',
      'lines': [
        {
          'tool_id': 't1',
          'qty': 1,
          'issue_condition': 'good',
          'returned_at': '2026-10-28T08:00:00Z',
          'return_condition': 'damaged',
          'return_note': 'Jaw cracked',
          'tool': {
            'code': 'T-0001',
            'name': 'Fluke True-RMS Clamp Meter',
            'serial_no': '67510984WS',
          },
        },
        {
          'tool_id': 't2',
          'qty': 2,
          'issue_condition': 'needs_repair',
          'tool': {'code': 'T-0002', 'name': 'Ingco Padlock'},
        },
      ],
    });
    expect(form.out, 1);
    expect(form.returned, isFalse);
    final bytes = await buildIssueFormPdf(
      form: form,
      siteName: 'Kamativi',
      issuedByName: 'Store Keeper',
      receivedBackByName: null,
      signatures: const {},
    );
    expect(String.fromCharCodes(bytes.take(4)), '%PDF');
  });
}
