import 'dart:async';
import 'dart:convert';

import 'package:device_info_plus/device_info_plus.dart';
import 'package:flutter/material.dart';
import 'package:fluttertoast/fluttertoast.dart';
import 'package:http/http.dart' as http;
import 'package:wear_os/globals.dart' as globals;
import 'package:wear_os/networkService.dart' as flask;
import 'package:wear_os/util/loggingclient.dart';

class Recog extends StatefulWidget {
  const Recog({super.key});

  @override
  State<Recog> createState() => _RecogState();
}


class DataPoint {
  final DateTime ts;
  final List<dynamic> values; // the rest of your accel/gyro fields

  DataPoint(this.ts, this.values);
}

class _RecogState extends State<Recog> {
  bool isPredicting = false;
  late flask.NetworkService _net;

    Map<String, dynamic>? ShowWatch;
  List<dynamic>? ShowEsense;
  DateTime? CurrentTime;


  var client = LoggingClient();
    // Queues for raw incoming:
  final List<DataPoint> watchQueue = [];
  final List<DataPoint> esenseQueue = [];

  // Aligned rows ready to write:
  final List<List<dynamic>> alignedBuffer = [];

  static const int kAlignmentThresholdMs = 40;
  static const int kBatchSize = 1;

  // … rest of your fields

// TO ADD TO QUEUES
  Timer? bufferTimer;
  void addToWatchBuffer(dynamic latestWatchData) {
    // 1) Make sure it’s even a Map
    if (latestWatchData == null || latestWatchData is! Map) {
      print('Error: not a Map');
      return;
    }

    // 2) Parse the timestamp (string here)
    final rawTs = latestWatchData['Timestamp'];
    if (rawTs == null) {
      print('Error: missing Timestamp');
      return;
    }
    final ts = DateTime.parse(rawTs.toString());

    // 3) Pull out each sensor map as a raw Map
    final accelRaw = latestWatchData['accelerometer'];
    final gyroRaw = latestWatchData['gyroscope'];

    if (accelRaw is! Map || gyroRaw is! Map) {
      print('Error: one of the sensor entries isn’t a Map');
      return;
    }

    // 4) Cast them into a Map<String,dynamic>
    final accel = (accelRaw as Map).cast<String, dynamic>();
    final gyro = (gyroRaw as Map).cast<String, dynamic>();

    // 5) Flatten into doubles
    final data = <double>[
      (accel['x'] as num).toDouble(),
      (accel['y'] as num).toDouble(),
      (accel['z'] as num).toDouble(),
      (gyro['x'] as num).toDouble(),
      (gyro['y'] as num).toDouble(),
      (gyro['z'] as num).toDouble(),
    ];

    // 6) Enqueue your DataPoint
    final dp = DataPoint(ts, data);
    watchQueue.add(dp);
    _tryAlign();
  }
  double toDouble(dynamic e) {
  if (e is num) {
    // covers both int and double
    return e.toDouble();
  } else if (e is String) {
    // in case it comes in as a numeric string
    return double.parse(e);
  } else {
    throw ArgumentError('Cannot convert $e (${e.runtimeType}) to double');
  }
}

  void addToEsenseBuffer(List<dynamic> latestEsenseData) {
    print('Adding to esense buffer: $latestEsenseData');
    if (latestEsenseData == null || latestEsenseData.isEmpty) {
      print('Error: latestEsenseData is null or empty');
      return;
    }
    final timestamp = DateTime.fromMillisecondsSinceEpoch(latestEsenseData[0]);
    if (timestamp == null) {
      print('Error: unable to convert timestamp to DateTime');
      return;
    }

    final data = <double> [
      (latestEsenseData[1] as num).toDouble(),
      (latestEsenseData[2] as num).toDouble(),
      (latestEsenseData[3] as num).toDouble(),
      (latestEsenseData[4] as num).toDouble(),
      (latestEsenseData[5] as num).toDouble(),
      (latestEsenseData[6] as num).toDouble(),
    ];
    final dp = DataPoint(timestamp, data);
    print('Created DataPoint: $dp');
    esenseQueue.add(dp);
    print('Added to esense queue: $dp');
    _tryAlign();
  }

  int lengthleft = 0;
  void _tryAlign() {
    if (watchQueue.isEmpty || esenseQueue.isEmpty) return;

    print("GOT DATA IN BUFFERS");
    int? matchedWatchIndex;
    int? matchedEsenseIndex;

    for (int i = 0; i < watchQueue.length; i++) {
      final wdp = watchQueue[i];
      for (int j = 0; j < esenseQueue.length; j++) {
        final edp = esenseQueue[j];
        final diffMs = wdp.ts.difference(edp.ts).inMilliseconds.abs();

        if (diffMs <= kAlignmentThresholdMs) {
          print("esense values : ${edp.values}");
          final row = <dynamic>[
            // ++num,
            // dateFormatWithMs.format(DateTime.now()),
            // wdp.ts,
            wdp.values[0],
            wdp.values[1],
            wdp.values[2],
            wdp.values[3],
            wdp.values[4],
            wdp.values[5],
            // edp.ts,
            ...edp.values,
          ];
          final Datarow = <double>[
            // ++num,
            // dateFormatWithMs.format(DateTime.now()),
            // wdp.ts,
            wdp.values[0],
            wdp.values[1],
            wdp.values[2],
            wdp.values[3],
            wdp.values[4],
            wdp.values[5],
            // edp.ts,
            ...edp.values,
          ];
          alignedBuffer.add(row);

          print('About to add to InputWindow; row is: $row');
          print('Types: ${row.map((e) => e.runtimeType).toList()}');
          try {
            InputWindow?.add(Datarow);
          } catch (e, st) {
            print('Cast failed here: $e\n$st');
            rethrow;
          }

          print("✨✨✨✨");
          print("window size: ${InputWindow!.length}");
          if (InputWindow!.length >= 50) {
            setState(()=> lengthleft = 0);
            print("👍👍Buffer filled");
            startPredicting(InputWindow);
            print("Got  prediction❤️‍🔥");
            
            InputWindow?.clear();
          }
          setState(() {
            lengthleft ++;
          });

          matchedWatchIndex = i;
          matchedEsenseIndex = j;
          break;
        }
      }
      if (matchedWatchIndex != null && matchedEsenseIndex != null) break;
    }

    if (matchedWatchIndex != null && matchedEsenseIndex != null) {
      watchQueue.removeAt(matchedWatchIndex);
      esenseQueue.removeAt(matchedEsenseIndex);
      if (alignedBuffer.length >= kBatchSize) _flushAlignedBuffer();
    }

    // Remove stale entries
    final cutoff = DateTime.now().subtract(Duration(seconds: 2));
    watchQueue.removeWhere((d) => d.ts.isBefore(cutoff));
    esenseQueue.removeWhere((d) => d.ts.isBefore(cutoff));
  }

  List<dynamic> alignedRow = [];

  void _flushAlignedBuffer() {
    print(
        '🧪 Buffer Snapshot | watch: ${watchQueue.length} | esense: ${esenseQueue.length}');
    print(
        '🔍 Next watch sample: ${watchQueue.isNotEmpty ? watchQueue.first : 'EMPTY'}');
    print(
        '🔍 Next esense sample: ${esenseQueue.isNotEmpty ? esenseQueue.first : 'EMPTY'}');
    print("🟨 flushAlignedBuffers called");
    while (alignedBuffer.isNotEmpty) {
      alignedRow = alignedBuffer.removeAt(0);
      
    }
  }

  List<List<double>>? InputWindow = [];
  List<List<double>>? Input1 = [];
  List<List<double>>? Input2 = [];
  Timer? PredictionTimer;
  String? labelPredicted;
  double? confidencePredicted;
  int Windowsize = 50;
  List<double>? _prediction;

  // ignore: non_constant_identifier_names
List<String> Activity_classes = [
   "Sitting + Typing on Desk",
   "Sitting + Taking Notes", 
   "Standing + Writing on Whiteboard",
   "Standing + Erasing Whiteboard",
   "Sitting + Talking + Waving Hands",
  "Standing + Talking + Waving Hands",
   "Sitting + Drinking Water",
   "Sitting + Drinking Coffee",
   "Standing + Drinking Water",
   "Standing + Drinking Coffee",
   "Scrolling on Phone",
];

String predictedActivity = "Null";
int maxidx = 0;
int max = 0;
String? _attentionStatus;

  void startPredicting(List<List<double>>? InputWindow) async {
  

  final flatInput = InputWindow?.expand((row) => row).toList();

  // Ensure flatInput is not null before passing to fetchPrediction
  if (flatInput == null) {
    Fluttertoast.showToast(msg: "Input data is null.");
    return;
  }
  print("Sending to server🚀🚀🚀: $flatInput");

  final response = await _net.fetchPrediction(flatInput, globals.Model!);
  final preds = response[0];
  // final label = await _net.fetchPrediction(flatInput);
  print("💫💫💫predictions: ${preds}");

  // --- Corrected logic to find maxidx ---
  if (preds.isEmpty) {
    // Handle the case where predictions list might be empty
    Fluttertoast.showToast(msg: "No predictions received.");
    return;
  }

  double maxVal = preds[0]; // Initialize maxVal with the first prediction
         // Initialize maxIdx with the index of the first prediction

  for (int i = 1; i < preds.length; i++) { // Start from the second element
    if (preds[i] > maxVal) {
      maxVal = preds[i];
      maxidx = i;
    }
  }
  // --- End of corrected logic ---

  setState(() {
    _prediction = preds;
    predictedActivity =  preds[maxidx] > 0.6 ? Activity_classes[maxidx] : "Transition" ; // Use the correctly found maxIdx
    _attentionStatus = response[1];
  });
}



DeviceInfoPlugin? devicePlugin;
AndroidDeviceInfo? info;

  void initState(){
    super.initState();
    _net  = flask.NetworkService("http://10.6.0.56:5500");
    initAsync();

  }

  void initAsync() async{
devicePlugin = await  DeviceInfoPlugin();
info = await devicePlugin?.androidInfo;
globals.Model = info!.model;
  }

double? attentionPercent;

void onStopPredicting() async {
    

   
      setState(() {
        ShowEsense = null;
        ShowWatch = null;
      });
      if(InputWindow!.isNotEmpty) InputWindow!.clear();
      lengthleft = 0;
      predictedActivity = "null";
      _attentionStatus = null;
      _prediction = null;
      attentionPercent = null;
      bufferTimer?.cancel();

      final resp = await client.post(
        Uri.parse("http://10.6.0.56:5500/end_meeting")
  ,
  headers: {
    'Content-Type': 'application/json',
    'Cache-Control': 'no-cache',
    'Pragma': 'no-cache',
  },
  body: jsonEncode({'user_id': globals.Model}), 
);
      final response = jsonDecode(resp.body);
      print("⬇️⬇️⬇️⬇️ $response['attentive_percent']");
      setState(() {
        attentionPercent = response['attentive_percent'];
      });
      // watchBuffer.clear();
      // esenseBuffer.clear();
      Fluttertoast.showToast(msg: "Predicting stopped");

      if(response!= null){
      
      showSuggestion(context, response["suggestion"]);
      }
  }

  void toggleStart(){
    if(isPredicting == false){
      isPredicting = true;
      onStart();
    }
    else if(isPredicting == true){
      isPredicting = false;
      onStopPredicting();
    }
  }

  void onStart() async {
     
     Fluttertoast.showToast(msg: "Prediction started");
    
      print("BUFFERS TO BE STARTED BEING FILLED");
      initIMU();
    
  }

  void initIMU() {
    bufferTimer = Timer.periodic(const Duration(milliseconds: 100), (_) {
      try {
        setState(() {
          ShowWatch = globals.globallatestWatchData;
          ShowEsense = globals.gloaballatestEsenseData;
          CurrentTime = DateTime.now();
        });

        // void AddToBuffer
        if (globals.globallatestWatchData.isNotEmpty) {
          addToWatchBuffer(globals.globallatestWatchData);
        }

        if (globals.gloaballatestEsenseData.isNotEmpty) {
          addToEsenseBuffer(globals.gloaballatestEsenseData);
        }
      } catch (e, st) {
        print("Error in buffer loop: $e\n$st");
      }
    });
  }


  Future<void> showSuggestion(
BuildContext context,
 String message,
) {
  return showGeneralDialog<void>(
    context: context,
    barrierDismissible: true,
    barrierLabel: 'Suggestion Dialog',
    barrierColor: Colors.black54,
    transitionDuration: const Duration(milliseconds: 300),
    pageBuilder: (ctx, anim1, anim2) => Center(
      child: SingleChildScrollView(
        child: Dialog(
          insetPadding: const EdgeInsets.all(5),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(8),
          ),
          child: ConstrainedBox(
            constraints: BoxConstraints(
              maxWidth: MediaQuery.of(ctx).size.width - 20,
              maxHeight: MediaQuery.of(ctx).size.height - 100,
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // Top bar with close button
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.only(right: 4, top: 4),
                  child: Align(
                    alignment: Alignment.topRight,
                    child: IconButton(
                      icon: const Icon(Icons.close),
                      onPressed: () => Navigator.of(ctx).pop(),
                    ),
                  ),
                ),

                const SizedBox(height: 8),
                Container(
              padding: const EdgeInsets.all(16.0), // inner spacing
              decoration: BoxDecoration(
                color: Colors.white, // background color
                border: Border.all(
                  color: const Color.fromARGB(255, 242, 40, 195), // outline color
                  width: 2.0, // outline thickness
                ),
                borderRadius:
                    BorderRadius.circular(12), // circular corners (12px radius)
              ),
              child: Text(
                'Attention Percent: ${"$attentionPercent %" ?? "Nothing predicted"}',
                style: TextStyle(color: const Color.fromARGB(255, 242, 40, 195)),
              ),
            ),
                SizedBox(height: 20,),

                // Your scrollable message
                Expanded(
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    child: Text(
                      "Suggestion: $message",
                      style: const TextStyle(fontSize: 15),
                    ),
                  ),
                ),

                const SizedBox(height: 16),

                // Optional OK button
                TextButton(
                  onPressed: () => Navigator.of(ctx).pop(),
                  child: const Text('Close'),
                ),
              ],
            ),
          ),
        ),
      ),
    ),
    transitionBuilder: (ctx, anim, secAnim, child) {
      final fade = CurvedAnimation(parent: anim, curve: Curves.easeOut);
      final scale = CurvedAnimation(parent: anim, curve: Curves.elasticOut);
      return FadeTransition(
        opacity: fade,
        child: ScaleTransition(
          scale: scale,
          child: child,
        ),
      );
    },
  );
}




  @override
  Widget build(BuildContext context) {
    return SafeArea(
        child: Column(
          
      children: [
        SizedBox(
              height: 20,
            ),
            Container(
              padding: const EdgeInsets.all(16.0), // inner spacing
              decoration: BoxDecoration(
                color: Colors.white, // background color
                border: Border.all(
                  color: Colors.purple, // outline color
                  width: 2.0, // outline thickness
                ),
                borderRadius:
                    BorderRadius.circular(12), // circular corners (12px radius)
              ),
              child: Text(
                'Predicted : ${"$predictedActivity" ?? "Nothing predicted"}',
                style: TextStyle(color: Colors.purple),
              ),
            ),
            SizedBox(height: 20,),
            Container(
              padding: const EdgeInsets.all(16.0), // inner spacing
              decoration: BoxDecoration(
                color: Colors.white, // background color
                border: Border.all(
                  color: const Color.fromARGB(255, 39, 98, 176), // outline color
                  width: 2.0, // outline thickness
                ),
                borderRadius:
                    BorderRadius.circular(12), // circular corners (12px radius)
              ),
              child: Text(
                'Attention State: ${"$_attentionStatus" ?? "Nothing predicted"}',
                style: TextStyle(color: const Color.fromARGB(255, 39, 117, 176)),
              ),
            ),
            SizedBox(height: 20,),
            Container(
              padding: const EdgeInsets.all(16.0), // inner spacing
              decoration: BoxDecoration(
                color: Colors.white, // background color
                border: Border.all(
                  color: const Color.fromARGB(255, 242, 40, 195), // outline color
                  width: 2.0, // outline thickness
                ),
                borderRadius:
                    BorderRadius.circular(12), // circular corners (12px radius)
              ),
              child: Text(
                'Attention Percent: ${"$attentionPercent %" ?? "Nothing predicted"}',
                style: TextStyle(color: const Color.fromARGB(255, 242, 40, 195)),
              ),
            ),
            SizedBox(height: 20,),
            Container(
              height: MediaQuery.sizeOf(context).height*0.3,
              width: MediaQuery.sizeOf(context).width-0.7,
              decoration: BoxDecoration(border: Border.all()),
              child: SingleChildScrollView(
                child: Column(
                  children: [
                    Text("Probabilities: $_prediction"),
            Text("Window Size: $lengthleft"),
            const SizedBox(height: 20),
            ConstrainedBox(
      constraints: const BoxConstraints(
        maxHeight: 100, 
        // the maximum height of your scrollable window
      ),
      child: Container(
        decoration: BoxDecoration(
          border: Border.all(color: Colors.grey),
          borderRadius: BorderRadius.circular(8),
        ),
        clipBehavior: Clip.hardEdge,  // hide anything outside
        child: SingleChildScrollView(
            child: Column(
              children: [Text("Watch Data: ${ShowWatch.toString()}"), Text("eSense Data: ${ShowEsense.toString() ?? 'No data'}"), ],
            ),
          
        ),
      ),
    ),
            
            Text("Latency Tolerance: $kAlignmentThresholdMs"),
            Text("Current Time: ${CurrentTime}"),
            Text("Model Name: ${globals.Model}"),
                  ],
                ),
              ),
            ),
            SizedBox(
              height: 40,
            ),
        ElevatedButton(
          onPressed: toggleStart,
          child: isPredicting
              ? Text(
                  "Stop",
                  style: TextStyle(
                    color: Colors.white,
                  ),
                )
              : Text("Start", style: TextStyle(color: Colors.white)),
          style: ElevatedButton.styleFrom(
            backgroundColor: isPredicting
                ? Color.fromARGB(255, 240, 105, 105)
                : Color.fromARGB(255, 77, 221, 94),
            shape: const CircleBorder(),
            padding: const EdgeInsets.all(50),
          ),
        ),

        
      ],
    ));
  }
}
