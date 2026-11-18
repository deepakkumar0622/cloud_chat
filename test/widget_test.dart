import 'package:flutter_test/flutter_test.dart';
import 'package:cloud_chat/main.dart';

void main() {
  testWidgets('Cloud Chat app initializes', (WidgetTester tester) async {
    // Basic test that verifies the root widget can be created.
    const app = CloudChatApp();

    expect(app, isA<CloudChatApp>());
  });
}