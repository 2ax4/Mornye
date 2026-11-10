import 'download_pipeline_performance_test.dart' as downloads;
import 'library_pipeline_performance_test.dart' as library_pipeline;
import 'performance_probe.dart';
import 'playback_pipeline_performance_test.dart' as playback;

void main() {
  PerformanceTestBinding.ensureInitialized();
  library_pipeline.main();
  downloads.main();
  playback.main();
}
