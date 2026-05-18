import 'package:flutter_test/flutter_test.dart';
import 'package:masakin/main.dart';
import 'package:masakin/screens/splash_screen.dart';

void main() {
  testWidgets('routes from splash screen to onboarding', (tester) async {
    await tester.pumpWidget(const MasakinApp());

    expect(find.text('MasAkIn'), findsOneWidget);
    expect(find.text('Loading...'), findsOneWidget);

    await tester.pump(SplashScreen.initializationDuration);
    await tester.pumpAndSettle();

    expect(find.text('Scan Bahan\nMasakan'), findsOneWidget);
  });
}
