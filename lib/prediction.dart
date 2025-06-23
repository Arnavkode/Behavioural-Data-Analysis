import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:csv/csv.dart';
import 'package:fluttertoast/fluttertoast.dart';
import 'package:hive/hive.dart';
import 'package:media_scanner/media_scanner.dart';
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:rxdart/rxdart.dart';
import 'package:watch_connectivity/watch_connectivity.dart';
import 'package:wear_os/globals.dart' as globals;
import 'package:intl/intl.dart';

class ActivityRecog extends StatefulWidget {
  const ActivityRecog({Key? key}) : super(key: key);

  @override
  State<ActivityRecog> createState() => _ActivityRecogState();
}

class _ActivityRecogState extends State<ActivityRecog>
    with AutomaticKeepAliveClientMixin {
  bool get wantKeepAlive => true;
  bool useFilter = false;
  Map<String, dynamic> watchData = {};
  dynamic esenseData;
  File? filewBuffer;
  File? filewoBuffer;
  Directory? dir;
  bool fileCreated = false;
  int counter = 0;

  final myBox = Hive.box('myBox');
  StreamSubscription<dynamic>? watchStreamSubscription;
  StreamSubscription<dynamic>? esenseStreamSubscription;
  StreamSubscription<void>? writesubscription;
  final dateFormatWithMs = DateFormat('yyyy-MM-dd HH:mm:ss.SSS');

  @override
  void initState() {
    super.initState();
    initAsync();
    initWatch();
    initEsense();
  }

  @override
  void dispose() {
    writesubscription?.cancel();
    watchStreamSubscription?.cancel();
    esenseStreamSubscription?.cancel();
    globals.stopDatalistUpdates();
    super.dispose();
  }

  Future<void> initAsync() async {
    requestStoragePermission();
    dir = await getDownloadsDirectory();
    counter = myBox.get('counter', defaultValue: 0);
  }

  void initWatch() {
    watchStreamSubscription = globals.watchDataStream.listen((data) {
      if (!mounted) return;
      setState(() {
        watchData = data;
      });
    });
  }

  Future<void> requestStoragePermission() async {
    var status = await Permission.storage.status;
    if (!status.isGranted) {
      await Permission.storage.request();
    }
  }

  void initEsense() {
    globals.startDatalistUpdates();
    esenseStreamSubscription =
        globals.EdatalistStream.sampleTime(const Duration(milliseconds: 100))
            .listen((data) {
      if (!mounted) return;
      setState(() {
        esenseData = data;
      });
    });
  }

  int num = 0;
  int num1 = 0;




  // MAKE FILE FOR FOR DATA WITHOUT BUFFER

  Future<void> makeFilewoBuffer() async {
    if (dir == null) return;

    filewoBuffer = File('${dir!.path}/combinedwoBuffer$counter.csv');
    List<String> labels = [
      "id",
      "ActualTime",
      'WatchTimeStamp',
      'Ax watch',
      'Ay watch',
      'Az watch',
      'Gx watch',
      'Gy watch',
      'Gz watch',
      'Esense TimeStamp',
      'Ax esense',
      'Ay esense',
      'Az esense',
      'Gx esense',
      'Gy esense',
      'Gz esense',
    ];
    String header = ListToCsvConverter().convert([labels], eol: '\r\n');
    num = 0;
    try {
      await filewoBuffer!.writeAsString(header, mode: FileMode.write);
      fileCreated = true;
      myBox.put('counter', ++counter);
    } catch (_) {
      fileCreated = false;
    }
  }

  Future<void> makeFile() async {
    if (dir == null) return;

    filewBuffer = File('${dir!.path}/combined$counter.csv');
    List<String> labels = [
      "id",
      "ActualTime",
      'WatchTimeStamp',
      'Ax watch',
      'Ay watch',
      'Az watch',
      'Gx watch',
      'Gy watch',
      'Gz watch',
      'Esense TimeStamp',
      'Ax esense',
      'Ay esense',
      'Az esense',
      'Gx esense',
      'Gy esense',
      'Gz esense',
      'TimeDifference_ms' 
    ];
    String header = ListToCsvConverter().convert([labels], eol: '\r\n');
    num = 0;
    try {
      await filewBuffer!.writeAsString(header, mode: FileMode.write);
      fileCreated = true;
      myBox.put('counter', ++counter);
    } catch (_) {
      fileCreated = false;
    }
  }

  // BUFFER latest watch data - MAP<STRING,DYNAMIC>

  List<List<dynamic>> watchBuffer = [];
  List<List<dynamic>> esenseBuffer = [];
  Timer? bufferTimer;
  Timer? MaintainTimer;
  bool recordingStarted = false;
  bool isAligned = false;

  /// Buffer first 10 entries of each source and align them once
  void startAndAlignBuffersOnce() {
    isAligned = false;
    int i = 0;

    bufferTimer = Timer.periodic(const Duration(milliseconds: 100), (_) {
      final w = globals.globallatestWatchData;
      final e = globals.gloaballatestEsenseData;

      // Format timestamps to human-readable form
      final formattedWatchTime =
          dateFormatWithMs.format(DateTime.fromMillisecondsSinceEpoch(
        // w['Timestamp'] ?? DateTime.now().millisecondsSinceEpoch),
        w["Timestamp"],
      ));

      final formattedEsenseTime = (e.isNotEmpty && e[0] is int) //CHECKS FOR EMPTY ENTRIES AND IF THE UNIT IS IN EPOCHS
          ? dateFormatWithMs.format(DateTime.fromMillisecondsSinceEpoch(e[0]))
          : '_';

      watchBuffer.add([
        formattedWatchTime,
        w['accelerometer']?['x'] ?? '_',
        w['accelerometer']?['y'] ?? '_',
        w['accelerometer']?['z'] ?? '_',
        w['gyroscope']?['x'] ?? '_',
        w['gyroscope']?['y'] ?? '_',
        w['gyroscope']?['z'] ?? '_',
      ]);

      esenseBuffer.add([formattedEsenseTime, ...e.sublist(1)]);

      if (bufferTimer!.tick >= 10) {
        bufferTimer?.cancel();
        print("🛑 Stopped after 1 second");

        // // FOR WHEN THE WATCH EVENT HAS TO BE BEFORE THE ESENSE EVENT
        // while (i < watchBuffer.length &&
        //     watchBuffer[i][0].compareTo(esenseBuffer[0][0]) < 0) {
        //   ++i;
        // }

        // FOR ABSOLUTELY CLOSEST EVENT
        DateTime esenseTime = dateFormatWithMs.parse(esenseBuffer[0][0]);

// Find index of closest watch timestamp to esense timestamp
        int closestIndex = 0;
        Duration minDiff = Duration(days: 9999); // arbitrarily large

        for (int j = 0; j < watchBuffer.length; j++) {
          DateTime watchTime = dateFormatWithMs.parse(watchBuffer[j][0]);
          Duration diff = watchTime.difference(esenseTime).abs();
          if (diff < minDiff) {
            minDiff = diff;
            closestIndex = j;
          }
        }

        watchBuffer = watchBuffer.sublist(i);
        isAligned = true;

        // ✅ start writing to CSV
      }
    });

    Buffermaintain();
  }

  void Buffermaintain() {
    int? lastWatchTimestamp;
    int? lastEsenseTimestamp;

    MaintainTimer = Timer.periodic(const Duration(milliseconds: 100), (_) {
      final w = globals.globallatestWatchData;
      final e = globals.gloaballatestEsenseData;

      int currentWatchTimestamp = w['Timestamp'] is int
          ? w['Timestamp']
          : DateTime.now().millisecondsSinceEpoch;

      // ✅ Format watch timestamp
      final formattedWatchTime = dateFormatWithMs
          .format(DateTime.fromMillisecondsSinceEpoch(currentWatchTimestamp));

      if (currentWatchTimestamp != lastWatchTimestamp) {
        watchBuffer.add([
          formattedWatchTime,
          w['accelerometer']?['x'] ?? '_',
          w['accelerometer']?['y'] ?? '_',
          w['accelerometer']?['z'] ?? '_',
          w['gyroscope']?['x'] ?? '_',
          w['gyroscope']?['y'] ?? '_',
          w['gyroscope']?['z'] ?? '_',
        ]);
        lastWatchTimestamp = currentWatchTimestamp;
      }

      if (e.isNotEmpty && e[0] is int && e[0] != lastEsenseTimestamp) {
        final formattedEsenseTime =
            dateFormatWithMs.format(DateTime.fromMillisecondsSinceEpoch(e[0]));

        esenseBuffer.add([
          formattedEsenseTime,
          ...e.sublist(1),
        ]);
        lastEsenseTimestamp = e[0];
      }
    });

    // ✅ CSV writing starts after alignment
    onStartRecording();
  }

  // WRITE TO CSV WITHOUT BUFFER

  void writeToCsvwithoutBuffer() async {
  if (filewoBuffer == null) return;

  List<dynamic> watch = globals.globallatestWatchData.isNotEmpty
      ? [
          ++num1,
          dateFormatWithMs.format(DateTime.now()),
          globals.globallatestWatchData['Timestamp'],
          globals.globallatestWatchData['accelerometer']?['x'] ?? '_',
          globals.globallatestWatchData['accelerometer']?['y'] ?? '_',
          globals.globallatestWatchData['accelerometer']?['z'] ?? '_',
          globals.globallatestWatchData['gyroscope']?['x'] ?? '_',
          globals.globallatestWatchData['gyroscope']?['y'] ?? '_',
          globals.globallatestWatchData['gyroscope']?['z'] ?? '_',
        ]
      : List.filled(7, '_');

  List<dynamic> rawEsense = globals.gloaballatestEsenseData.map((v) => v ?? '_').toList();

  // Convert first value (timestamp) to ISO 8601 if it is a valid int
  if (rawEsense.isNotEmpty && rawEsense[0] is int) {
    int epoch = rawEsense[0];
    rawEsense[0] = DateTime.fromMillisecondsSinceEpoch(epoch).toIso8601String();
  }

  String row = ListToCsvConverter().convert([watch + rawEsense]);

  if (await filewoBuffer!.length() > 0) {
    row = '\n$row';
  }

  await filewoBuffer!.writeAsString(row, mode: FileMode.append);
} 

  void writeToCsv() async {
    if (filewBuffer == null) return;

    // Default to "_" values if buffer is empty
    List<dynamic> watch = watchBuffer.isNotEmpty
        ? watchBuffer.removeAt(0)
        : List.filled(7, '_'); // 7 watch fields (timestamp + 6 axes)

    List<dynamic> esense = esenseBuffer.isNotEmpty
        ? esenseBuffer.removeAt(0)
        : List.filled(7, '_'); // 7 esense fields (timestamp + 6 axes)

    // Construct the row
    List<dynamic> row = [
      ++num,
      DateFormat('yyyy-MM-dd HH:mm:ss.SSS').format(DateTime.now()),
      ...watch,
      ...esense,
    ];

    // Format esense timestamp if present and valid
    if (esense[0] is int) {
      row[10] =
          DateTime.fromMillisecondsSinceEpoch(esense[0]).toIso8601String();
    }

    String line = ListToCsvConverter().convert([row]);
    if (await filewBuffer!.length() > 0) {
      line = '\n$line';
    }

    try {
      await filewBuffer!.writeAsString(line, mode: FileMode.append);
      print("✅ Row written to CSV");
    } catch (e) {
      print("❌ Error writing row: $e");
    }
  }

  Future<void> copyCsvToPublicDownloads() async {
  if (filewBuffer == null || filewoBuffer == null) return;

  final destDir = Directory('/storage/emulated/0/Download');
  if (!(await destDir.exists())) {
    await destDir.create(recursive: true);
  }

  final destFileWithBuffer =
      File('${destDir.path}/${filewBuffer!.uri.pathSegments.last}');
  final destFileWithoutBuffer =
      File('${destDir.path}/${filewoBuffer!.uri.pathSegments.last}');

  try {
    await filewBuffer!.copy(destFileWithBuffer.path);
    await filewoBuffer!.copy(destFileWithoutBuffer.path);

    await MediaScanner.loadMedia(path: destFileWithBuffer.path);
    await MediaScanner.loadMedia(path: destFileWithoutBuffer.path);
  } catch (e) {
    print("Failed to copy file: $e");
  }
}


  void OnStart() {
    startAndAlignBuffersOnce();
  }

  void onStartRecording() async {
    await makeFile();
    await makeFilewoBuffer();
    Fluttertoast.showToast(msg: "Buffer successful & Started Recording");
    writesubscription = Stream.periodic(const Duration(milliseconds: 100))
        .listen((_){
          writeToCsv();
          writeToCsvwithoutBuffer();
        });
  }

  void onStopRecording() async {
    writesubscription?.cancel();
    writesubscription = null;
    MaintainTimer?.cancel();
    await copyCsvToPublicDownloads();
    watchBuffer.clear();
    esenseBuffer.clear();
    Fluttertoast.showToast(msg: "Recording stopped and CSV copied.");
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    return Scaffold(
      body: Center(
        child: Column(
          children: [
            const SizedBox(height: 20),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Text('Use Filter'),
                Switch(
                  value: useFilter,
                  onChanged: (val) => setState(() => useFilter = val),
                ),
                const Text('Don\'t Use Filter'),
              ],
            ),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                ElevatedButton(
                  onPressed: OnStart,
                  child: const Text('Start Recording',
                      style: TextStyle(color: Colors.white)),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color.fromARGB(255, 105, 240, 121),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(5)),
                  ),
                ),
                const SizedBox(width: 20),
                ElevatedButton(
                  onPressed: onStopRecording,
                  child: const Text('Stop Recording',
                      style: TextStyle(color: Colors.white)),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color.fromARGB(255, 240, 105, 105),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(5)),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 20),
            Text("Directory: ${dir?.path ?? 'Loading...'}"),
            Text("Watch Data: ${watchData.toString()}"),
            Text(
                "eSense Data: ${globals.gloaballatestEsenseData.toString() ?? 'No data'}"),
            Text(isAligned ? "Aligned" : "no"),
          ],
        ),
      ),
    );
  }
}
