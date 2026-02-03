// Basic widget test for PRSM Chat app
import 'package:flutter_test/flutter_test.dart';
import 'package:ble_spike/main.dart';

void main() {
  testWidgets('App starts and shows role selection', (WidgetTester tester) async {
    // Build our app and trigger a frame.
    await tester.pumpWidget(const PrsmChatApp());
    await tester.pump();

    // Verify that the app title is shown
    expect(find.text('PRSM Chat'), findsOneWidget);
    
    // Verify that role selection options are mentioned
    expect(find.text('Ende-zu-Ende verschlüsselter BLE-Chat'), findsOneWidget);
  });
}
