/// Spec §6.2 — STT interface. macOS impl (whisper.cpp FFI with
/// whisper-large-et GGML) lands in M3; Android hub mode in M5.
abstract class SttService {
  Future<String> transcribe(String audioFilePath);
}

class UnimplementedStt implements SttService {
  @override
  Future<String> transcribe(String audioFilePath) async =>
      throw UnimplementedError('STT arrives in M3 (spec §11).');
}
