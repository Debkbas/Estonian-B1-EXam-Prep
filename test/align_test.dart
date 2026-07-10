import 'package:flutter_test/flutter_test.dart';
import 'package:rada/domain/align.dart';

void main() {
  test('normalize strips punctuation and case', () {
    expect(normalizeWords('Tere! Kuidas läheb?'), ['tere', 'kuidas', 'läheb']);
  });

  test('perfect match', () {
    expect(alignScore('Ma õpin eesti keelt.', 'ma õpin eesti keelt'), 1.0);
  });

  test('one wrong word', () {
    final s = alignScore('Ma õpin eesti keelt', 'ma õpin soome keelt');
    expect(s, closeTo(0.75, 0.001));
  });

  test('empty heard = 0', () {
    expect(alignScore('Tere hommikust', ''), 0.0);
  });

  test('order matters (LCS, not bag of words)', () {
    final matched =
        alignWords(['üks', 'kaks', 'kolm'], ['kolm', 'kaks', 'üks']);
    expect(matched.where((m) => m).length, 1);
  });
}
