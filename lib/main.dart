import 'dart:collection';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:megavnc_server/config.dart';
import 'package:megavnc_server/http_override.dart';
import 'package:megavnc_server/uvnc_ini.dart';
import 'package:provider/provider.dart';
import 'package:uuid/uuid.dart';
import 'package:window_manager/window_manager.dart';

class ResponseGroupApiDto {
  final int groupId;
  final String groupName;

  ResponseGroupApiDto({required this.groupId, required this.groupName});

  factory ResponseGroupApiDto.fromJson(Map<String, dynamic> json) {
    return ResponseGroupApiDto(
      groupId: json['groupId'],
      groupName: json['groupName'],
    );
  }
}

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  await windowManager.ensureInitialized();

  WindowOptions windowOptions = const WindowOptions(
    size: Size(600, 800),
    center: true,
  );

  windowManager.waitUntilReadyToShow(windowOptions, () async {
    await windowManager.show();
    await windowManager.focus();
  });

  HttpOverrides.global = DevHttpOverrides();

  runApp(const MyApp());
}

class MyAppState extends ChangeNotifier {
  int? repeaterId;
  String? pcName;
  String? accessPassword;
  String? reconnectId;
  List<ResponseGroupApiDto> _groups = [];
  List<ResponseGroupApiDto> get groups => _groups;

  void setRepeaterId(int repeaterId) {
    this.repeaterId = repeaterId;
  }

  void setPcName(String pcName) {
    this.pcName = pcName;
  }

  void setAccessPassword(String accessPassword) {
    this.accessPassword = accessPassword;
  }

  void setReconnectId(String reconnectId) {
    this.reconnectId = reconnectId;
  }
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider(
      create: (context) => MyAppState(),
      child: MaterialApp(
        title: 'MegaVNC',
        theme: ThemeData(
          colorScheme: ColorScheme.fromSeed(seedColor: Colors.blue),
          useMaterial3: true,
        ),
        home: const ServerSetupPage(),
      ),
    );
  }
}

class ServerSetupPage extends StatefulWidget {
  const ServerSetupPage({super.key});

  @override
  State<ServerSetupPage> createState() => _ServerSetupPageState();
}

class _ServerSetupPageState extends State<ServerSetupPage> {
  var output = Queue<String>();
  final _formKey = GlobalKey<FormState>();
  var pcNameController = TextEditingController();
  var accessPasswordController = TextEditingController();
  var isProcessing = false;
  var setupFinished = false;
  var pcName = "";
  var status = "OFFLINE";
  var isStatusLoading = false;
  var isDisconnectLoading = false;
  final String filePath =  "C://Program Files//MegaVnc//config.txt";
  ResponseGroupApiDto? _selectedGroup;
  late Future<List<ResponseGroupApiDto>> fetchGroupsFuture;
  late Map<String, dynamic> _config;

//초기값 설정 매서드
  @override
  void initState() {
    super.initState();
    fetchGroupsFuture = fetchGroups();
    firstParseConfig().then((_) {
      setState(() {
        if (_config['reconnect']['pcName'] != 'default') {
          pcNameController.text = _config['reconnect']['pcName'];
        }
      });
    });
  }

//로그 매서드
  void log(String message) {
    setState(() {
      output.addFirst(message);
    });
  }

//처리 결과 출력 매서드
  void append(String message) {
    setState(() {
      String first = output.removeFirst();
      output.addFirst(first + message);
    });
  }

//에러 스낵바 매서드
  void showErrorSnackbar(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: Colors.red,
      ),
    );
  }

//성공 스낵바 매서드
  void showSuccessSnackbar(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: Colors.green,
      ),
    );
  }

//그룹리스트 로딩 매서드
  Future<List<ResponseGroupApiDto>> fetchGroups() async {
    try {
      final response =
          await http.get(Uri.parse('https://$apiHost:$apiPort/api/groups'));

      if (response.statusCode == 200) {
        final List<dynamic> jsonData =
            jsonDecode(utf8.decode(response.bodyBytes));
        final List<ResponseGroupApiDto> fetchedGroups =
            jsonData.map((json) => ResponseGroupApiDto.fromJson(json)).toList();

        setState(() {
          if (_config['reconnect']['groupName'] != 'default') {
            _selectedGroup = fetchedGroups.firstWhere(
              (group) => group.groupName == _config['reconnect']['groupName'],
              orElse: () => fetchedGroups[0],
            );
          }
        });

        return fetchedGroups;
      } else {
        throw Exception('Failed to load groups');
      }
    } catch (error) {
      showErrorSnackbar('Failed to fetch groups: $error');
      rethrow;
    }
  }

// config 파싱 매서드
  Map<String, dynamic> parseConfig(String configContent) {
    Map<String, dynamic> configMap = {};
    List<String> lines = LineSplitter().convert(configContent);
    String? section;
    for (String line in lines) {
      if (line.startsWith('[') && line.endsWith(']')) {
        section = line.substring(1, line.length - 1);
        configMap[section] = {};
      } else {
        List<String> parts = line.split('=');
        configMap[section][parts[0]] = parts[1];
      }
    }

    return configMap;
  }

 //미리 로딩한 config
  Future<void> firstParseConfig() async {
 var file = File(filePath);
  String contents;

  if (await file.exists()) {
    contents = await file.readAsString();
  } else {
    var byteData = await rootBundle.load('assets/config.txt');
    contents = utf8.decode(byteData.buffer.asUint8List());
  }

        _config = parseConfig(contents);
    
  }

  
  @override
  Widget build(BuildContext context) {
    var isInputEnabled = !isProcessing && !setupFinished;
    final appState = Provider.of<MyAppState>(context);

    
//config 다시쓰기 매서드
  void writeConfigFile(Map<String, dynamic> configMap) async {
    IOSink? sink;
    try {
      final file = File(filePath);

      if (await file.exists()) {
        await file.delete();
      }

      await file.create(recursive: true);

      sink = file.openWrite(mode: FileMode.writeOnly);

      configMap.forEach((section, values) {
        sink!.writeln('[$section]');
        values.forEach((key, value) {
          sink!.writeln('$key=$value');
        });
      });
      await sink.close();
    } catch (e) {
      log('Error writing config file: $e');
    }
  }

//연결 해제 매서드
  void disconnect(Map<String, dynamic> config) async {
    setState(() {
      isDisconnectLoading = true;
    });
    try {
      String reconnectId = config['reconnect']['reconnectId'];
      final response = await http.delete(
          Uri.parse('https://$apiHost:$apiPort/api/remote-pcs/$reconnectId'));
      await Process.run('net', ['stop', 'uvnc_service']);
      if (response.statusCode == 200) {
        
        config['reconnect']['pcName'] = 'default';
        config['reconnect']['groupName'] = 'default';
        config['reconnect']['repeaterId'] = 'default';
        writeConfigFile(config);

        await Process.run('taskkill', ['/F', '/IM', 'ClipboardReader.exe']);

        await Process.run('powershell', [
          '-Command',
          r'Remove-ItemProperty -Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\Run" -Name "ClipboardReader"'
        ]);
        showSuccessSnackbar('연결이 성공적으로 해제되었습니다.');
      } else {
        final Map<String, dynamic> errorJson =
            jsonDecode(utf8.decode(response.bodyBytes));
        final errorMessage = errorJson['message'] ?? 'Unknown error';
        throw Exception('$errorMessage');
      }
    } catch (e) {
      showErrorSnackbar('$e');
    }
    //연결해제 실패 에러처리

    setState(() {
      isDisconnectLoading = false;
      isProcessing = false;
      setupFinished = false;
      output.clear();
    });
  }





 
    return Scaffold(
      appBar: AppBar(
        foregroundColor: Theme.of(context).colorScheme.onPrimary,
        title: const Text('서버 설정'),
        backgroundColor: Theme.of(context).colorScheme.primary,
      ),
      body: Padding(
        padding: const EdgeInsets.all(20.0),
        child: Center(
          child: Column(
            children: [
              const Row(
                children: [
                  Text('1. 그룹을 선택하고 이 PC의 이름과, 접속할 때 사용할 비밀번호를 입력하세요.'),
                ],
              ),
              const SizedBox(height: 20),
              FutureBuilder<List<ResponseGroupApiDto>>(
                future: fetchGroupsFuture,
                builder: (context, snapshot) {
                  if (snapshot.connectionState == ConnectionState.waiting) {
                    return const Center(child: CircularProgressIndicator());
                  } else if (snapshot.hasError) {
                    return Center(child: Text('Error: ${snapshot.error}'));
                  } else {
                    final groups = snapshot.data;
                    return DropdownButton<ResponseGroupApiDto>(
                      isExpanded: true,
                      hint: const Text('그룹을 선택하세요.'),
                      value: _selectedGroup,
                      onChanged: isInputEnabled
                          ? (newValue) {
                              setState(() {
                                _selectedGroup = newValue;
                              });
                            }
                          : null,
                      items: groups!.map((group) {
                        return DropdownMenuItem<ResponseGroupApiDto>(
                          value: group,
                          child: Text(group.groupName),
                        );
                      }).toList(),
                    );
                  }
                },
              ),
              const SizedBox(height: 20),
              Form(
                key: _formKey,
                child: Column(
                  children: [
                    TextFormField(
                      controller: pcNameController,
                      enabled: isInputEnabled,
                      decoration: const InputDecoration(
                          border: OutlineInputBorder(), label: Text('PC 이름')),
                      validator: (value) {
                        if (value == null || value.isEmpty) {
                          return 'PC 이름을 입력하세요.';
                        }
                        return null;
                      },
                    ),
                    const SizedBox(height: 10),
                    TextFormField(
                      controller: accessPasswordController,
                      enabled: isInputEnabled,
                      obscureText: true,
                      decoration: const InputDecoration(
                          border: OutlineInputBorder(), label: Text('접속 비밀번호')),
                      validator: (value) {
                        if (value == null || value.isEmpty) {
                          return '접속 비밀번호를 입력하세요.';
                        }
                        return null;
                      },
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 20),
              const Row(
                children: [
                  Text('2. 아래 "연결" 버튼을 눌러 설정을 완료해주세요. (관리자 권한이 필요합니다.)'),
                ],
              ),
              const SizedBox(height: 20),
              ElevatedButton.icon(
                icon: isProcessing
                    ? const Padding(
                        padding: EdgeInsets.all(8.0),
                        child: SizedBox(
                          width: 20,
                          height: 20,
                          child: Center(
                              child: CircularProgressIndicator(
                            strokeWidth: 3,
                          )),
                        ),
                      )
                    : const Icon(Icons.link),
                label: const Text('연결'),
                onPressed: isProcessing
                    ? null
                    : () async {
                        if (!_formKey.currentState!.validate()) {
                          return;
                        }

                        setState(() {
                          isProcessing = true;
                        });

                        output.clear();
                        try {
                          log("Start");
                         
                         log("Make program Derectory... ");
                          String programDirectoryPath =
                              'C:\\Program Files\\MegaVnc';
                          Directory programDirectory =
                              Directory(programDirectoryPath);
                          if (!await programDirectory.exists()) {
                            await programDirectory.create(recursive: true);
                            append('Done ($programDirectoryPath)');
                          }

                         log("Locate install configuration file... ");
                          var configFile =
                              File(filePath);
                          append("Done");

                          if(!await File(filePath).exists()){

                         log("Read install configuration from asset... ");
                          var configBytes =
                              await rootBundle.load('assets/config.txt');
                          append("Done");

                          log("Copy configuration to destination file... ");
                    
                          configFile.writeAsBytesSync(
                              configBytes.buffer.asUint8List());
                          append("Done");
                          }

               

                          log("Read Config File... ");
                          Map<String, dynamic> config =
                              parseConfig(await File(filePath).readAsString());
                          appState.setReconnectId(
                              config['reconnect']['reconnectId'] ?? 'default');
                          append("Done");

                          if (appState.reconnectId == 'default') {
                            log("Generate ReconnectId... ");
                            appState.setReconnectId(Uuid().v4());
                            config['reconnect']['reconnectId'] =
                                appState.reconnectId;
                            append("Done");
                          }

                       
                          log("Request repeater ID... ");
                          http.Response response = await http.post(
                            Uri.parse(
                                "https://$apiHost:$apiPort/api/remote-pcs"),
                            headers: <String, String>{
                              'Content-Type': 'application/json; charset=UTF-8',
                            },
                            body: jsonEncode(<String, String>{
                              'groupName': _selectedGroup?.groupName ?? '',
                              'accessPassword': accessPasswordController.text,
                              'pcName': pcNameController.text,
                              'reconnectId': appState.reconnectId ?? ''
                            }),
                          );
                        append("Done (${response.statusCode})");

                          Map<String, dynamic> json =
                              jsonDecode(utf8.decode(response.bodyBytes));

                          if (response.statusCode != 200) {
                            showErrorSnackbar(json['message']);
                            append("Failed");
                            throw Exception(json['message']);
                          }

                          if (!json.containsKey('repeaterId')) {
                            append("Failed");
                            showErrorSnackbar("리피터 아이디가 존재하지 않습니다.");
                            throw Exception("리피터 아이디가 존재하지 않습니다.");
                          }

                          int repeaterId = json['repeaterId']!;
                          appState.setRepeaterId(repeaterId);
                          appState.setPcName(pcNameController.text);
                          appState
                              .setAccessPassword(accessPasswordController.text);

                          append("Done (ID:$repeaterId)");

                          log("Stop ClipboardReader... ");
                          ProcessResult ClipboardReaderResult =
                              await Process.run('taskkill',
                                  ['/F', '/IM', 'ClipboardReader.exe']);
                          append("Done (${ClipboardReaderResult.exitCode})");

                          log("reset config... ");
                          config['reconnect']['pcName'] = pcNameController.text;
                          config['reconnect']['groupName'] =
                              _selectedGroup?.groupName ?? 'null';
                          config['reconnect']['repeaterId'] =
                              repeaterId.toString();
                          writeConfigFile(config);
                          append("Done");

                       

                          log("Read uVNC executable from asset... ");
                          var exeBytes = await rootBundle
                              .load('assets/UltraVNC_1436_X64_Setup.exe');
                          append("Done");

                     

                          log("Read ClipboardReader executable from asset... ");
                          var ClipboardReaderExeBytes = await rootBundle
                              .load('assets/ClipboardReader.exe');
                          append("Done");

                          log("Locate destination file... ");
                          var exeFile = File(
                              '${programDirectory.path}\\UltraVNC_1436_X64_Setup.exe');
                          append("Done");

       
                          log("Locate ClipboardReader file... ");
                          var ClipboardReaderExeFile = File(
                              '${programDirectory.path}\\ClipboardReader.exe');
                          append("Done");

                          log("Copy uVNC executable to destination file... ");
                          if (exeFile.existsSync()) {
                            await exeFile.delete();
                          }
                          exeFile
                              .writeAsBytesSync(exeBytes.buffer.asUint8List());
                          append("Done");

                  

                          log("Run uVNC executable process... ");
                          ProcessResult result = await Process.run(
                              exeFile.path, [
                            '/verysilent',
                            '/loadinf=${configFile.path}',
                            '/norestart'
                          ]);
                          append("Done (${result.exitCode})");

                          log("Stop service... ");
                          ProcessResult stopServiceResult = await Process.run(
                              'net', ['stop', 'uvnc_service']);
                          append("Done (${stopServiceResult.exitCode})");

                          log("Set repeater... ");
                          String iniString = getIniString(
                              repeaterId, repeaterHost, repeaterPort);
                          var iniFile = File(
                              'C:\\Program Files\\uvnc bvba\\UltraVNC\\ultravnc.ini');
                          await iniFile.writeAsString(iniString);
                          append("Done");

                          log("Set password... ");
                          var setPasswordPath =
                              'C:\\Program Files\\uvnc bvba\\UltraVNC\\setpasswd.exe';
                          String accessPassword = appState.accessPassword ?? "";
                          ProcessResult setPasswordResult = await Process.run(
                              setPasswordPath, [accessPassword]);
                          append("Done (${setPasswordResult.stdout})");

                          log("Start service... ");
                          ProcessResult startServiceResult = await Process.run(
                              'net', ['start', 'uvnc_service']);
                          append("Done (${startServiceResult.exitCode})");

                          log("Copy ClipboardReader executable to destination file... ");
                          if (ClipboardReaderExeFile.existsSync()) {
                            await ClipboardReaderExeFile.delete();
                          }
                          ClipboardReaderExeFile.writeAsBytesSync(
                              ClipboardReaderExeBytes.buffer.asUint8List());
                          append("Done");

                          log("Start ClipboardReader... ");
                          ProcessResult startClipboardReaderResult =
                              await Process.run('powershell', [
                            '-Command',
                            'Start-Process -WindowStyle hidden -FilePath  "$programDirectoryPath\\ClipboardReader.exe"'
                          ]);
                          append(
                              "Done (${startClipboardReaderResult.exitCode})");

                          log("Setting ClipboardReader as startup application...");
                          String programPath =
                              "$programDirectoryPath\\ClipboardReader.exe";
                          ProcessResult setStartupResult =
                              await Process.run('powershell', [
                            '-Command',
                            r'Set-ItemProperty -Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\Run" -Name "ClipboardReader" -Value "' +
                                programPath +
                                r'"'
                          ]);
                          append("Done (${setStartupResult.exitCode})");

                          log("reg delete PendingFileRenameOperations... ");
                          ProcessResult deletaRegResult = await Process.run(
                            'powershell',
                            [
                              '-Command',
                              r'''
                                try {
                                    Set-Location "HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager"
                                    Remove-ItemProperty -Path . -Name "PendingFileRenameOperations" -Force -ErrorAction Stop
                                    Write-Output "deleted successfully."
                                } catch {
                                    Write-Output "Failed to delete: $_"
                                    exit 1
                                }
                                '''
                            ],
                          );
                          append("Done (${deletaRegResult.exitCode})");

                          log("Finish");

                          setState(() {
                            isProcessing = false;
                            if (startServiceResult.exitCode == 0) {
                              setState(() {
                                setupFinished = true;
                              });
                            }
                          });
                        } catch (e) {
                          log("Error occurred: $e");
                          setState(() {
                            isProcessing = false;
                          });
                          return;
                        }
                      },
              ),
              const SizedBox(
                height: 20,
              ),
              Expanded(
                child: Container(
                  padding: const EdgeInsets.all(8.0),
                  decoration: BoxDecoration(
                      border: Border.all(color: Colors.grey, width: 1),
                      borderRadius:
                          const BorderRadius.all(Radius.circular(8.0))),
                  child: ListView(
                    children: output.map((e) => Text(e)).toList(),
                  ),
                ),
              ),
              const SizedBox(
                height: 20,
              ),
              const Row(
                children: [
                  Text('3. 아래 "연결 확인" 버튼을 눌러 서버가 정상적으로 설치되었는지 확인하세요.'),
                ],
              ),
              const Row(
                children: [
                  Text('(상태 업데이트에 30초 정도 시간이 걸릴 수 있습니다.)'),
                ],
              ),
              const SizedBox(
                height: 20,
              ),
              ElevatedButton.icon(
                icon: isStatusLoading
                    ? const Padding(
                        padding: EdgeInsets.all(8.0),
                        child: SizedBox(
                          width: 20,
                          height: 20,
                          child: Center(
                              child: CircularProgressIndicator(
                            strokeWidth: 3,
                          )),
                        ),
                      )
                    : const Icon(Icons.refresh),
                label: const Text('연결 확인'),
                onPressed: () async {
                  setState(() {
                    isStatusLoading = true;
                  });
           
                  Map<String, dynamic> config =
                      parseConfig(await File(filePath).readAsString());
                  if (config['reconnect']['repeaterId'] == 'default') {
                    showErrorSnackbar("연결 이후에 연결 확인이 가능합니다.");
                    status = "OFFLINE";
                  } else {
                    http
                        .get(Uri.parse(
                            'https://$apiHost:$apiPort/api/remote-pcs/${config['reconnect']['repeaterId']}'))
                        .then((res) {
                      if (res.statusCode == 200) {
                        Map<String, dynamic> json = jsonDecode(res.body);
                        setState(() {
                          status = json['status'];
                        });
                      } else {
                        setState(() {
                          status = res.statusCode.toString();
                        });
                      }
                    });
                    await Future.delayed(Duration(milliseconds: 2000));
                  }

                  setState(() {
                    isStatusLoading = false;
                  });
                },
              ),
              const SizedBox(
                height: 20.0,
              ),
              Row(
                children: [
                  Text('현재 상태: '),
                  if (isStatusLoading)
                    const Text('연결 확인중...',
                        style: TextStyle(color: Colors.grey)),
                  if (!isStatusLoading)
                    switch (status) {
                      "OFFLINE" => const Text('오프라인',
                          style: TextStyle(color: Colors.grey)),
                      "STANDBY" => const Text('대기중',
                          style: TextStyle(color: Colors.green)),
                      "ACTIVE" => const Text('사용중',
                          style: TextStyle(color: Colors.lightBlueAccent)),
                      _ =>
                        const Text('error', style: TextStyle(color: Colors.red))
                    }
                ],
              ),
              const SizedBox(
                height: 20.0,
              ),
              const Row(
                children: [
                  Text('4. 아래 "연결 해제" 버튼을 눌러 안전하게 연결을 종료하세요.'),
                ],
              ),
              const Row(
                children: [
                  Text('(연결을 해제하지 않으면 프로그램을 종료하여도 외부에서 pc에 접근 가능합니다.)'),
                ],
              ),
              const SizedBox(
                height: 20.0,
              ),
              ElevatedButton.icon(
                icon: isDisconnectLoading
                    ? const Padding(
                        padding: EdgeInsets.all(8.0),
                        child: SizedBox(
                          width: 20,
                          height: 20,
                          child: Center(
                              child: CircularProgressIndicator(
                            strokeWidth: 3,
                          )),
                        ),
                      )
                    : const Icon(Icons.link_off),
                label: const Text('연결 해제'),
                onPressed: isProcessing
                    ? null
                    : () async {
                        Map<String, dynamic> config =
                            parseConfig(await File(filePath).readAsString());

                        disconnect(config);
                      },
              ),
            ],
          ),
        ),
      ),
    );
  }
}
