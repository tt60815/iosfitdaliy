// 建議在 pubspec.yaml 加入：
//   sqflite: ^2.2.8
//   path: ^1.8.3
//   image_picker: ^0.8.7
//   timeline_tile: ^2.0.0
// 並在 AndroidManifest.xml / Info.plist 中設定拍照/檔案權限

import 'package:flutter/material.dart';
import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart' as path_provider;
import 'package:image_picker/image_picker.dart';
import 'dart:io';
import 'dart:math';
import 'package:timeline_tile/timeline_tile.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:fluttertoast/fluttertoast.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';
import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:geolocator/geolocator.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:intl/intl.dart';
import 'package:in_app_purchase/in_app_purchase.dart';
// --------------------------------------------------
// Database helper class
// --------------------------------------------------
class DatabaseHelper {
  static final DatabaseHelper instance = DatabaseHelper._init();
  static Database? _database;

  DatabaseHelper._init();

  Future<Database> get database async {
    if (_database != null) return _database!;
    _database = await _initDB('fitness.db');
    return _database!;
  }

  Future<Database> _initDB(String filePath) async {
    final dbPath = await getDatabasesPath();
    final path = path_provider.join(dbPath, filePath);

    // 確保資料夾存在
    await Directory(dbPath).create(recursive: true);

    // 除錯用：印出資料庫路徑
    print('Database path: $path');

    return await openDatabase(
      path,
      version: 1,
      onCreate: _createDB,
      onOpen: (db) async {
        await _verifyTables(db);
      },
    );
  }

  // 建立資料表
  Future _createDB(Database db, int version) async {

    await db.execute('''
  CREATE TABLE IF NOT EXISTS exercise_records(
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    date TEXT,
    time TEXT,
    exercise_type TEXT,
    duration INTEGER,  -- 分鐘數
    calories_burned INTEGER,
    note TEXT
  )
''');
    try {
      // user_profile
      await db.execute('''
        CREATE TABLE IF NOT EXISTS user_profile (
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          name TEXT,
          gender TEXT,
          birthday TEXT,
          height INTEGER,
          weight INTEGER,
          target_weight INTEGER
        )
      ''');

      // weight_records
      await db.execute('''
        CREATE TABLE IF NOT EXISTS weight_records(
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          date TEXT,
          time TEXT,
          weight REAL,
          body_fat REAL
        )
      ''');

      // calories_records
      await db.execute('''
        CREATE TABLE IF NOT EXISTS calories_records(
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          date TEXT,
          time TEXT,
          calories INTEGER,
           protein REAL,
    carbs REAL,
    fat REAL,
          meal TEXT,
          description TEXT,
          image_path TEXT
        )
      ''');

      // water_records
      await db.execute('''
        CREATE TABLE IF NOT EXISTS water_records(
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          date TEXT,
          time TEXT,
          amount INTEGER,
          note TEXT
        )
      ''');

       // 添加跑步路線表
  await db.execute('''
    CREATE TABLE IF NOT EXISTS run_routes(
      id TEXT PRIMARY KEY,
      date TEXT,
      coordinates TEXT,
      distance REAL
    )
  ''');

      print('All tables created successfully');
    } catch (e) {
      print('Error creating tables: $e');
      rethrow;
    }
  }
// 在 DatabaseHelper 類中添加跑步路線相關方法
Future<void> insertRunRoute(RunRoute route) async {
  try {
    final db = await database;
    await db.insert('run_routes', {
      'id': route.id,
      'date': route.date.toIso8601String(),
      'coordinates': jsonEncode(route.coordinates.map((c) => {
        'latitude': c.latitude,
        'longitude': c.longitude,
      }).toList()),
      'distance': route.distance,
    });
  } catch (e) {
    print('Error inserting run route: $e');
    rethrow;
  }
}

Future<List<RunRoute>> getRunRoutes() async {
  try {
    final db = await database;
    final records = await db.query('run_routes', orderBy: 'date DESC');
    return records.map((record) {
      final coordinates = (jsonDecode(record['coordinates'] as String) as List)
          .map((c) => LatLng(c['latitude'], c['longitude']))
          .toList();

      return RunRoute(
        id: record['id'] as String,
        date: DateTime.parse(record['date'] as String),
        coordinates: coordinates,
        distance: record['distance'] as double,
      );
    }).toList();
  } catch (e) {
    print('Error getting run routes: $e');
    return [];
  }
}

  // 驗證資料表是否存在
  Future<void> _verifyTables(Database db) async {
    try {
      var tables =
          await db.rawQuery("SELECT name FROM sqlite_master WHERE type='table'");
      print('Tables in database: $tables');

      // 確保必要的表存在，若不存在就重新建立
      if (!tables.any((table) => table['name'] == 'weight_records')) {
        await _createDB(db, 1);
      }
    } catch (e) {
      print('Error verifying tables: $e');
      rethrow;
    }
  }

  // -------------------- user_profile --------------------
  Future<void> saveUserProfile({
    required String name,
    required String gender,
    required DateTime birthday,
    required int height,
    required int weight,
    required int targetWeight,
  }) async {
    try {
      final db = await database;
      // 先刪除舊紀錄，只存一筆
      await db.delete('user_profile');
      // 插入新紀錄
      await db.insert('user_profile', {
        'name': name,
        'gender': gender,
        'birthday': birthday.toIso8601String(),
        'height': height,
        'weight': weight,
        'target_weight': targetWeight,
      });
      print('User profile saved successfully');
    } catch (e) {
      print('Error saving user profile: $e');
      rethrow;
    }
  }

  Future<Map<String, dynamic>?> getUserProfile() async {
    try {
      final db = await database;
      final List<Map<String, dynamic>> maps = await db.query('user_profile');
      if (maps.isEmpty) return null;
      return maps.first;
    } catch (e) {
      print('Error getting user profile: $e');
      rethrow;
    }
  }

  // -------------------- weight_records --------------------
  Future<void> insertWeightRecord(Map<String, dynamic> record) async {
    try {
      final db = await database;
      await db.insert('weight_records', record);
    } catch (e) {
      print('Error inserting weight record: $e');
      rethrow;
    }
  }

  Future<List<Map<String, dynamic>>> getWeightRecords() async {
    try {
      final db = await database;
      return await db.query('weight_records', orderBy: 'date DESC, time DESC');
    } catch (e) {
      print('Error getting weight records: $e');
      rethrow;
    }
  }

  // -------------------- calories_records --------------------
  Future<void> insertCaloriesRecord(Map<String, dynamic> record) async {
    try {
      final db = await database;
      await db.insert('calories_records', record);
    } catch (e) {
      print('Error inserting calories record: $e');
      rethrow;
    }
  }

  Future<List<Map<String, dynamic>>> getCaloriesRecords() async {
    try {
      final db = await database;
      return await db.query('calories_records', orderBy: 'date DESC, time DESC');
    } catch (e) {
      print('Error getting calories records: $e');
      rethrow;
    }
  }

  // -------------------- water_records --------------------
  Future<void> insertWaterRecord(Map<String, dynamic> record) async {
    try {
      final db = await database;
      await db.insert('water_records', record);
    } catch (e) {
      print('Error inserting water record: $e');
      rethrow;
    }
  }

  Future<List<Map<String, dynamic>>> getWaterRecords() async {
    try {
      final db = await database;
      return await db.query('water_records', orderBy: 'date DESC, time DESC');
    } catch (e) {
      print('Error getting water records: $e');
      rethrow;
    }
  }


  Future<Map<String, dynamic>?> getLatestWeightRecord() async {
  final db = await database;
  final result = await db.query(
    'weight_records',
    orderBy: 'date DESC, time DESC',
    limit: 1,
  );
  return result.isNotEmpty ? result.first : null;
}

Future<Map<String, dynamic>?> getLatestCaloriesRecord() async {
  final db = await database;
  final result = await db.query(
    'calories_records',
    orderBy: 'date DESC, time DESC',
    limit: 1,
  );
  return result.isNotEmpty ? result.first : null;
}

Future<Map<String, dynamic>?> getLatestWaterRecord() async {
  final db = await database;
  final result = await db.query(
    'water_records',
    orderBy: 'date DESC, time DESC',
    limit: 1,
  );
  return result.isNotEmpty ? result.first : null;
}

Future<void> insertExerciseRecord(Map<String, dynamic> record) async {
  try {
    final db = await database;
    await db.insert('exercise_records', record);
  } catch (e) {
    print('Error inserting exercise record: $e');
    rethrow;
  }
}

Future<List<Map<String, dynamic>>> getExerciseRecords() async {
  try {
    final db = await database;
    return await db.query('exercise_records', orderBy: 'date DESC, time DESC');
  } catch (e) {
    print('Error getting exercise records: $e');
    rethrow;
  }
}

Future<Map<String, dynamic>?> getLatestExerciseRecord() async {
  final db = await database;
  final result = await db.query(
    'exercise_records',
    orderBy: 'date DESC, time DESC',
    limit: 1,
  );
  return result.isNotEmpty ? result.first : null;
}
}
 
// --------------------------------------------------
// Main application
// --------------------------------------------------
// void main() {
//   WidgetsFlutterBinding.ensureInitialized();
//   AwesomeNotifications().initialize(
//     null,
//     [
//       NotificationChannel(
//         channelKey: 'fitness_reminders',
//         channelName: 'Fitness Reminders',
//         channelDescription: 'Notification channel for fitness reminders',
//         defaultColor: Color(0xFF7DAAB6),
//         ledColor: Colors.white,
//         importance: NotificationImportance.High,
//       )
//     ],
//   );
//   runApp(MyApp());
// }
void main() async {
  WidgetsFlutterBinding.ensureInitialized();
   await MobileAds.instance.initialize();
  // 初始化資料庫或其他配置
  final initialScreen = await _getInitialScreen();

  runApp(MaterialApp(
    title: 'Fit Daily',
    debugShowCheckedModeBanner: false,
    theme: ThemeData(
      colorScheme: ColorScheme.fromSeed(seedColor: MyApp.primaryColor),
      useMaterial3: true,
    ),
    home: initialScreen, // 根據檢查結果設置初始畫面
  ));
}

Future<Widget> _getInitialScreen() async {
  try {
    final userProfile = await DatabaseHelper.instance.getUserProfile();
    if (userProfile != null) {
      // 已有資料 -> 進入 HomeScreen
      return HomeScreen();
    } else {
      // 無資料 -> 進入 LoginScreen（包含 Google 登入與條款打勾）
      return LoginScreen();
    }
  } catch (e) {
    print('Error during initial screen check: $e');
    // 如果發生錯誤，回到登入畫面
    return LoginScreen();
  }
}
class MyApp extends StatelessWidget {
  static const primaryColor = Color(0xFF7DAAB6);
  static const secondaryColor = Color(0xFF9CBEC3);

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Fit Daily',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: primaryColor),
        useMaterial3: true,
      ),
      home: LoginScreen(),
    );
  }
}
 
 class LoginScreen extends StatelessWidget {
 final GoogleSignIn _googleSignIn = GoogleSignIn(
  scopes: ['email', 'profile'],
  clientId: Platform.isIOS
      ? '599090774181-1rm6tg8t2eqa5g1s2hng5etu9uevtphm.apps.googleusercontent.com'  // iOS 的 clientId
      : '599090774181-db855virbaurhemr46sk84b2ih5nf6ju.apps.googleusercontent.com', // Android 的 clientId
);
  Future<void> _checkAndNavigate(BuildContext context, String? userName) async {
    try {
      final userProfile = await DatabaseHelper.instance.getUserProfile();
      if (userProfile != null) {
        // 已經有資料 -> 進入 HomeScreen
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(builder: (_) => HomeScreen()),
        );
      } else {
     // 無資料 -> 進入 OnboardingScreen，並傳遞名稱
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(builder: (_) => OnboardingScreen(userName: userName)),
      );
      }
    } catch (e) {
      print('Error checking user profile: $e');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error checking user profile')),
      );
    }
  }

  Future<void> _handleSignIn(BuildContext context) async {
    try {
      // 顯示 Terms & Privacy Dialog
      // bool acceptedTerms = await _showTermsDialog(context);
      // if (!acceptedTerms) {
    
      //   return;
      // }

      // bool acceptedPrivacy = await _showPrivacyDialog(context);
      // if (!acceptedPrivacy) {
      
      //   return;
      // }
        Navigator.pushReplacement(
      context,
      MaterialPageRoute(builder: (_) => OnboardingScreen(userName: 'Guest')),
    );
     return;
final GoogleSignInAccount? googleUser = await _googleSignIn.signIn();
if (googleUser == null) {
  print('Sign in aborted by user');
  return;
}

final GoogleSignInAuthentication googleAuth = await googleUser.authentication;

// 顯示使用者信息
ScaffoldMessenger.of(context).showSnackBar(
  SnackBar(
    content: Text(
      'Email: ${googleUser.email}, Name: ${googleUser.displayName}, Photo: ${googleUser.photoUrl ?? "No photo"}',
    ),
  ),
);
final userName = googleUser.displayName ?? 'Guest'; // 獲取 Google 使用者名稱

    // 呼叫 _checkAndNavigate，並傳遞名稱
    await _checkAndNavigate(context, userName);
// 使用原本的 _checkAndNavigate 來處理導航
 

    } catch (error) {
      print('Sign in error: $error');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Login failed: $error')),
      );
    }
  }

  // 新增：顯示使用者條款 Dialog
  Future<bool> _showTermsDialog(BuildContext context) async {
    bool isChecked = false;

    final result = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (context, setState) {
            return AlertDialog(
              title: Text('Terms of Use'),
              content: SingleChildScrollView(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                Text('')
   
,
                    SizedBox(height: 20),
                    Row(
                      children: [
                        Checkbox(
                          value: isChecked,
                          onChanged: (value) {
                            setState(() {
                              isChecked = value ?? false;
                            });
                          },
                        ),
                        Expanded(child: Text('I agree to the Terms of Use')),
                      ],
                    ),
                  ],
                ),
              ),
              actions: [
                // TextButton(
                //   onPressed: () => Navigator.of(ctx).pop(false), // 拒絕
                //   child: Text('Decline'),
                // ),
                ElevatedButton(
                  onPressed: isChecked ? () => Navigator.of(ctx).pop(true) : null, // 接受
                  child: Text('Accept'),
                ),
              ],
            );
          },
        );
      },
    );
    return result ?? false;
  }

  // 新增：顯示隱私政策 Dialog
  Future<bool> _showPrivacyDialog(BuildContext context) async {
    bool isChecked = false;

    final result = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (context, setState) {
            return AlertDialog(
              title: Text('Privacy Policy'),
              content: SingleChildScrollView(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                Text(
  ' '
)
,
                    SizedBox(height: 21),
                    Row(
                      children: [
                        Checkbox(
                          value: isChecked,
                          onChanged: (value) {
                            setState(() {
                              isChecked = value ?? false;
                            });
                          },
                        ),
                        Expanded(child: Text('I agree to the Privacy Policy')),
                      ],
                    ),
                  ],
                ),
              ),
              actions: [
                // TextButton(
                //   onPressed: () => Navigator.of(ctx).pop(false), // 拒絕
                //   child: Text('Decline'),
                // ),
                ElevatedButton(
                  onPressed: isChecked ? () => Navigator.of(ctx).pop(true) : null, // 接受
                  child: Text('Accept'),
                ),
              ],
            );
          },
        );
      },
    );
    return result ?? false;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
         
            SizedBox(height: 30),
            ElevatedButton.icon(
              onPressed: () => _handleSignIn(context),
             
              label: Text("Start Fit Daily!"),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.white,
                foregroundColor: Colors.black87,
                minimumSize: Size(220, 50),
                side: BorderSide(color: Colors.black12),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(4),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}



// 跑步路線數據模型
class RunRoute {
  final String id;
  final DateTime date;
  final List<LatLng> coordinates;
  final double distance; // 公里

  RunRoute({
    required this.id,
    required this.date,
    required this.coordinates,
    required this.distance,
  });

  // 轉換為JSON格式存儲
  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'date': date.millisecondsSinceEpoch,
      'coordinates': coordinates.map((coord) => {
            'latitude': coord.latitude,
            'longitude': coord.longitude,
          }).toList(),
      'distance': distance,
    };
  }

  // 從JSON格式轉換
  factory RunRoute.fromJson(Map<String, dynamic> json) {
    return RunRoute(
      id: json['id'],
      date: DateTime.fromMillisecondsSinceEpoch(json['date']),
      coordinates: (json['coordinates'] as List).map((coord) {
        return LatLng(coord['latitude'], coord['longitude']);
      }).toList(),
      distance: json['distance'],
    );
  }
}

// 路線記錄頁面
class RunRoutesScreen extends StatefulWidget {
  @override
  _RunRoutesScreenState createState() => _RunRoutesScreenState();
}

class _RunRoutesScreenState extends State<RunRoutesScreen> {
  List<RunRoute> _routes = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadRoutes();
    _addTestDataIfEmpty();
  }

  Future<void> _loadRoutes() async {
    try {
      setState(() => _isLoading = true);
      final routes = await DatabaseHelper.instance.getRunRoutes();
      setState(() {
        _routes = routes;
        _isLoading = false;
      });
    } catch (e) {
      print('加載路線時出錯: $e');
      setState(() => _isLoading = false);
    }
  }

 // 添加台灣測試數據
void _addTestDataIfEmpty() async {
  if (_routes.isEmpty) {
    try {
      // 先檢查測試路線是否已存在
      final db = await DatabaseHelper.instance.database;
      final existingRoute = await db.query(
        'run_routes',
        where: 'id = ?',
        whereArgs: ['test-route-20250105'],
      );

      // 如果測試路線不存在，才添加
      if (existingRoute.isEmpty) {
        // 台北大安森林公園附近的一條路線
        final testRoute = RunRoute(
          id: 'test-route-20250105',
          date: DateTime(2025, 1, 5),
          coordinates: [
            // 大安森林公園附近的路線坐標
            const LatLng(25.033082, 121.534243), // 起點
            const LatLng(25.033703, 121.535209),
            const LatLng(25.034554, 121.536357),
            const LatLng(25.035405, 121.537129),
            const LatLng(25.036041, 121.538116),
            const LatLng(25.036580, 121.539039),
            const LatLng(25.036908, 121.540155),
            const LatLng(25.037139, 121.541313),
            const LatLng(25.037371, 121.542257),
            const LatLng(25.037686, 121.543158),
            const LatLng(25.037939, 121.544060),
            const LatLng(25.038170, 121.544961),
            const LatLng(25.038411, 121.545884),
            const LatLng(25.038652, 121.546785), // 終點
          ],
          distance: 1.75, // 約 1.75 公里
        );
        
        await DatabaseHelper.instance.insertRunRoute(testRoute);
        print('測試路線添加成功');
      } else {
        print('測試路線已存在，跳過添加');
      }
      _loadRoutes(); // 無論是否添加了新記錄，都重新加載路線
    } catch (e) {
      print('添加測試數據時出錯: $e');
    }
  }
}

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('跑步路線記錄'),
      ),
      body: _isLoading
          ? Center(child: CircularProgressIndicator())
          : _routes.isEmpty
              ? Center(child: Text('沒有記錄的路線。點擊下方按鈕開始記錄新路線！'))
              : ListView.builder(
                  itemCount: _routes.length,
                  itemBuilder: (context, index) {
                    final route = _routes[index];
                    return Card(
                      margin: EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                      child: ListTile(
                        leading: Icon(Icons.directions_run, color: Color(0xFF7DAAB6), size: 36),
                        title: Text(
                          DateFormat('yyyy-MM-dd').format(route.date),
                          style: TextStyle(fontWeight: FontWeight.bold),
                        ),
                        subtitle: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text('距離: ${route.distance.toStringAsFixed(2)} 公里'),
                            Text('時間: ${DateFormat('HH:mm').format(route.date)}'),
                          ],
                        ),
                        trailing: Icon(Icons.chevron_right),
                        onTap: () {
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (context) => RouteDetailsScreen(route: route),
                            ),
                          );
                        },
                      ),
                    );
                  },
                ),
      floatingActionButton: FloatingActionButton(
        backgroundColor: Color(0xFF7DAAB6),
        onPressed: () async {
          // 檢查位置權限
          final status = await Permission.location.request();
          if (status.isGranted) {
            final result = await Navigator.push(
              context,
              MaterialPageRoute(
                builder: (context) => RecordRunScreen(),
              ),
            );
            
            if (result != null && result is RunRoute) {
              // 保存新路線
              await DatabaseHelper.instance.insertRunRoute(result);
              _loadRoutes();
            }
          } else {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('需要位置權限才能記錄路線')),
            );
          }
        },
        child: const Icon(Icons.play_arrow),
      ),
    );
  }
}

// 記錄路線頁面
class RecordRunScreen extends StatefulWidget {
  const RecordRunScreen({Key? key}) : super(key: key);

  @override
  State<RecordRunScreen> createState() => _RecordRunScreenState();
}

class _RecordRunScreenState extends State<RecordRunScreen> {
  GoogleMapController? _mapController;
  List<LatLng> _routeCoordinates = [];
  bool _isRecording = false;
  Timer? _locationTimer;
  double _totalDistance = 0.0;
  final Set<Polyline> _polylines = {};
  final Set<Marker> _markers = {};

  @override
  void initState() {
    super.initState();
    _requestLocationPermission();
  }

  @override
  void dispose() {
    _locationTimer?.cancel();
    _mapController?.dispose();
    super.dispose();
  }

  // 請求位置權限
  Future<void> _requestLocationPermission() async {
    final status = await Permission.location.request();
    if (status.isGranted) {
      _getCurrentLocation();
    } else {
      Navigator.pop(context);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('需要位置權限才能記錄路線')),
      );
    }
  }

  // 獲取當前位置
  Future<void> _getCurrentLocation() async {
    try {
      final position = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.high,
      );
      
      final currentLatLng = LatLng(position.latitude, position.longitude);
      
      setState(() {
        _markers.add(
          Marker(
            markerId: const MarkerId('currentLocation'),
            position: currentLatLng,
            icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueAzure),
          ),
        );
      });
      
      _mapController?.animateCamera(
        CameraUpdate.newCameraPosition(
          CameraPosition(
            target: currentLatLng,
            zoom: 16.0,
          ),
        ),
      );
    } catch (e) {
      print('獲取位置時出錯: $e');
    }
  }

  // 開始記錄
  void _startRecording() {
    setState(() {
      _isRecording = true;
      _routeCoordinates = [];
      _totalDistance = 0.0;
      _polylines.clear();
    });

    // 每秒更新位置
    _locationTimer = Timer.periodic(const Duration(seconds: 1), (timer) async {
      try {
        final position = await Geolocator.getCurrentPosition(
          desiredAccuracy: LocationAccuracy.high,
        );
        
        final currentLatLng = LatLng(position.latitude, position.longitude);
        
        setState(() {
          // 添加新坐標點
          _routeCoordinates.add(currentLatLng);
          
          // 更新標記
          _markers.clear();
          _markers.add(
            Marker(
              markerId: const MarkerId('currentLocation'),
              position: currentLatLng,
              icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueAzure),
            ),
          );
          
          // 繪製路線
          _polylines.clear();
          _polylines.add(
            Polyline(
              polylineId: const PolylineId('route'),
              points: _routeCoordinates,
              color: Colors.blue,
              width: 5,
            ),
          );
          
          // 計算總距離
          if (_routeCoordinates.length > 1) {
            final last = _routeCoordinates[_routeCoordinates.length - 2];
            final current = _routeCoordinates.last;
            
            _totalDistance += Geolocator.distanceBetween(
              last.latitude,
              last.longitude,
              current.latitude,
              current.longitude,
            );
          }
        });
        
        // 跟隨當前位置
        _mapController?.animateCamera(
          CameraUpdate.newCameraPosition(
            CameraPosition(
              target: currentLatLng,
              zoom: 16.0,
            ),
          ),
        );
      } catch (e) {
        print('記錄位置時出錯: $e');
      }
    });
  }

  // 結束記錄
  void _stopRecording() {
    _locationTimer?.cancel();

    if (_routeCoordinates.length < 2) {
      setState(() {
        _isRecording = false;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('路線太短，無法保存')),
      );
      return;
    }

    final newRoute = RunRoute(
      id: DateTime.now().millisecondsSinceEpoch.toString(),
      date: DateTime.now(),
      coordinates: List.from(_routeCoordinates),
      distance: _totalDistance / 1000, // 轉換為公里
    );

    setState(() {
      _isRecording = false;
    });

    Navigator.pop(context, newRoute);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('記錄跑步路線'),
      ),
      body: Stack(
        children: [
          GoogleMap(
            initialCameraPosition: const CameraPosition(
              target: LatLng(25.033, 121.565), // 默認位置（台北）
              zoom: 14.0,
            ),
            myLocationEnabled: true,
            myLocationButtonEnabled: true,
            markers: _markers,
            polylines: _polylines,
            onMapCreated: (controller) {
              _mapController = controller;
              _getCurrentLocation();
            },
          ),
          Positioned(
            bottom: 20,
            left: 0,
            right: 0,
            child: Center(
              child: Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(10),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.1),
                      blurRadius: 5,
                      offset: const Offset(0, 3),
                    ),
                  ],
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      '距離: ${(_totalDistance / 1000).toStringAsFixed(2)} 公里',
                      style: const TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 10),
                    ElevatedButton(
                      onPressed: _isRecording ? _stopRecording : _startRecording,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: _isRecording ? Colors.red : Colors.green,
                        padding: const EdgeInsets.symmetric(
                          horizontal: 20,
                          vertical: 12,
                        ),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(_isRecording ? Icons.stop : Icons.play_arrow),
                          const SizedBox(width: 8),
                          Text(_isRecording ? '結束' : '開始'),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// 路線詳情頁面
class RouteDetailsScreen extends StatefulWidget {
  final RunRoute route;

  const RouteDetailsScreen({Key? key, required this.route}) : super(key: key);

  @override
  State<RouteDetailsScreen> createState() => _RouteDetailsScreenState();
}

class _RouteDetailsScreenState extends State<RouteDetailsScreen> {
  GoogleMapController? _mapController;
  final Set<Polyline> _polylines = {};
  final Set<Marker> _markers = {};
  bool _isMapReady = false;

  @override
  void initState() {
    super.initState();
    _setupRouteDisplay();
  }

  void _setupRouteDisplay() {
    try {
      if (widget.route.coordinates.isEmpty) return;

      // 設置起點標記
      final startPoint = widget.route.coordinates.first;
      final endPoint = widget.route.coordinates.last;

      setState(() {
        _markers.add(
          Marker(
            markerId: const MarkerId('start'),
            position: startPoint,
            icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueGreen),
            infoWindow: const InfoWindow(title: '起點'),
          ),
        );

        _markers.add(
          Marker(
            markerId: const MarkerId('end'),
            position: endPoint,
            icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueRed),
            infoWindow: const InfoWindow(title: '終點'),
          ),
        );

        _polylines.add(
          Polyline(
            polylineId: const PolylineId('route'),
            points: widget.route.coordinates,
            color: Colors.blue,
            width: 5,
          ),
        );
      });
    } catch (e) {
      print('設置路線顯示時出錯: $e');
      // 顯示錯誤對話框，這樣用戶至少能看到錯誤信息而不是程序崩潰
      WidgetsBinding.instance.addPostFrameCallback((_) {
        showDialog(
          context: context,
          builder: (ctx) => AlertDialog(
            title: Text('顯示路線時出錯'),
            content: Text('$e'),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(ctx).pop(),
                child: Text('確定'),
              ),
            ],
          ),
        );
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(DateFormat('yyyy-MM-dd').format(widget.route.date)),
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(16.0),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(Icons.straighten, color: Colors.blue),
                const SizedBox(width: 8),
                Text(
                  '距離: ${widget.route.distance.toStringAsFixed(2)} 公里',
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
          ),
          Expanded(
            child: GoogleMap(
              initialCameraPosition: CameraPosition(
                target: widget.route.coordinates.isNotEmpty
                    ? widget.route.coordinates.first
                    : const LatLng(25.033, 121.565), // 默認位置（台北）
                zoom: 14.0,
              ),
              markers: _markers,
              polylines: _polylines,
              onMapCreated: (controller) {
                _mapController = controller;
                _isMapReady = true;
                
                // 使用 Future.delayed 給地圖一點時間加載
                Future.delayed(Duration(milliseconds: 500), () {
                  if (_isMapReady && mounted && widget.route.coordinates.isNotEmpty) {
                    try {
                      // 計算路線的邊界
                      final bounds = _calculateBounds(widget.route.coordinates);
                      _mapController?.animateCamera(
                        CameraUpdate.newLatLngBounds(bounds, 50),
                      );
                    } catch (e) {
                      print('設置地圖相機時出錯: $e');
                    }
                  }
                });
              },
            ),
          ),
        ],
      ),
    );
  }

  // 計算路線的邊界，添加錯誤處理
  LatLngBounds _calculateBounds(List<LatLng> coordinates) {
    if (coordinates.isEmpty) {
      // 如果沒有坐標，返回台北的固定邊界
      return LatLngBounds(
        southwest: const LatLng(25.01, 121.53),
        northeast: const LatLng(25.06, 121.56),
      );
    }

    double minLat = coordinates.first.latitude;
    double maxLat = coordinates.first.latitude;
    double minLng = coordinates.first.longitude;
    double maxLng = coordinates.first.longitude;

    for (final coord in coordinates) {
      if (coord.latitude < minLat) minLat = coord.latitude;
      if (coord.latitude > maxLat) maxLat = coord.latitude;
      if (coord.longitude < minLng) minLng = coord.longitude;
      if (coord.longitude > maxLng) maxLng = coord.longitude;
    }

    // 確保邊界有一定大小，避免單點或過小範圍
    if ((maxLat - minLat).abs() < 0.001) {
      maxLat += 0.001;
      minLat -= 0.001;
    }
    if ((maxLng - minLng).abs() < 0.001) {
      maxLng += 0.001;
      minLng -= 0.001;
    }

    return LatLngBounds(
      southwest: LatLng(minLat, minLng),
      northeast: LatLng(maxLat, maxLng),
    );
  }
}
/*
  流程共七頁：
  1. Name
  2. Gender
  3. Birthday
  4. Height
  5. Weight
  6. Target Weight
  7. BMR & BMI Evaluation
*/
// --------------------------------------------------
// OnboardingScreen
// --------------------------------------------------
class OnboardingScreen extends StatefulWidget {
  final String? userName; // 新增 userName 成員

  OnboardingScreen({this.userName}); // 修改建構函式，接收 userName

  @override
  _OnboardingScreenState createState() => _OnboardingScreenState();
}

/*
  流程共七頁：
  1. Name
  2. Gender
  3. Birthday
  4. Height
  5. Weight
  6. Target Weight
  7. BMR & BMI Evaluation
*/
class _OnboardingScreenState extends State<OnboardingScreen> {
  int currentPage = 0;
   

      @override
  void initState() {
    super.initState();
    userName = widget.userName ?? ''; // 使用 widget.userName 初始化
  }


  final PageController _controller = PageController(initialPage: 0);

  String? userName;
  String? selectedGender;     // 'Male' or 'Female'
  DateTime? selectedDate;     // 生日
  int? selectedHeight = 170;  // 身高
  int? selectedWeight = 60;   // 體重
  int? selectedTargetWeight = 55; // 目標體重

  // 存檔：把填寫的資料存到 DB
  Future<void> _saveUserData() async {
    try {
      if (userName == null ||
          selectedGender == null ||
          selectedDate == null ||
          selectedHeight == null ||
          selectedWeight == null ||
          selectedTargetWeight == null) {
        return;
      }
      await DatabaseHelper.instance.saveUserProfile(
        name: userName!,
        gender: selectedGender!,
        birthday: selectedDate!,
        height: selectedHeight!,
        weight: selectedWeight!,
        targetWeight: selectedTargetWeight!,
      );
    } catch (e) {
      print('Error saving user data: $e');
    }
  }

  // 計算 BMR (Mifflin-St Jeor)
  // 男: BMR = 10*kg + 6.25*cm - 5*age + 5
  // 女: BMR = 10*kg + 6.25*cm - 5*age - 161
  double _calculateBMR() {
    if (selectedGender == null ||
        selectedWeight == null ||
        selectedHeight == null ||
        selectedDate == null) {
      return 0.0;
    }
    final now = DateTime.now();
    int age = now.year - selectedDate!.year;
    // 若尚未過生日 -> age--
    if (now.month < selectedDate!.month ||
        (now.month == selectedDate!.month && now.day < selectedDate!.day)) {
      age--;
    }

    double bmr;
    if (selectedGender == 'Male') {
      bmr = (10 * selectedWeight!) +
          (6.25 * selectedHeight!) -
          (5 * age) +
          5;
    } else {
      bmr = (10 * selectedWeight!) +
          (6.25 * selectedHeight!) -
          (5 * age) -
          161;
    }
    return bmr;
  }

  // 計算 BMI = kg / (m^2)
  double _calculateBMI() {
    if (selectedWeight == null || selectedHeight == null) {
      return 0.0;
    }
    final heightM = selectedHeight! / 100.0;
    return selectedWeight! / (heightM * heightM);
  }

  void _goToNextPage() {
    _controller.nextPage(
      duration: Duration(milliseconds: 500),
      curve: Curves.ease,
    );
  }

  void _goToPreviousPage() {
    _controller.previousPage(
      duration: Duration(milliseconds: 500),
      curve: Curves.ease,
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: PageView(
        controller: _controller,
        onPageChanged: (int page) => setState(() => currentPage = page),
        children: [
          _buildNamePage(),
          _buildGenderPage(),
          _buildBirthdayPage(),
          _buildHeightPage(),
          _buildWeightPage(),
          _buildTargetWeightPage(),      // 新增的第6頁：目標體重
          _buildBmrBmiEvaluationPage(),  // 新增的第7頁：BMR & BMI 評估
        ],
      ),
      bottomSheet: currentPage < 6
          ? Container(
              height: 60,
              color: MyApp.primaryColor,
              width: double.infinity,
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  if (currentPage > 0)
                    TextButton(
                      onPressed: _goToPreviousPage,
                      child: Text('Back',
                          style: TextStyle(color: Colors.white, fontSize: 20)),
                    ),
                  if (currentPage > 0)
                  TextButton(
                    onPressed: _goToNextPage,
                    child: Text('Next',
                        style: TextStyle(color: Colors.white, fontSize: 20)),
                  ),
                ],
              ),
            )
          : Container(
              height: 60,
              color: MyApp.primaryColor,
              width: double.infinity,
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  TextButton(
                    onPressed: _goToPreviousPage,
                    child: Text('Back',
                        style: TextStyle(color: Colors.white, fontSize: 20)),
                  ),
                  TextButton(
                    onPressed: () async {
                      // 按下「開始計畫」 -> 存檔 -> 進入主頁
                      await _saveUserData();
                      Navigator.pushReplacement(
                        context,
                        MaterialPageRoute(builder: (_) => HomeScreen()),
                      );
                    },
                    child: Text('Start',
                        style: TextStyle(color: Colors.white, fontSize: 20)),
                  ),
                ],
              ),
            ),
    );
  }Widget _buildNamePage() {
  String tempName = userName ?? ''; // 用於臨時儲存輸入值

  return Center(
    child: Padding(
      padding: const EdgeInsets.symmetric(horizontal: 40),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.person, size: 100, color: MyApp.primaryColor),
          SizedBox(height: 30),
          Text(
            'Enter your name',
            style: TextStyle(fontSize: 28, fontWeight: FontWeight.bold),
          ),
          SizedBox(height: 30),
          TextField(
            decoration: InputDecoration(
              labelText: 'Name',
              border: OutlineInputBorder(),
              hintText: userName ?? 'Enter your name', // 顯示初始值作為提示
            ),
            onChanged: (value) {
              tempName = value; // 更新臨時變數
            },
          ),
          SizedBox(height: 16),
          ElevatedButton(
            onPressed: () {
              setState(() {
                userName = tempName.trim(); // 更新 userName
              });
              _goToNextPage();
            },
            child: Text('Next'),
          ),
        ],
      ),
    ),
  );
}

  // 第 2 頁：Gender
  Widget _buildGenderPage() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text('Select Gender',
              style: TextStyle(fontSize: 28, fontWeight: FontWeight.bold)),
          SizedBox(height: 30),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              _genderIcon(Icons.male, 'Male'),
              SizedBox(width: 50),
              _genderIcon(Icons.female, 'Female'),
            ],
          ),
        ],
      ),
    );
  }

  Widget _genderIcon(IconData icon, String gender) {
    final isSelected = (selectedGender == gender);
    return GestureDetector(
      onTap: () {
        setState(() => selectedGender = gender);
        _goToNextPage();
      },
      child: Column(
        children: [
          Icon(icon,
              size: 100,
              color: isSelected ? MyApp.primaryColor : Colors.grey),
          Text(gender, style: TextStyle(fontSize: 20)),
        ],
      ),
    );
  }

  // 第 3 頁：Birthday
  Widget _buildBirthdayPage() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.cake, size: 100, color: MyApp.primaryColor),
          SizedBox(height: 30),
          Text('Select Birthday',
              style: TextStyle(fontSize: 28, fontWeight: FontWeight.bold)),
          SizedBox(height: 30),
          GestureDetector(
            onTap: () async {
              DateTime? date = await showDatePicker(
                context: context,
                initialDate: DateTime(2000),
                firstDate: DateTime(1900),
                lastDate: DateTime.now(),
              );
              if (date != null) {
                setState(() => selectedDate = date);
                _goToNextPage();
              }
            },
            child: Container(
              padding: EdgeInsets.symmetric(vertical: 15, horizontal: 20),
              decoration: BoxDecoration(
                border: Border.all(color: MyApp.primaryColor),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                selectedDate == null
                    ? 'Tap to select'
                    : '${selectedDate!.year}-${selectedDate!.month.toString().padLeft(2, '0')}-${selectedDate!.day.toString().padLeft(2, '0')}',
                style: TextStyle(fontSize: 20),
              ),
            ),
          ),
        ],
      ),
    );
  }

  // 第 4 頁：Height
  Widget _buildHeightPage() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.height, size: 100, color: MyApp.primaryColor),
          SizedBox(height: 30),
          Text('Select Height',
              style: TextStyle(fontSize: 28, fontWeight: FontWeight.bold)),
          SizedBox(height: 30),
          SizedBox(
            height: 150,
            child: ListWheelScrollView(
              itemExtent: 50,
              physics: FixedExtentScrollPhysics(),
              onSelectedItemChanged: (index) {
                setState(() => selectedHeight = 100 + index); // 100 ~ 220
              },
              children: List.generate(121, (index) {
                return Center(
                  child: Text('${100 + index} cm', style: TextStyle(fontSize: 20)),
                );
              }),
            ),
          ),
        ],
      ),
    );
  }

  // 第 5 頁：Weight
  Widget _buildWeightPage() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.monitor_weight, size: 100, color: MyApp.primaryColor),
          SizedBox(height: 30),
          Text('Select Weight',
              style: TextStyle(fontSize: 28, fontWeight: FontWeight.bold)),
          SizedBox(height: 30),
          SizedBox(
            height: 150,
            child: ListWheelScrollView(
              itemExtent: 50,
              physics: FixedExtentScrollPhysics(),
              onSelectedItemChanged: (index) {
                setState(() => selectedWeight = 30 + index); // 30 ~ 150
              },
              children: List.generate(121, (index) {
                return Center(
                  child: Text('${30 + index} kg', style: TextStyle(fontSize: 20)),
                );
              }),
            ),
          ),
        ],
      ),
    );
  }

  // 第 6 頁：Target Weight
  Widget _buildTargetWeightPage() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.flag, size: 100, color: MyApp.primaryColor),
          SizedBox(height: 30),
          Text('Select Target Weight',
              style: TextStyle(fontSize: 28, fontWeight: FontWeight.bold)),
          SizedBox(height: 30),
          SizedBox(
            height: 150,
            child: ListWheelScrollView(
              itemExtent: 50,
              physics: FixedExtentScrollPhysics(),
              onSelectedItemChanged: (index) {
                setState(() => selectedTargetWeight = 30 + index); // 30~150
              },
              children: List.generate(121, (index) {
                return Center(
                  child: Text('${30 + index} kg', style: TextStyle(fontSize: 20)),
                );
              }),
            ),
          ),
        ],
      ),
    );
  }

  // 第 7 頁：BMR & BMI 評估
  Widget _buildBmrBmiEvaluationPage() {
    final bmrValue = _calculateBMR();
    final bmiValue = _calculateBMI();

    // 根據 BMI 判斷簡易文字
    String bmiStatusText;
    if (bmiValue < 18.5) {
      bmiStatusText = '(Underweight)';
    } else if (bmiValue < 25) {
      bmiStatusText = ' (Normal)';
    } else if (bmiValue < 30) {
      bmiStatusText = ' (Overweight)';
    } else {
      bmiStatusText = ' (Obesity)';
    }

    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 20),
        child: SingleChildScrollView(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.assessment, size: 100, color: MyApp.primaryColor),
              SizedBox(height: 30),
              Text('BMR & BMI Evaluation',
                  style: TextStyle(fontSize: 28, fontWeight: FontWeight.bold)),
              SizedBox(height: 30),
              // 顯示使用者目前輸入
              Text(
                'Data currently entered：\n'
                'Height：${selectedHeight ?? 0} cm\n'
                'Weight：${selectedWeight ?? 0} kg\n'
                'Target weight：${selectedTargetWeight ?? 0} kg',
                style: TextStyle(fontSize: 18, height: 1.4),
                textAlign: TextAlign.center,
              ),
              SizedBox(height: 10),
              // 顯示 BMR、BMI 以及 BMI 狀態文字
              Text(
                'BMR：${bmrValue.toStringAsFixed(1)} kcal/day\n'
                'BMI：${bmiValue.toStringAsFixed(1)}\n'
                '$bmiStatusText',
                style: TextStyle(fontSize: 18, height: 1.4, color: Colors.red),
                textAlign: TextAlign.center,
              ),
              SizedBox(height: 20),
              // 半圓儀表板
              SizedBox(
                width: 300,
                height: 150, // 半圓
                child: CustomPaint(
                  painter: BmiGaugePainter(bmiValue),
                ),
              ),
              SizedBox(height: 20),
              // BMI 圖例
              _buildBmiLegendRow(),
              Divider(thickness: 1),
              SizedBox(height: 10),
              Text(
                'Start',
                style: TextStyle(fontSize: 16, color: Colors.grey[600]),
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      ),
    );
  }

  // 在儀表板下方的「區段」圖例
  Widget _buildBmiLegendRow() {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceAround,
      children: [
        _legendItem(Icons.sentiment_dissatisfied, 'Underweight'),
        _legendItem(Icons.sentiment_satisfied, 'Normal'),
        _legendItem(Icons.sentiment_neutral, 'Overweight'),
        _legendItem(Icons.sentiment_very_dissatisfied, 'Obesity'),
      ],
    );
  }

  Widget _legendItem(IconData iconData, String label) {
    return Column(
      children: [
        Icon(iconData, size: 30, color: Colors.blueGrey),
        SizedBox(height: 4),
        Text(label, style: TextStyle(fontSize: 14)),
      ],
    );
  }
}


// --------------------------------------------------
// HomeScreen（含底部導航）
// --------------------------------------------------
class HomeScreen extends StatefulWidget {
  @override
  _HomeScreenState createState() => _HomeScreenState();
}

 
class _HomeScreenState extends State<HomeScreen> with WidgetsBindingObserver {
  int _selectedIndex = 0;
  BannerAd? _bannerAd;
  bool _isAdLoaded = false;
  bool _isError = false;
  String _errorMessage = '';

  final List<Widget> _widgetOptions = <Widget>[
    HomePageWithSummary(),  // 首頁
    TimelinePage(),         // Timeline
    RecordOptionsPage(),    // 紀錄選單頁
    ProfilePage(),          // 個人資料
    SettingsScreen(),       // 設定頁面
  ];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _createBannerAd();
    _checkAndInitializeNotifications();
  }

  @override
  void dispose() {
    _bannerAd?.dispose();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  // 處理應用生命週期變化
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      // 應用回到前台時重新加載廣告
      if (_bannerAd == null || _isError) {
        _createBannerAd();
      }
    }
  }

  // 初始化通知
  Future<void> _checkAndInitializeNotifications() async {
   
  }

  // 創建橫幅廣告
  void _createBannerAd() {
    setState(() => _isError = false);
    
    print('Starting to create banner ad...'); // Debug log
    _bannerAd = BannerAd(
      size: AdSize.banner,
      adUnitId: Platform.isAndroid 
          ? 'ca-app-pub-6422295172788813/4986337051'  // Android test ID
          : 'ca-app-pub-6422295172788813/7709430637',  // iOS test ID
      listener: BannerAdListener(
        onAdLoaded: (ad) {
          print('Ad loaded successfully!');
          setState(() {
            _isAdLoaded = true;
            _isError = false;
          });
          _showMessage('welcome');
        },
        onAdFailedToLoad: (ad, error) {
          print('Ad failed to load: $error');
          ad.dispose();
          setState(() {
            _isAdLoaded = false;
            _isError = true;
            _errorMessage = error.message;
          });
          _showMessage('welcome: ${error.message}', isError: true);
        },
        onAdOpened: (ad) => print('Ad opened'),
        onAdClosed: (ad) => print('Ad closed'),
        onAdWillDismissScreen: (ad) => print('Ad will dismiss'),
        onAdImpression: (ad) => print('Ad impression'),
      ),
      request: AdRequest(),
    );

    print('Attempting to load banner ad...');
    _bannerAd?.load();
  }

  // 顯示消息提示
  void _showMessage(String message, {bool isError = false}) {
    if (!mounted) return;
    
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: isError ? Colors.red : Colors.green,
        duration: Duration(seconds: isError ? 5 : 3),
        action: isError ? SnackBarAction(
          label: '重試',
          textColor: Colors.white,
          onPressed: _createBannerAd,
        ) : null,
      ),
    );
  }

  void _onItemTapped(int index) {
    setState(() => _selectedIndex = index);
  }

  // 構建錯誤提示widget
  Widget _buildErrorWidget() {
    return Container(
      padding: EdgeInsets.all(8),
      color: Colors.red.shade100,
      child: Row(
        children: [
          Icon(Icons.error_outline, color: Colors.red),
          SizedBox(width: 8),
          Expanded(
            child: Text(
              '廣告載入失敗: $_errorMessage',
              style: TextStyle(color: Colors.red),
            ),
          ),
          TextButton(
            onPressed: _createBannerAd,
            child: Text('重試'),
            style: TextButton.styleFrom(
              foregroundColor: Colors.red,
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('Fit Daily'),
        actions: [
          IconButton(
            icon: Icon(Icons.notifications),
            onPressed: () async {
              // 檢查通知權限
              
            },
          ),
          // 添加設置按鈕
          IconButton(
            icon: Icon(Icons.refresh),
            onPressed: _createBannerAd,
            tooltip: '重新載入廣告',
          ),
        ],
      ),
      body: Column(
        children: [
          // 主要內容區域
          Expanded(
            child: _widgetOptions.elementAt(_selectedIndex),
          ),
          // 錯誤提示
          if (_isError) _buildErrorWidget(),
          // 廣告區域
          if (_isAdLoaded && _bannerAd != null)
            Container(
              child: AdWidget(ad: _bannerAd!),
              width: _bannerAd!.size.width.toDouble(),
              height: _bannerAd!.size.height.toDouble(),
              alignment: Alignment.center,
            ),
        ],
      ),
      bottomNavigationBar: BottomNavigationBar(
        type: BottomNavigationBarType.fixed,
        currentIndex: _selectedIndex,
        selectedItemColor: MyApp.primaryColor,
        unselectedItemColor: MyApp.secondaryColor,
        onTap: _onItemTapped,
        items: [
          BottomNavigationBarItem(
            icon: Icon(Icons.home),
            label: 'Home',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.timeline),
            label: 'Timeline',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.add_circle_outline),
            label: 'Record',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.person),
            label: 'Profile',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.settings),
            label: 'Settings',
          ),
        ],
      ),
    );
  }
}
// --------------------------------------------------
// HomePageWithSummary
// --------------------------------------------------
class HomePageWithSummary extends StatelessWidget {
  final DatabaseHelper dbHelper = DatabaseHelper.instance;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(16.0),
      child: FutureBuilder(
        future: _fetchLatestData(),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return Center(child: CircularProgressIndicator());
          } else if (snapshot.hasError) {
            return Center(child: Text('Error loading data'));
          } else if (snapshot.data == null || (snapshot.data as Map<String, dynamic>).isEmpty) {
            return Center(child: Text('No data available'));
          } else {
            final data = snapshot.data as Map<String, dynamic>;
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Today\'s Summary',
                  style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
                ),
                SizedBox(height: 10),
                GridView.count(
                  shrinkWrap: true,
                  crossAxisCount: 2,
                  crossAxisSpacing: 10,
                  mainAxisSpacing: 10,
                  children: [
                    _buildSummaryCard('Weight', '${data['weight']} kg', Icons.monitor_weight),
                    _buildSummaryCard('Body Fat', '${data['body_fat']}%', Icons.accessibility_new),
                    _buildSummaryCard('Meal', '${data['calories']} kcal', Icons.fastfood),
                    _buildSummaryCard('Water', '${data['water']} ml', Icons.water_drop),
                    _buildSummaryCard('Exercise', '${data['exercise_calories']} kcal', Icons.fitness_center),
                  ],
                ),
              ],
            );
          }
        },
      ),
    );
  }

Future<Map<String, dynamic>> _fetchLatestData() async {
  final weightRecord = await dbHelper.getLatestWeightRecord();
  final caloriesRecord = await dbHelper.getLatestCaloriesRecord();
  final waterRecord = await dbHelper.getLatestWaterRecord();
  final exerciseRecord = await dbHelper.getLatestExerciseRecord();

  return {
    'weight': weightRecord?['weight'] ?? '-',
    'body_fat': weightRecord?['body_fat'] ?? '-',
    'calories': caloriesRecord?['calories'] ?? '-',
    'water': waterRecord?['amount'] ?? '-',
    'exercise_calories': exerciseRecord?['calories_burned'] ?? '-',
  };
}

  Widget _buildSummaryCard(String title, String value, IconData icon) {
    return Card(
      elevation: 4,
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          
          Icon(icon, size: 50, color: MyApp.primaryColor),
          SizedBox(height: 10),
          Text(title, style: TextStyle(fontWeight: FontWeight.bold, fontSize: 22)),
          SizedBox(height: 5),
          Text(value, style: TextStyle(fontSize: 18, color: Colors.grey[700])),
        ],
      ),
    );
  }
}

// --------------------------------------------------
// ProfilePage
// --------------------------------------------------
class ProfilePage extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return FutureBuilder<Map<String, dynamic>?>(
      future: DatabaseHelper.instance.getUserProfile(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return Center(child: CircularProgressIndicator());
        }
        if (!snapshot.hasData || snapshot.data == null) {
          return Center(child: Text('No profile data'));
        }

        final data = snapshot.data!;
        final birthday = DateTime.parse(data['birthday']);
        final birthdayStr =
            '${birthday.year}-${birthday.month.toString().padLeft(2, '0')}-${birthday.day.toString().padLeft(2, '0')}';

        return Padding(
          padding: const EdgeInsets.all(16.0),
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Profile',
                    style:
                        TextStyle(fontSize: 24, fontWeight: FontWeight.bold)),
                SizedBox(height: 20),
                _buildProfileItem('Name', data['name']),
                _buildProfileItem('Gender', data['gender']),
                _buildProfileItem('Birthday', birthdayStr),
                _buildProfileItem('Height', '${data['height']} cm'),
                _buildProfileItem('Weight', '${data['weight']} kg'),
                _buildProfileItem('Target Weight', '${data['target_weight']} kg'),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildProfileItem(String label, String value) {
    return Container(
      padding: EdgeInsets.symmetric(vertical: 12),
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: Colors.grey.shade300)),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: TextStyle(fontSize: 16, color: Colors.grey[600])),
          Text(value, style: TextStyle(fontSize: 16, fontWeight: FontWeight.w500)),
        ],
      ),
    );
  }
}

// --------------------------------------------------
// RecordOptionsPage
// --------------------------------------------------
class RecordOptionsPage extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.all(16.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('Record Types',
              style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold)),
          SizedBox(height: 20),
          Expanded(
            child: ListView(
              children: [
                _buildOptionCard(
                  context,
                  'Weight & Body Fat Records',
                  Icons.monitor_weight,
                  'Track your weight and Body fat measurements',
                  () => Navigator.push(
                    context,
                    MaterialPageRoute(builder: (_) => WeightWaistRecordPage()),
                  ),
                ),
                SizedBox(height: 16),
                _buildOptionCard(
                  context,
                  'Meal Records',
                  Icons.fastfood,  
                  'Track your calorie intake',
                  () => Navigator.push(
                    context,
                    MaterialPageRoute(builder: (_) => CaloriesRecordPage()),
                  ),
                ),
                SizedBox(height: 16),
                _buildOptionCard(
                  context,
                  'Water Records',
                  Icons.water_drop,
                  'Track your daily water intake',
                  () => Navigator.push(
                    context,
                    MaterialPageRoute(builder: (_) => WaterRecordPage()),
                  ),
                ),
                SizedBox(height: 16),
_buildOptionCard(
  context,
  'Exercise Records',
  Icons.fitness_center,
  'Track your exercise activities',
  () => Navigator.push(
    context,
    MaterialPageRoute(builder: (_) => ExerciseRecordPage()),
  ),
),

SizedBox(height: 16),
_buildOptionCard(
  context,
  'Running Route Records',
  Icons.directions_run,
  'Track your running routes on map',
  () => Navigator.push(
    context,
    MaterialPageRoute(builder: (_) => RunRoutesScreen()),
  ),
),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildOptionCard(
    BuildContext context,
    String title,
    IconData icon,
    String description,
    VoidCallback onTap,
  ) {
    return Card(
      elevation: 4,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(20.0),
          child: Column(
            children: [
              Container(
                width: 80,
                height: 80,
                decoration: BoxDecoration(
                  color: MyApp.secondaryColor.withOpacity(0.2),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Icon(icon, size: 50, color: MyApp.primaryColor),
              ),
              SizedBox(height: 16),
              Text(
                title,
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                textAlign: TextAlign.center,
              ),
              SizedBox(height: 8),
              Text(
                description,
                style: TextStyle(color: Colors.grey[600], fontSize: 14),
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// --------------------------------------------------
// Weight & Body Fat Record Page
// --------------------------------------------------
class WeightWaistRecordPage extends StatefulWidget {
  @override
  _WeightWaistRecordPageState createState() => _WeightWaistRecordPageState();
}

class _WeightWaistRecordPageState extends State<WeightWaistRecordPage> {
  List<Map<String, dynamic>> records = [];
  bool isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadRecords();
 
    
  }
 
  Future<void> _loadRecords() async {
    try {
      setState(() => isLoading = true);
      final loaded = await DatabaseHelper.instance.getWeightRecords();
      setState(() {
        records = loaded;
        isLoading = false;
      });
    } catch (e) {
      print('Error loading weight records: $e');
      setState(() => isLoading = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to load records')),
      );
    }
  }

  void _showAddRecordDialog() {
    final _formKey = GlobalKey<FormState>();
    final _weightController = TextEditingController();
    final _bodyFatController = TextEditingController();

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Add Weight Record'),
        content: Form(
          key: _formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextFormField(
                controller: _weightController,
                decoration: InputDecoration(
                  labelText: 'Weight (kg)',
                  border: OutlineInputBorder(),
                  prefixIcon: Icon(Icons.monitor_weight),
                ),
                keyboardType: TextInputType.numberWithOptions(decimal: true),
                validator: (value) {
                  if (value == null || value.isEmpty) {
                    return 'Please enter weight';
                  }
                  final number = double.tryParse(value);
                  if (number == null) {
                    return 'Invalid number';
                  }
                  if (number < 30 || number > 250) {
                    return 'Please enter a reasonable range';
                  }
                  return null;
                },
              ),
              SizedBox(height: 16),
              TextFormField(
                controller: _bodyFatController,
                decoration: InputDecoration(
                  labelText: 'Body Fat (%)',
                  border: OutlineInputBorder(),
                  prefixIcon: Icon(Icons.accessibility_new),
                ),
                keyboardType: TextInputType.numberWithOptions(decimal: true),
                validator: (value) {
                  if (value == null || value.isEmpty) {
                    return 'Please enter body fat';
                  }
                  final number = double.tryParse(value);
                  if (number == null) {
                    return 'Invalid number';
                  }
                  if (number < 0 || number > 60) {
                    return 'Please enter a valid range (0-60)';
                  }
                  return null;
                },
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text('Cancel'),
          ),
          TextButton(
            onPressed: () async {
              if (_formKey.currentState?.validate() ?? false) {
                final weight = double.parse(_weightController.text);
                final bodyFat = double.parse(_bodyFatController.text);
                final now = DateTime.now();
                final record = {
                  'date':
                      '${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}',
                  'time':
                      '${now.hour.toString().padLeft(2, '0')}:${now.minute.toString().padLeft(2, '0')}',
                  'weight': weight,
                  'body_fat': bodyFat,
                };
                await DatabaseHelper.instance.insertWeightRecord(record);
                Navigator.pop(context);
                _loadRecords();
              }
            },
            child: Text('Save'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('Weight & Body Fat Records'),
        actions: [
          IconButton(
            icon: Icon(Icons.add),
            onPressed: _showAddRecordDialog,
          ),
        ],
      ),
      body: isLoading
          ? Center(child: CircularProgressIndicator())
          : records.isEmpty
              ? Center(child: Text('No records yet'))
              : ListView.builder(
                  itemCount: records.length,
                  itemBuilder: (_, i) {
                    final r = records[i];
                    return Card(
                      margin: EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                      child: Padding(
                        padding: EdgeInsets.all(16),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Text(r['date'],
                                    style: TextStyle(fontWeight: FontWeight.bold)),
                                Text(r['time'], style: TextStyle(color: Colors.grey)),
                              ],
                            ),
                            SizedBox(height: 8),
                            Text('Weight: ${r['weight']} kg'),
                            Text('Body Fat: ${r['body_fat']} %'),
                          ],
                        ),
                      ),
                    );
                  },
                ),
    );
  }
}
// 新增完整的 ExerciseRecordPage 類
class ExerciseRecordPage extends StatefulWidget {
  @override
  _ExerciseRecordPageState createState() => _ExerciseRecordPageState();
}

class _ExerciseRecordPageState extends State<ExerciseRecordPage> {
  List<Map<String, dynamic>> records = [];
  bool isLoading = true;
  int todayTotalCalories = 0;

  @override
  void initState() {
    super.initState();
    _loadRecords();
  }

  Future<void> _loadRecords() async {
    try {
      setState(() => isLoading = true);
      final loaded = await DatabaseHelper.instance.getExerciseRecords();
      setState(() {
        records = loaded;
        isLoading = false;
      });
      _calculateTodayTotal();
    } catch (e) {
      print('Error loading exercise records: $e');
      setState(() => isLoading = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to load records')),
      );
    }
  }

  void _calculateTodayTotal() {
    final now = DateTime.now();
    final todayStr =
        '${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}';
    todayTotalCalories = records
        .where((r) => r['date'] == todayStr)
        .fold(0, (sum, r) => sum + (r['calories_burned'] as int));
  }

  void _showAddRecordDialog() {
    final _formKey = GlobalKey<FormState>();
    final _noteController = TextEditingController();
    
    // 運動項目選項
    final exerciseTypes = [
      'Running',
      'Cycling',
      'Swimming',
      'Yoga',
      'Weight Training',
      'Walking'
    ];
    String? selectedExercise;
    
    // 運動時間選項
    final durations = [15, 30, 45];
    int? selectedDuration;

    showDialog(
      context: context,
      builder: (dialogCtx) => AlertDialog(
        title: Text('Add Exercise Record'),
        content: SingleChildScrollView(
          child: Form(
            key: _formKey,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // 運動項目下拉選單
                DropdownButtonFormField<String>(
                  decoration: InputDecoration(
                    labelText: 'Exercise Type',
                    border: OutlineInputBorder(),
                    prefixIcon: Icon(Icons.fitness_center),
                  ),
                  items: exerciseTypes
                      .map((type) => DropdownMenuItem(
                            value: type,
                            child: Text(type),
                          ))
                      .toList(),
                  onChanged: (val) => selectedExercise = val,
                  validator: (val) => val == null ? 'Please select an exercise' : null,
                ),
                SizedBox(height: 16),
                // 運動時間選擇
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: durations.map((val) {
                    return ElevatedButton(
                      onPressed: () {
                        setState(() {
                          selectedDuration = val;
                        });
                      },
                      style: ElevatedButton.styleFrom(
                        backgroundColor: selectedDuration == val 
                            ? MyApp.primaryColor 
                            : MyApp.secondaryColor,
                        foregroundColor: Colors.white,
                      ),
                      child: Text('$val min'),
                    );
                  }).toList(),
                ),
                SizedBox(height: 16),
                // 備註
                TextFormField(
                  controller: _noteController,
                  decoration: InputDecoration(
                    labelText: 'Note',
                    hintText: 'e.g. felt great!',
                    border: OutlineInputBorder(),
                    prefixIcon: Icon(Icons.notes),
                  ),
                  maxLines: 2,
                ),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogCtx),
            child: Text('Cancel'),
          ),
          TextButton(
            onPressed: () async {
              if (_formKey.currentState?.validate() ?? false) {
                if (selectedDuration == null) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text('Please select a duration')),
                  );
                  return;
                }
                
                final now = DateTime.now();
                // 簡單估算消耗的卡路里（每分鐘約 5-10 大卡，依運動強度不同）
                final caloriesBurned = selectedDuration! * 
                    (selectedExercise == 'Running' ? 10 : 
                     selectedExercise == 'Cycling' ? 8 : 
                     selectedExercise == 'Swimming' ? 9 :
                     selectedExercise == 'Yoga' ? 5 :
                     selectedExercise == 'Weight Training' ? 7 : 6);

                final record = {
                  'date': '${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}',
                  'time': '${now.hour.toString().padLeft(2, '0')}:${now.minute.toString().padLeft(2, '0')}',
                  'exercise_type': selectedExercise!,
                  'duration': selectedDuration,
                  'calories_burned': caloriesBurned,
                  'note': _noteController.text.trim(),
                };
                
                await DatabaseHelper.instance.insertExerciseRecord(record);
                Navigator.pop(dialogCtx);
                _loadRecords();
              }
            },
            child: Text('Save'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    _calculateTodayTotal(); // 更新今日總消耗

    return Scaffold(
      appBar: AppBar(
        title: Text('Exercise Records'),
        actions: [
          IconButton(
            icon: Icon(Icons.add),
            onPressed: _showAddRecordDialog,
          ),
        ],
      ),
      body: isLoading
          ? Center(child: CircularProgressIndicator())
          : Column(
              children: [
                Card(
                  margin: EdgeInsets.all(16),
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      children: [
                        Text(
                          'Today\'s Burned Calories',
                          style: TextStyle(fontSize: 16, color: MyApp.primaryColor),
                        ),
                        SizedBox(height: 8),
                        Text(
                          '$todayTotalCalories kcal',
                          style: TextStyle(
                            fontSize: 24,
                            fontWeight: FontWeight.bold,
                            color: MyApp.primaryColor,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                Expanded(
                  child: records.isEmpty
                      ? Center(child: Text('No records yet'))
                      : ListView.builder(
                          itemCount: records.length,
                          itemBuilder: (_, i) {
                            final r = records[i];
                            return Card(
                              margin: EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                              child: ListTile(
                                leading: Icon(Icons.fitness_center,
                                    color: MyApp.primaryColor, size: 32),
                                title: Row(
                                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                  children: [
                                    Text(r['exercise_type']),
                                    Text(
                                      r['time'],
                                      style: TextStyle(color: Colors.grey),
                                    ),
                                  ],
                                ),
                                subtitle: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(r['date']),
                                    Text('Duration: ${r['duration']} min'),
                                    Text('Burned: ${r['calories_burned']} kcal'),
                                    if ((r['note'] as String).isNotEmpty)
                                      Text(r['note'],
                                          style: TextStyle(color: Colors.grey[600])),
                                  ],
                                ),
                              ),
                            );
                          },
                        ),
                ),
              ],
            ),
    );
  }
}
// --------------------------------------------------
// CaloriesRecordPage
// --------------------------------------------------
class CaloriesRecordPage extends StatefulWidget {
  @override
  _CaloriesRecordPageState createState() => _CaloriesRecordPageState();
}

 

class _CaloriesRecordPageState extends State<CaloriesRecordPage> {
  List<Map<String, dynamic>> records = [];
  bool isLoading = true;
  InterstitialAd? _interstitialAd;
  bool _isInterstitialAdReady = false;
  DateTime? _lastAdShowTime;
  static const Duration _minIntervalBetweenAds = Duration(minutes: 3); // 設定最小間隔時間為3分鐘
// 新增這些 controller
  final TextEditingController _caloriesController = TextEditingController();
  final TextEditingController _proteinController = TextEditingController();
  final TextEditingController _carbsController = TextEditingController();
  final TextEditingController _fatController = TextEditingController();
  final TextEditingController _descriptionController = TextEditingController();
  @override
  void initState() {
    super.initState();
    _loadRecords();
    _loadInterstitialAd();
  }

  @override
  void dispose() {
      _interstitialAd?.dispose();
  _caloriesController.dispose();
  _proteinController.dispose();
  _carbsController.dispose();
  _fatController.dispose();
  _descriptionController.dispose();
    super.dispose();
  }

  void _loadInterstitialAd() {
    print('Loading interstitial ad...'); // Debug log
    InterstitialAd.load(
      adUnitId: Platform.isAndroid
          ? 'ca-app-pub-6422295172788813/2836516551' // Android   ID
          : 'ca-app-pub-6422295172788813/3770185626', // iOS   ID
      request: AdRequest(),
      adLoadCallback: InterstitialAdLoadCallback(
        onAdLoaded: (InterstitialAd ad) {
          print('Interstitial ad loaded successfully');
          _interstitialAd = ad;
          _isInterstitialAdReady = true;
          
          // 設置廣告關閉回調
          _interstitialAd?.fullScreenContentCallback = FullScreenContentCallback(
            onAdDismissedFullScreenContent: (InterstitialAd ad) {
              print('Ad dismissed');
              ad.dispose();
              _isInterstitialAdReady = false;
              // 廣告關閉後重新載入新廣告
              _loadInterstitialAd();
            },
            onAdFailedToShowFullScreenContent: (InterstitialAd ad, AdError error) {
              print('Ad failed to show: $error');
              ad.dispose();
              _isInterstitialAdReady = false;
              _loadInterstitialAd();
            },
          );

          // 檢查是否可以顯示廣告
          if (_isInterstitialAdReady && _canShowAd()) {
            _showAdWithTimeout();
          }
        },
        onAdFailedToLoad: (LoadAdError error) {
          print('Interstitial ad failed to load: $error');
          _isInterstitialAdReady = false;
          _interstitialAd = null;
          
          // 顯示錯誤訊息
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('廣告載入失敗: ${error.message}'),
              backgroundColor: Colors.red,
              action: SnackBarAction(
                label: '重試',
                textColor: Colors.white,
                onPressed: _loadInterstitialAd,
              ),
            ),
          );
        },
      ),
    );
  }

  Future<void> _loadRecords() async {
    try {
      setState(() => isLoading = true);
      final loaded = await DatabaseHelper.instance.getCaloriesRecords();
      setState(() {
        records = loaded;
        isLoading = false;
      });
    } catch (e) {
      print('Error loading calorie records: $e');
      setState(() => isLoading = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to load records')),
      );
    }
  }

  void _showAddRecordDialog() {
    final _formKey = GlobalKey<FormState>();
    final _caloriesController = TextEditingController();
    final _descriptionController = TextEditingController();
    String? imagePath;

    // 時間下拉選單
    final timeSlots = _generateTimeSlots();
    String selectedTime = _getCurrentTimeSlot();

    // 假裝有個食物分析表
  final mockFoodAnalysis = {
  'Bread': {
    'calories': 320,
    'protein': 15.0,
    'carbs': 30.0,
    'fat': 10,
  },
  'Hamburger': {
    'calories': 300,
    'protein': 15.0,
    'carbs': 28.0,
    'fat': 12.0,
  },
  'Salad': {
    'calories': 350,
    'protein': 5.0,
    'carbs': 10.0,
    'fat': 8.0,
  },
  'Noodles': {
    'calories': 450,
    'protein': 12.0,
    'carbs': 85.0,
    'fat': 2.0,
  },
  'Fruit': {
    'calories': 500,
    'protein': 13.0,
    'carbs': 30.0,
    'fat': 20.2,
  },
  'Rice': {
    'calories': 400,
    'protein': 20.0,
    'carbs': 44.0,
    'fat': 6,
  },
};

    showDialog(
      context: context,
      builder: (dialogCtx) {
        return StatefulBuilder(
          builder: (context, setState) => AlertDialog(
            title: Text('Add meal Record'),
            content: SingleChildScrollView(
              child: Form(
                key: _formKey,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // 方式選擇：手動 / 拍照
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                      children: [
                        ElevatedButton.icon(
                          icon: Icon(Icons.edit),
                          label: Text('Manual'),
                          onPressed: () {
                            setState(() {
                              imagePath = null;
                              _caloriesController.clear();
                              _descriptionController.clear();
                            });
                          },
                        ),
                        ElevatedButton.icon(
                          icon: Icon(Icons.camera_alt),
                          label: Text('Camera'),
                          onPressed: () async {
                            final picker = ImagePicker();
                            final photo = await picker.pickImage(
                              source: ImageSource.camera,
                            );
                            if (photo != null) {
                              setState(() {
                                imagePath = photo.path;
                                // 隨機假裝分析
                               final rand = Random();
                              final keys = mockFoodAnalysis.keys.toList();
                              final food = keys[rand.nextInt(keys.length)];
                              final analysis = mockFoodAnalysis[food]!;
                              _caloriesController.text = '${analysis['calories']}';
                              _proteinController.text = '${analysis['protein']}';
                              _carbsController.text = '${analysis['carbs']}';
                              _fatController.text = '${analysis['fat']}';
                              _descriptionController.text = '';
                            });
                            }
                          },
                        ),
                      ],
                    ),
                    SizedBox(height: 16),
                    // 若有照片則顯示
                    if (imagePath != null) ...[
                      ClipRRect(
                        borderRadius: BorderRadius.circular(8),
                        child: Image.file(
                          File(imagePath!),
                          height: 150,
                          width: double.infinity,
                          fit: BoxFit.cover,
                        ),
                      ),
                      SizedBox(height: 8),
                      Text('Analysis Results',
                          style: TextStyle(
                              fontWeight: FontWeight.bold,
                              color: MyApp.primaryColor)),
                    ],
                    SizedBox(height: 16),
                    // 時間下拉
                    DropdownButtonFormField<String>(
                      value: selectedTime,
                      decoration: InputDecoration(
                        labelText: 'Time',
                        border: OutlineInputBorder(),
                      ),
                      items: timeSlots
                          .map((t) => DropdownMenuItem(value: t, child: Text(t)))
                          .toList(),
                      onChanged: (val) {
                        if (val != null) {
                          setState(() => selectedTime = val);
                        }
                      },
                    ),


                    TextFormField(
  controller: _proteinController,
  decoration: InputDecoration(
    labelText: 'Protein (g)',
    border: OutlineInputBorder(),
    prefixIcon: Icon(Icons.food_bank),
  ),
  keyboardType: TextInputType.numberWithOptions(decimal: true),
  validator: (val) {
    if (val == null || val.isEmpty) return 'Please enter value';
    final n = double.tryParse(val);
    if (n == null) return 'Invalid number';
    if (n < 0 || n > 200) return 'Out of range (0-200)';
    return null;
  },
),
SizedBox(height: 16),
TextFormField(
  controller: _carbsController,
  decoration: InputDecoration(
    labelText: 'Carbohydrates (g)',
    border: OutlineInputBorder(),
    prefixIcon: Icon(Icons.grain),
  ),
  keyboardType: TextInputType.numberWithOptions(decimal: true),
  validator: (val) {
    if (val == null || val.isEmpty) return 'Please enter value';
    final n = double.tryParse(val);
    if (n == null) return 'Invalid number';
    if (n < 0 || n > 500) return 'Out of range (0-500)';
    return null;
  },
),
SizedBox(height: 16),
TextFormField(
  controller: _fatController,
  decoration: InputDecoration(
    labelText: 'Fat (g)',
    border: OutlineInputBorder(),
    prefixIcon: Icon(Icons.opacity),
  ),
  keyboardType: TextInputType.numberWithOptions(decimal: true),
  validator: (val) {
    if (val == null || val.isEmpty) return 'Please enter value';
    final n = double.tryParse(val);
    if (n == null) return 'Invalid number';
    if (n < 0 || n > 200) return 'Out of range (0-200)';
    return null;
  },
),
                    SizedBox(height: 16),
                    // Calories
                    TextFormField(
                      controller: _caloriesController,
                      decoration: InputDecoration(
                        labelText: 'Calories',
                        suffixText: 'kcal',
                        border: OutlineInputBorder(),
                        prefixIcon: Icon(Icons.fastfood),
                      ),
                      keyboardType: TextInputType.number,
                      validator: (val) {
                        if (val == null || val.isEmpty) {
                          return 'Please enter value';
                        }
                        final n = int.tryParse(val);
                        if (n == null) {
                          return 'Invalid number';
                        }
                        if (n < 1 || n > 5000) {
                          return 'Out of range (1-5000)';
                        }
                        return null;
                      },
                    ),
                    SizedBox(height: 16),
                    // 描述
                    TextFormField(
                      controller: _descriptionController,
                      decoration: InputDecoration(
                        labelText: 'Description',
                        border: OutlineInputBorder(),
                        prefixIcon: Icon(Icons.notes),
                      ),
                      maxLines: 2,
                    ),
                  ],
                ),
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(dialogCtx),
                child: Text('Cancel'),
              ),
              TextButton(
                onPressed: () async {
                  if (_formKey.currentState?.validate() ?? false) {
                    try {
                      final now = DateTime.now();
                     final record = {
  'date': '${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}',
  'time': selectedTime,
  'calories': int.parse(_caloriesController.text),
  'protein': double.parse(_proteinController.text),
  'carbs': double.parse(_carbsController.text),
  'fat': double.parse(_fatController.text),
  'description': _descriptionController.text.trim(),
  'image_path': imagePath ?? '',
};
                      await DatabaseHelper.instance.insertCaloriesRecord(record);
                      Navigator.pop(dialogCtx);
                      _loadRecords();

                      // 添加記錄成功後檢查是否可以顯示廣告
                      if (_isInterstitialAdReady && _canShowAd()) {
                        _showAdWithTimeout();
                      }
                    } catch (e) {
                      print('Error saving: $e');
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(content: Text('Save failed: $e')),
                      );
                    }
                  }
                },
                child: Text('Save'),
              ),
            ],
          ),
        );
      },
    );
  }

  // 檢查是否可以顯示廣告
  bool _canShowAd() {
    if (_lastAdShowTime == null) return true;
    final timeSinceLastAd = DateTime.now().difference(_lastAdShowTime!);
    return timeSinceLastAd >= _minIntervalBetweenAds;
  }

  // 顯示廣告並設置超時
  void _showAdWithTimeout() {
    if (!_canShowAd()) {
      print('廣告展示間隔時間不足，跳過顯示');
      return;
    }
    
    _lastAdShowTime = DateTime.now();
    _interstitialAd?.show().then((_) {
      print('welcome');
    }).catchError((error) {
      print('welcome: $error');
      _isInterstitialAdReady = false;
      _loadInterstitialAd();
    });
  }

  List<String> _generateTimeSlots() {
    final slots = <String>[];
    for (int h = 0; h < 24; h++) {
      slots.add('${h.toString().padLeft(2, '0')}:00');
      slots.add('${h.toString().padLeft(2, '0')}:30');
    }
    return slots;
  }

  String _getCurrentTimeSlot() {
    final now = DateTime.now();
    final hh = now.hour.toString().padLeft(2, '0');
    final mm = (now.minute >= 30) ? '30' : '00';
    return '$hh:$mm';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('Meal Records'),
        actions: [
          // 添加重新載入廣告的按鈕
          IconButton(
            icon: Icon(Icons.refresh),
            onPressed: _loadInterstitialAd,
            tooltip: '重新載入廣告',
          ),
          IconButton(
            icon: Icon(Icons.add),
            onPressed: _showAddRecordDialog,
          ),
        ],
      ),
      body: isLoading
          ? Center(child: CircularProgressIndicator())
          : records.isEmpty
              ? Center(child: Text('No records yet'))
              : ListView.builder(
                  itemCount: records.length,
                  itemBuilder: (_, i) {
                    final r = records[i];
                    return Card(
                      margin: EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          if ((r['image_path'] as String).isNotEmpty)
                            ClipRRect(
                              borderRadius:
                                  BorderRadius.vertical(top: Radius.circular(4)),
                              child: Image.file(
                                File(r['image_path']),
                                height: 150,
                                fit: BoxFit.cover,
                                errorBuilder: (_, __, ___) => Container(
                                  height: 50,
                                  color: Colors.grey,
                                  child: Center(child: Text('Image load error')),
                                ),
                              ),
                            ),
                          Padding(
                            padding: EdgeInsets.all(16),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  mainAxisAlignment:
                                      MainAxisAlignment.spaceBetween,
                                  children: [
                                    Text(r['date'],
                                        style: TextStyle(fontWeight: FontWeight.bold)),
                                    Text(r['time'],
                                        style: TextStyle(color: Colors.grey)),
                                  ],
                                ),
                                SizedBox(height: 8),
                                Text('${r['calories']} kcal',
                                    style: TextStyle(
                                        fontWeight: FontWeight.bold,
                                        color: Colors.orange)),
                                if ((r['description'] as String).isNotEmpty)
                                  Text(r['description'],
                                      style: TextStyle(color: Colors.grey[700])),
                              ],
                            ),
                          ),
                        ],
                      ),
                    );
                  },
                ),
    );
  }
}

// --------------------------------------------------
// WaterRecordPage
// --------------------------------------------------
class WaterRecordPage extends StatefulWidget {
  @override
  _WaterRecordPageState createState() => _WaterRecordPageState();
}

class _WaterRecordPageState extends State<WaterRecordPage> {
  List<Map<String, dynamic>> records = [];
  bool isLoading = true;
  int todayTotal = 0;
  final int dailyGoal = 2000; // 目標水量 (ml)

  @override
  void initState() {
    super.initState();
    _loadRecords();
  }

  Future<void> _loadRecords() async {
    try {
      setState(() => isLoading = true);
      final loaded = await DatabaseHelper.instance.getWaterRecords();
      setState(() {
        records = loaded;
        isLoading = false;
      });
      _calculateTodayTotal();
    } catch (e) {
      print('Error loading water records: $e');
      setState(() => isLoading = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to load records')),
      );
    }
  }

  void _calculateTodayTotal() {
    final now = DateTime.now();
    final todayStr =
        '${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}';
    todayTotal = records
        .where((r) => r['date'] == todayStr)
        .fold(0, (sum, r) => sum + (r['amount'] as int));
  }

  void _showAddRecordDialog() {
    final _formKey = GlobalKey<FormState>();
    final _amountController = TextEditingController();
    final _noteController = TextEditingController();

    final quickAmounts = [100, 200, 300, 500, 750, 1000];

    showDialog(
      context: context,
      builder: (dialogCtx) => AlertDialog(
        title: Text('Add Water Record'),
        content: SingleChildScrollView(
          child: Form(
            key: _formKey,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: quickAmounts.map((val) {
                    return ElevatedButton(
                      onPressed: () {
                        _amountController.text = val.toString();
                      },
                      style: ElevatedButton.styleFrom(
                        backgroundColor: MyApp.secondaryColor,
                        foregroundColor: Colors.white,
                      ),
                      child: Text('$val ml'),
                    );
                  }).toList(),
                ),
                SizedBox(height: 16),
                TextFormField(
                  controller: _amountController,
                  decoration: InputDecoration(
                    labelText: 'Water Amount',
                    suffixText: 'ml',
                    border: OutlineInputBorder(),
                    prefixIcon: Icon(Icons.water_drop),
                  ),
                  keyboardType: TextInputType.number,
                  validator: (val) {
                    if (val == null || val.isEmpty) return 'Please enter amount';
                    final n = int.tryParse(val);
                    if (n == null) return 'Invalid number';
                    if (n < 1 || n > 3000) return 'Out of range (1-3000)';
                    return null;
                  },
                ),
                SizedBox(height: 16),
                TextFormField(
                  controller: _noteController,
                  decoration: InputDecoration(
                    labelText: 'Note',
                    hintText: 'e.g. after workout',
                    border: OutlineInputBorder(),
                    prefixIcon: Icon(Icons.notes),
                  ),
                  maxLines: 2,
                ),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogCtx),
            child: Text('Cancel'),
          ),
          TextButton(
            onPressed: () async {
              if (_formKey.currentState?.validate() ?? false) {
                final now = DateTime.now();
                final record = {
                  'date':
                      '${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}',
                  'time':
                      '${now.hour.toString().padLeft(2, '0')}:${now.minute.toString().padLeft(2, '0')}',
                  'amount': int.parse(_amountController.text),
                  'note': _noteController.text.trim(),
                };
                await DatabaseHelper.instance.insertWaterRecord(record);
                Navigator.pop(dialogCtx);
                _loadRecords();
              }
            },
            child: Text('Save'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    _calculateTodayTotal(); // 更新今日水量

    return Scaffold(
      appBar: AppBar(
        title: Text('Water Records'),
        actions: [
          IconButton(
            icon: Icon(Icons.add),
            onPressed: _showAddRecordDialog,
          ),
        ],
      ),
      body: isLoading
          ? Center(child: CircularProgressIndicator())
          : Column(
              children: [
                Card(
                  margin: EdgeInsets.all(16),
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      children: [
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                          children: [
                            Column(
                              children: [
                                Text('Today',
                                    style: TextStyle(
                                        fontSize: 16,
                                        color: MyApp.primaryColor)),
                                SizedBox(height: 8),
                                Text(
                                  '$todayTotal ml',
                                  style: TextStyle(
                                      fontSize: 24,
                                      fontWeight: FontWeight.bold,
                                      color: MyApp.primaryColor),
                                ),
                              ],
                            ),
                            Column(
                              children: [
                                Text('Goal',
                                    style: TextStyle(
                                        fontSize: 16,
                                        color: MyApp.primaryColor)),
                                SizedBox(height: 8),
                                Text(
                                  '${((todayTotal / dailyGoal) * 100).toStringAsFixed(1)}%',
                                  style: TextStyle(
                                      fontSize: 24,
                                      fontWeight: FontWeight.bold,
                                      color: MyApp.primaryColor),
                                ),
                              ],
                            ),
                          ],
                        ),
                        SizedBox(height: 16),
                        LinearProgressIndicator(
                          value: todayTotal / dailyGoal,
                          backgroundColor: Colors.grey[200],
                          valueColor:
                              AlwaysStoppedAnimation<Color>(MyApp.primaryColor),
                          minHeight: 10,
                        ),
                      ],
                    ),
                  ),
                ),
                Expanded(
                  child: records.isEmpty
                      ? Center(child: Text('No records yet'))
                      : ListView.builder(
                          itemCount: records.length,
                          itemBuilder: (_, i) {
                            final r = records[i];
                            return Card(
                              margin: EdgeInsets.symmetric(
                                  horizontal: 16, vertical: 8),
                              child: ListTile(
                                leading: Icon(Icons.water_drop,
                                    color: MyApp.primaryColor, size: 32),
                                title: Row(
                                  mainAxisAlignment:
                                      MainAxisAlignment.spaceBetween,
                                  children: [
                                    Text('${r['amount']} ml'),
                                    Text(
                                      r['time'],
                                      style: TextStyle(color: Colors.grey),
                                    ),
                                  ],
                                ),
                                subtitle: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(r['date']),
                                    if ((r['note'] as String).isNotEmpty)
                                      Text(r['note'],
                                          style: TextStyle(
                                              color: Colors.grey[600])),
                                  ],
                                ),
                              ),
                            );
                          },
                        ),
                ),
              ],
            ),
    );
  }
}

// --------------------------------------------------
// TimelinePage
// --------------------------------------------------
class TimelinePage extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return FutureBuilder<List<Map<String, dynamic>>>(
      future: _loadAllRecords(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return Center(child: CircularProgressIndicator());
        }
        if (!snapshot.hasData || snapshot.data!.isEmpty) {
          return Center(child: Text('No saved records', style: TextStyle(fontSize: 18)));
        }

        final grouped = _groupByDate(snapshot.data!);

        return ListView.builder(
          padding: EdgeInsets.only(top: kToolbarHeight, bottom: 16),
          itemCount: grouped.length,
          itemBuilder: (context, i) {
            final date = grouped.keys.elementAt(i);
            final items = grouped[date]!;
            // 判斷 left / right
            final isLeft = (i % 2 == 0);

            return _buildTimelineCard(context, date, items, isLeft);
          },
        );
      },
    );
  }

  Future<List<Map<String, dynamic>>> _loadAllRecords() async {
  final weightRecords = await DatabaseHelper.instance.getWeightRecords();
  final caloriesRecords = await DatabaseHelper.instance.getCaloriesRecords();
  final waterRecords = await DatabaseHelper.instance.getWaterRecords();
  final exerciseRecords = await DatabaseHelper.instance.getExerciseRecords();

  final all = [
    ...weightRecords.map((x) => {...x, 'type': 'weight'}),
    ...caloriesRecords.map((x) => {...x, 'type': 'calories'}),
    ...waterRecords.map((x) => {...x, 'type': 'water'}),
    ...exerciseRecords.map((x) => {...x, 'type': 'exercise'}),
  ];
  all.sort((a, b) {
    final dA = DateTime.parse('${a['date']} ${a['time']}');
    final dB = DateTime.parse('${b['date']} ${b['time']}');
    return dB.compareTo(dA);
  });
  return all;
}
  Map<String, List<Map<String, dynamic>>> _groupByDate(
      List<Map<String, dynamic>> all) {
    final map = <String, List<Map<String, dynamic>>>{};
    for (var item in all) {
      final date = item['date'];
      map[date] ??= [];
      map[date]!.add(item);
    }
    return map;
  }

  Widget _buildTimelineCard(
    BuildContext context,
    String date,
    List<Map<String, dynamic>> items,
    bool isLeft,
  ) {
    return Row(
      mainAxisAlignment: isLeft ? MainAxisAlignment.start : MainAxisAlignment.end,
      children: [
        Container(
          margin: EdgeInsets.symmetric(vertical: 8, horizontal: 16),
          width: MediaQuery.of(context).size.width * 0.7,
          child: Card(
            elevation: 4,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            child: Padding(
              padding: EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Date：$date',
                      style: TextStyle(
                          fontSize: 16, fontWeight: FontWeight.bold, color: Colors.teal)),
                  Divider(thickness: 1),
                  ...items.map((r) {
                    final type = r['type'];
                    if (type == 'weight') {
                      // Weight
                      return Padding(
                        padding: const EdgeInsets.only(bottom: 8.0),
                        child: Text(
                          'Time：${r['time']}'
                          '\nWeight${r['weight']} kg'
                          '\nBody Fat：${r['body_fat']} %',
                          style: TextStyle(fontSize: 14, height: 1.3),
                        ),
                      );
                  } else if (type == 'calories') {
  // Calories
  return Padding(
    padding: const EdgeInsets.only(bottom: 8.0),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Time：${r['time']}\n'
          'Calories：${r['calories']} kcal\n'
          'Protein：${r['protein']}g\n'
          'Carbs：${r['carbs']}g\n'
          'Fat：${r['fat']}g\n'
          'Description：${r['description'] ?? ''}',
          style: TextStyle(fontSize: 14, height: 1.3),
        ),
        if ((r['image_path'] as String).isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 4.0),
            child: Image.file(
              File(r['image_path']),
              width: 60,
              height: 60,
              fit: BoxFit.cover,
              errorBuilder: (_, __, ___) => Container(
                width: 60,
                height: 60,
                color: Colors.grey,
                child: Center(child: Text('Img error')),
              ),
            ),
          ),
        SizedBox(height: 4),
      ],
    ),
  );
  

} else if (type == 'exercise') {
  // Exercise
  return Padding(
    padding: const EdgeInsets.only(bottom: 8.0),
    child: Text(
      'Time：${r['time']}'
      '\nExercise：${r['exercise_type']}'
      '\nDuration：${r['duration']} min'
      '\nCalories Burned：${r['calories_burned']} kcal'
      '${(r['note'] as String).isNotEmpty ? '\nNote：${r['note']}' : ''}',
      style: TextStyle(fontSize: 14, height: 1.3),
    ),
  );
}
else if (type == 'water') {
                      // Water
                      return Padding(
                        padding: const EdgeInsets.only(bottom: 8.0),
                        child: Text(
                          'Time${r['time']}'
                          '\nWater：${r['amount']} ml'
                          '${(r['note'] as String).isNotEmpty ? '\nNote：${r['note']}' : ''}',
                          style: TextStyle(fontSize: 14, height: 1.3),
                        ),
                      );
                    } else {
                      return SizedBox.shrink();
                    }
                  }).toList(),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }
}

// --------------------------------------------------
// 自訂 Painter：BmiGaugePainter
// --------------------------------------------------
class BmiGaugePainter extends CustomPainter {
  final double bmi;
  BmiGaugePainter(this.bmi);

  @override
  void paint(Canvas canvas, Size size) {
    final Paint paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 20;

    // 半圓外接矩形 (此儀表板是 180 度)
    final Rect arcRect = Rect.fromLTWH(0, 0, size.width, size.height * 2);

    // 先畫淺灰背景弧線
    paint.color = Colors.grey.shade300;
    canvas.drawArc(arcRect, pi, pi, false, paint);

    // 0~40 BMI 對應 180 度
    double clampBmi = bmi.clamp(0, 40);
    double fractionToAngle(double value) => pi * (value / 40);

    // 畫各區段
    _drawArcSegment(
      canvas: canvas,
      rect: arcRect,
      paint: paint,
      startAngle: pi,
      sweepAngle: fractionToAngle(18.5),
      color: Colors.lightBlue, // 過輕
    );
    _drawArcSegment(
      canvas: canvas,
      rect: arcRect,
      paint: paint,
      startAngle: pi + fractionToAngle(18.5),
      sweepAngle: fractionToAngle(25) - fractionToAngle(18.5),
      color: Colors.green, // 正常
    );
    _drawArcSegment(
      canvas: canvas,
      rect: arcRect,
      paint: paint,
      startAngle: pi + fractionToAngle(25),
      sweepAngle: fractionToAngle(30) - fractionToAngle(25),
      color: Colors.orange, // 過重
    );
    _drawArcSegment(
      canvas: canvas,
      rect: arcRect,
      paint: paint,
      startAngle: pi + fractionToAngle(30),
      sweepAngle: fractionToAngle(40) - fractionToAngle(30),
      color: Colors.redAccent, // 肥胖
    );

    // 指針
    final pointerAngle = fractionToAngle(clampBmi);
    final center = Offset(size.width / 2, size.height);
    final pointerLen = size.height - paint.strokeWidth; 
    final double actualAngle = pi + pointerAngle;

    final double endX = center.dx + pointerLen * cos(actualAngle);
    final double endY = center.dy + pointerLen * sin(actualAngle);

    final Paint pointerPaint = Paint()
      ..color = Colors.black
      ..strokeWidth = 4
      ..style = PaintingStyle.stroke;

    // 畫指針
    canvas.drawLine(center, Offset(endX, endY), pointerPaint);

    // 畫中心圓點
    final Paint centerDotPaint = Paint()..color = Colors.black;
    canvas.drawCircle(center, 6, centerDotPaint);
  }

  void _drawArcSegment({
    required Canvas canvas,
    required Rect rect,
    required Paint paint,
    required double startAngle,
    required double sweepAngle,
    required Color color,
  }) {
    paint.color = color;
    canvas.drawArc(rect, startAngle, sweepAngle, false, paint);
  }

  @override
  bool shouldRepaint(BmiGaugePainter oldDelegate) {
    return oldDelegate.bmi != bmi;
  }
}

// Settings Page
class SettingsScreen extends StatefulWidget {
  @override
  _SettingsScreenState createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  String selectedLanguage = 'EN';

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('Settings'),
        leading: IconButton(
          icon: Icon(Icons.arrow_back),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: ListView(
        children: [
          

          // Data Management Section
          
          // App Info Section
          Card(
            margin: EdgeInsets.all(8),
            color: Color(0xFFE0F4F4),
            child: Column(
              children: [
                ListTile(
                  title: Text('APP Version'),
                  trailing: Text('v1.0.0'),
                ),
                ListTile(
                  title: Text('Language'),
                  trailing: ToggleButtons(
                    borderRadius: BorderRadius.circular(20),
                    selectedColor: Colors.white,
                    fillColor: Color(0xFF7DAAB6),
                    children: [
                      Container(
                        padding: EdgeInsets.symmetric(horizontal: 16),
                        child: Text('EN'),
                      ) 
                    ],
                    isSelected: [
                      selectedLanguage == 'EN',
                    
                    ],
                    onPressed: (index) {
                      setState(() {
                        selectedLanguage = index == 0 ? 'EN' : '中文';
                      });
                    },
                  ),
                ),
                ListTile(
                  title: Text('Terms of use & Privacy Policy'),
                  onTap: () async {
                    // Display Terms of Use Dialog
                    await showDialog(
                      context: context,
                      builder: (context) => AlertDialog(
                        title: Text('Terms of Use'),
                        content:    Text(
  'Effective: December 11, 2024 (previous version)\n\n'
  'Thank you for using OpenAI!\n\n'
  'These Terms of Use apply to your use of ChatGPT, DALL·E, and OpenAI’s other services for individuals, '
  'along with any associated software applications and websites (all together, “Services”). These Terms '
  'form an agreement between you and OpenAI, L.L.C., a Delaware company, and they include our Service '
  'Terms⁠ and important provisions for resolving disputes through arbitration. By using our Services, '
  'you agree to these Terms. \n\n'
  'If you reside in the European Economic Area, Switzerland, or the UK, your use of the Services is '
  'governed by these terms⁠.\n\n'
  'Our Business Terms⁠ govern use of ChatGPT Enterprise, our APIs, and our other services for businesses '
  'and developers. \n\n'
  'Our Privacy Policy⁠ explains how we collect and use personal information. Although it does not form '
  'part of these Terms, it is an important document that you should read.\n\n'
  'Who we are\n'
  'OpenAI is an AI research and deployment company. Our mission is to ensure that artificial general '
  'intelligence benefits all of humanity. For more information about OpenAI, please visit https://openai.com/about⁠.\n\n'
  'Registration and access\n'
  'Minimum age. You must be at least 13 years old or the minimum age required in your country to consent '
  'to use the Services. If you are under 18 you must have your parent or legal guardian’s permission to use '
  'the Services. \n\n'
  'Registration. You must provide accurate and complete information to register for an account to use our '
  'Services. You may not share your account credentials or make your account available to anyone else and '
  'are responsible for all activities that occur under your account. If you create an account or use the Services '
  'on behalf of another person or entity, you must have the authority to accept these Terms on their behalf.\n\n'
  'Using our Services\n'
  'What you can do. Subject to your compliance with these Terms, you may access and use our Services. '
  'In using our Services, you must comply with all applicable laws as well as our Sharing & Publication Policy⁠, '
  'Usage Policies⁠, and any other documentation, guidelines, or policies we make available to you. \n\n'
  'What you cannot do. You may not use our Services for any illegal, harmful, or abusive activity. For example, you may not:\n\n'
  'Use our Services in a way that infringes, misappropriates or violates anyone’s rights.\n'
  'Modify, copy, lease, sell or distribute any of our Services.\n'
  'Attempt to or assist anyone to reverse engineer, decompile or discover the source code or underlying '
  'components of our Services, including our models, algorithms, or systems (except to the extent this restriction '
  'is prohibited by applicable law).\n\n'
  'Automatically or programmatically extract data or Output (defined below).\n'
  'Represent that Output was human-generated when it was not.\n\n'
  'Interfere with or disrupt our Services, including circumvent any rate limits or restrictions or bypass any '
  'protective measures or safety mitigations we put on our Services.\n\n'
  'Use Output to develop models that compete with OpenAI.\n\n'
  'Software. Our Services may allow you to download software, such as mobile applications, which may update '
  'automatically to ensure you’re using the latest version. Our software may include open source software that is '
  'governed by its own licenses that we’ve made available to you.\n\n'
  'Corporate domains. If you create an account using an email address owned by an organization (for example, your '
  'employer), that account may be added to the organization s business account with us, in which case we will provide '
  'notice to you so that you can help facilitate the transfer of your account (unless your organization has already '
  'provided notice to you that it may monitor and control your account). Once your account is transferred, the organization’s '
  'administrator will be able to control your account, including being able to access Content (defined below) and restrict or '
  'remove your access to the account.\n\n'
  'Third party Services. Our services may include third party software, products, or services, (“Third Party Services”) and '
  'some parts of our Services, like our browse feature, may include output from those services (“Third Party Output”). Third Party '
  'Services and Third Party Output are subject to their own terms, and we are not responsible for them. \n\n'
  'Feedback. We appreciate your feedback, and you agree that we may use it without restriction or compensation to you.\n'
)
,
                        actions: [
                          TextButton(
                            onPressed: () => Navigator.of(context).pop(),
                            child: Text('Close'),
                          ),
                        ],
                      ),
                    );

                    // Display Privacy Policy Dialog
                    await showDialog(
                      context: context,
                      builder: (context) => AlertDialog(
                        title: Text('Privacy Policy'),
                        content: Text(
  'For individuals in the European Economic Area, United Kingdom, and Switzerland, you can read this version⁠ of our Privacy Policy\n\n'
  'We at OpenAI OpCo, LLC (together with our affiliates, “OpenAI”, “we”, “our” or “us”) respect your privacy and are strongly '
  'committed to keeping secure any information we obtain from you or about you. This Privacy Policy describes our practices '
  'with respect to Personal Data that we collect from or about you when you use our website, applications, and services '
  '(collectively, “Services”). \n\n'
  'This Privacy Policy does not apply to content that we process on behalf of customers of our business offerings, such as '
  'our API. Our use of that data is governed by our customer agreements covering access to and use of those offerings.\n\n'
  'For information about how we collect and use training information to develop our language models that power ChatGPT and '
  'other Services, and your choices with respect to that information, please see this help center article⁠(opens in a new window).\n\n'
  '1. Personal Data we collect\n'
  'We collect personal data relating to you (“Personal Data”) as follows:\n\n'
  'Personal Data You Provide: We collect Personal Data if you create an account to use our Services or communicate with us as follows:\n\n'
  'Account Information: When you create an account with us, we will collect information associated with your account, '
  'including your name, contact information, account credentials, date of birth, payment information, and transaction history, '
  '(collectively, “Account Information”).\n\n'
  'User Content: We collect Personal Data that you provide in the input to our Services (“Content”), including your prompts '
  'and other content you upload, such as files⁠(opens in a new window), images⁠(opens in a new window), and audio⁠(opens in a new window), '
  'depending on the features you use.\n\n'
  'Communication Information: If you communicate with us, such as via email or our pages on social media sites, we may collect '
  'Personal Data like your name, contact information, and the contents of the messages you send (“Communication Information”).\n\n'
  'Other Information You Provide: We collect other information that you may provide to us, such as when you participate in our '
  'events or surveys or provide us with information to establish your identity or age (collectively, “Other Information You Provide”).\n\n'
  'Personal Data We Receive from Your Use of the Services: When you visit, use, or interact with the Services, we receive the following '
  'information about your visit, use, or interactions (“Technical Information”):\n\n'
  'Log Data: We collect information that your browser or device automatically sends when you use our Services. Log data includes '
  'your Internet Protocol address, browser type and settings, the date and time of your request, and how you interact with our Services.\n\n'
  'Usage Data: We collect information about your use of the Services, such as the types of content that you view or engage with, '
  'the features you use and the actions you take, as well as your time zone, country, the dates and times of access, user agent and version, '
  'type of computer or mobile device, and your computer connection.\n\n'
  'Device Information: We collect information about the device you use to access the Services, such as the name of the device, operating '
  'system, device identifiers, and browser you are using. Information collected may depend on the type of device you use and its settings.\n\n'
  'Location Information: We may determine the general area from which your device accesses our Services based on information like its '
  'IP address for security reasons and to make your product experience better, for example to protect your account by detecting unusual '
  'login activity or to provide more accurate responses. In addition, some of our Services allow you to choose to provide more precise '
  'location information from your device, such as location information from your device’s GPS.\n\n'
  'Cookies and Similar Technologies: We use cookies and similar technologies to operate and administer our Services, and improve your '
  'experience. If you use our Services without creating an account, we may store some of the information described in this policy with '
  'cookies, for example to help maintain your preferences across browsing sessions. For details about our use of cookies, please read '
  'our Cookie Notice⁠.\n\n'
  'Information We Receive from Other Sources: We receive information from our trusted partners, such as security partners, to protect '
  'against fraud, abuse, and other security threats to our Services, and from marketing vendors who provide us with information about '
  'potential customers of our business services.\n\n'
  'We also collect information from other sources, like information that is publicly available on the internet, to develop the models that '
  'power our Services. For more information on the sources of information used to develop the models that power ChatGPT and other '
  'Services, please see this help center article⁠(opens in a new window).\n'
)
,
                        actions: [
                          TextButton(
                            onPressed: () => Navigator.of(context).pop(),
                            child: Text('Close'),
                          ),
                        ],
                      ),
                    );
                  },
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class RemindersScreen extends StatefulWidget {
  @override
  _RemindersScreenState createState() => _RemindersScreenState();
}

class _RemindersScreenState extends State<RemindersScreen> {
  bool weightNotifications = false;
  bool mealNotifications = false;
  String weightTime = '08:00';
  String mealTime = '12:00';
  
  @override
  void initState() {
    super.initState();
    _initNotifications();
    _loadSettings();
        Fluttertoast.showToast(
      msg: "notifiy: ",
      toastLength: Toast.LENGTH_LONG,
      gravity: ToastGravity.BOTTOM,
      backgroundColor: Colors.red,
      textColor: Colors.white,
      fontSize: 16.0,
    );
  }

  Future<void> _initNotifications() async { 
  }

  Future<void> _loadSettings() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      setState(() {
        weightNotifications = prefs.getBool('weightNotifications') ?? false;
        mealNotifications = prefs.getBool('mealNotifications') ?? false;
        weightTime = prefs.getString('weightTime') ?? '08:00';
        mealTime = prefs.getString('mealTime') ?? '12:00';
      });
    } catch (e) {
      print('Error loading settings: $e');
    }
  }

  Future<void> _saveSettings() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool('weightNotifications', weightNotifications);
      await prefs.setBool('mealNotifications', mealNotifications);
      await prefs.setString('weightTime', weightTime);
      await prefs.setString('mealTime', mealTime);
    } catch (e) {
      print('Error saving settings: $e');
    }
  }

  Future<void> _scheduleNotification({
    required int id,
    required String title,
    required String body,
    required String time,
  }) async {
    try {
      final timeparts = time.split(':');
      final hour = int.parse(timeparts[0]);
      final minute = int.parse(timeparts[1]);
 
    } catch (e) {
      print('Error scheduling notification: $e');
          Fluttertoast.showToast(
      msg: "Error: $e",
      toastLength: Toast.LENGTH_LONG,
      gravity: ToastGravity.BOTTOM,
      backgroundColor: Colors.red,
      textColor: Colors.white,
      fontSize: 16.0,
    );
    }
  }

  Future<void> _cancelNotification(int id) async {
   
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('Reminder Settings'),
      ),
      body: ListView(
        children: [
          // 體重記錄提醒
          _buildReminderSection(
            title: 'Weight Record Reminder',
            icon: Icons.monitor_weight,
            isEnabled: weightNotifications,
            time: weightTime,
            onEnabledChanged: (value) async {
              setState(() => weightNotifications = value);
              await _saveSettings();
              
              if (value) {
                await _scheduleNotification(
                  id: 1,
                  title: 'Time to record weight',
                  body: 'Record today s weight change now',
                  time: weightTime,
                );
              } else {
                await _cancelNotification(1);
              }
            },
            onTimeChanged: (TimeOfDay? newTime) async {
              if (newTime != null) {
                final time = '${newTime.hour.toString().padLeft(2, '0')}:${newTime.minute.toString().padLeft(2, '0')}';
                setState(() => weightTime = time);
                await _saveSettings();
                
                if (weightNotifications) {
                  await _scheduleNotification(
                    id: 1,
                    title: 'Time to record weight',
                    body: 'Record today s weight change now',
                    time: time,
                  );
                }
              }
            },
          ),

          // 餐點記錄提醒
          _buildReminderSection(
            title: ' Meal Record Reminder',
            icon: Icons.restaurant,
            isEnabled: mealNotifications,
            time: mealTime,
            onEnabledChanged: (value) async {
              setState(() => mealNotifications = value);
              await _saveSettings();
              
              if (value) {
                await _scheduleNotification(
                  id: 2,
                  title: 'Time to record meal',
                  body: 'Record this meal s calories now',
                  time: mealTime,
                );
              } else {
                await _cancelNotification(2);
              }
            },
            onTimeChanged: (TimeOfDay? newTime) async {
              if (newTime != null) {
                final time = '${newTime.hour.toString().padLeft(2, '0')}:${newTime.minute.toString().padLeft(2, '0')}';
                setState(() => mealTime = time);
                await _saveSettings();
                
                if (mealNotifications) {
                  await _scheduleNotification(
                    id: 2,
                    title: 'Time to record meal',
                    body: '	Record this meal s calories now',
                    time: time,
                  );
                }
              }
            },
          ),
        ],
      ),
    );
  }

  Widget _buildReminderSection({
    required String title,
    required IconData icon,
    required bool isEnabled,
    required String time,
    required Function(bool) onEnabledChanged,
    required Function(TimeOfDay?) onTimeChanged,
  }) {
    return Container(
      padding: EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, color: MyApp.primaryColor),
              SizedBox(width: 8),
              Text(title, style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
            ],
          ),
          Card(
            margin: EdgeInsets.only(top: 8),
            child: Column(
              children: [
                SwitchListTile(
                  title: Text('Enable Reminder'),
                  value: isEnabled,
                  onChanged: onEnabledChanged,
                ),
                ListTile(
                  title: Text('Reminder Time'),
                  trailing: Text('$time'),
                  enabled: isEnabled,
                  onTap: () async {
                    final timeparts = time.split(':');
                    final TimeOfDay? picked = await showTimePicker(
                      context: context,
                      initialTime: TimeOfDay(
                        hour: int.parse(timeparts[0]),
                        minute: int.parse(timeparts[1]),
                      ),
                    );
                    onTimeChanged(picked);
                  },
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

