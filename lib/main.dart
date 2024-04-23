import 'dart:collection';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:megavnc_server/config.dart';
import 'package:megavnc_server/http_override.dart';
import 'package:megavnc_server/uvnc_ini.dart';
//import 'package:path_provider/path_provider.dart';
import 'package:provider/provider.dart';
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
  late Future<String> ipAdress;
  ResponseGroupApiDto? _selectedGroup;

  late Future<List<ResponseGroupApiDto>> fetchGroupsFuture;

  void log(String message) {
    setState(() {
      output.addFirst(message);
    });
  }

  void append(String message) {
    setState(() {
      String first = output.removeFirst();
      output.addFirst(first + message);
    });
  }

  @override
  void initState() {
    super.initState();
    fetchGroupsFuture = fetchGroups();

    ipAdress = getIPAddress();
  }

  void showErrorSnackbar(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: Colors.red[700],
      ),
    );
  }

  Future<List<ResponseGroupApiDto>> fetchGroups() async {
    try {
      final response =
          await http.get(Uri.parse('https://$apiHost:$apiPort/api/groups'));

      if (response.statusCode == 200) {
        final List<dynamic> jsonData =
            jsonDecode(utf8.decode(response.bodyBytes));
        final List<ResponseGroupApiDto> groups =
            jsonData.map((json) => ResponseGroupApiDto.fromJson(json)).toList();
        _selectedGroup ??= groups.isNotEmpty ? groups[0] : null;
        return groups;
      } else {
        throw Exception('Failed to load groups');
      }
    } catch (error) {
      showErrorSnackbar('Failed to fetch groups: $error');
      rethrow;
    }
  }

  Future<String> getIPAddress() async {
    try {
      for (var interface in await NetworkInterface.list()) {
        for (var addr in interface.addresses) {
          if (addr.type == InternetAddressType.IPv4) {
            return addr.address;
          }
        }
      }
    } catch (error) {
      showErrorSnackbar('Error getting IP address: $error');
    }
    showErrorSnackbar('Unable to get IP address');
    return 'Unable to get IP address';
  }

  @override
  Widget build(BuildContext context) {
    var isInputEnabled = !isProcessing && !setupFinished;
    final appState = Provider.of<MyAppState>(context);
    void copyDirectorySync(String sourcePath, String destinationPath) {
      final sourceDir = Directory(sourcePath);

      Directory(destinationPath).createSync(recursive: true);
      for (final entity in sourceDir.listSync(recursive: true)) {
        if (entity is File) {
          final newFile =
              File('${destinationPath}\\${entity.path.split('\\').last}');
          newFile.writeAsBytesSync(entity.readAsBytesSync());
        } else if (entity is Directory) {
          final newDir =
              Directory('${destinationPath}\\${entity.path.split('\\').last}');
          copyDirectorySync(entity.path, newDir.path);
        }
      }
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
                    : const SizedBox(),
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

                          log("Request repeater ID... ");
                          String ipadress = await ipAdress;

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
                              'ftpHost': ipadress
                            }),
                          );
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

//programfiles에 MegaVnc 디렉토리 생성
                          log("Make program Derectory... ");
                          String programDirectoryPath =
                              'C:\\Program Files\\MegaVnc';
                          Directory programDirectory =
                              Directory(programDirectoryPath);
                          if (!await programDirectory.exists()) {
                            await programDirectory.create(recursive: true);
                            append('Done ($programDirectoryPath)');
                          }

                          log("Read uVNC executable from asset... ");
                          var exeBytes = await rootBundle
                              .load('assets/UltraVNC_1436_X64_Setup.exe');
                          append("Done");

                          log("Read install configuration from asset... ");
                          var configBytes =
                              await rootBundle.load('assets/config.txt');
                          append("Done");

//ftpserver, ftp config 바이트로 변환

                          log("Read MegaFtpServ from asset... ");
                          var MegaFtpServBytes =
                              await rootBundle.load('assets/MegaFtpServ.exe');
                          append("Done");

                          log("Read ftpConfig from asset... ");
                          var ftpConfigBytes = await rootBundle
                              .load('assets/ftp-config.properties');
                          append("Done");

                          log("Locate destination file... ");
                          var exeFile = File(
                              '${programDirectory.path}\\UltraVNC_1436_X64_Setup.exe');
                          append("Done");

                          log("Locate install configuration file... ");
                          var configFile =
                              File('${programDirectory.path}\\config.txt');
                          append("Done");

//ftpserver, ftp config asset에서 위치 설정 위치는 위에서 만든 디렉토리로 변환

                          log("Locate MegaFtpServer file... ");
                          var MegaFtpServFile =
                              File('${programDirectory.path}\\MegaFtpServ.exe');
                          append("Done");

                          log("Locate ftpConfig file... ");
                          var ftpConfigFile = File(
                              '${programDirectory.path}\\ftp-config.properties');
                          append("Done");

                          log("Copy uVNC executable to destination file... ");
                          if (exeFile.existsSync()) {
                            await exeFile.delete();
                          }
                          exeFile
                              .writeAsBytesSync(exeBytes.buffer.asUint8List());
                          append("Done");

                          log("Copy configuration to destination file... ");
                          if (configFile.existsSync()) {
                            await configFile.delete();
                          }
                          configFile.writeAsBytesSync(
                              configBytes.buffer.asUint8List());
                          append("Done");

//ftpserver, ftp config 복사 이미 존재 하면 삭제하고 복사

                          log("Copy MegaFtpServ to destination file... ");
                          if (MegaFtpServFile.existsSync()) {
                            await MegaFtpServFile.delete();
                          }
                          MegaFtpServFile.writeAsBytesSync(
                              MegaFtpServBytes.buffer.asUint8List());
                          append("Done");

                          log("Copy ftpConfig to destination file... ");
                          if (ftpConfigFile.existsSync()) {
                            await ftpConfigFile.delete();
                          }
                          ftpConfigFile.writeAsBytesSync(
                              ftpConfigBytes.buffer.asUint8List());
                          append("Done");

//jdk 복사
                          log("Copy jdk-17.0.2 to destination file... ");
                          String currentDirectory = Directory.current.path;
                          if (!File('${programDirectory.path}\\jdk-17.0.2')
                              .existsSync()) {
                            copyDirectorySync(currentDirectory,
                                '${programDirectory.path}\\jdk-17.0.2');
                          }

                          append("Done");
                          log("Run uVNC executable process... ");
                          ProcessResult result = await Process.run(
                              exeFile.path, [
                            '/verysilent',
                            '/loadinf=${configFile.path}',
                            '/norestart'
                          ]);
                          append("Done (${result.stdout})");

                          log("Stop service... ");
                          ProcessResult stopServiceResult = await Process.run(
                              'net', ['stop', 'uvnc_service']);
                          append("Done (${stopServiceResult.stdout})");

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
                          append("Done (${startServiceResult.stdout})");

                          log("Make Derectory... ");
                          String directoryPath =
                              'C:\\Program Files\\MegaVncRemoteFiles';
                          Directory directory = Directory(directoryPath);
                          if (!await directory.exists()) {
                            await directory.create(recursive: true);
                            append('Done ($directoryPath)');
                          }
//삭제로직 없애기

                          log("Set up system environment... ");

                          ProcessResult setSystemEnvResult =
                              await Process.run('powershell', [
                            '-Command',
                            r'''
                          $existingEnv = [System.Environment]::GetEnvironmentVariable("MegaVncFtpJdk", "Machine")
                          if (-not $existingEnv) {
                            [System.Environment]::SetEnvironmentVariable("MegaVncFtpJdk", $null, "Machine")
                          }   ''',
                            ' [System.Environment]::SetEnvironmentVariable("MegaVncFtpJdk", "$programDirectoryPath\\jdk-17.0.2", "Machine")'
                          ]);
                          append("Done (${setSystemEnvResult.stdout})");

                          log("Set up inbound rules... ");
                          ProcessResult setInboundResult =
                              await Process.run('powershell', [
                            '-Command',
                            'if (-not (Get-NetFirewallRule -DisplayName "Allow Port 23")) { New-NetFirewallRule -DisplayName "Allow Port 23" -Direction Inbound -Protocol TCP -LocalPort 23 -Action Allow }'
                          ]);
                          append("Done (${setInboundResult.stdout})");

                          log("Run MegaFtpServ process... ");

//programfiles 에서 실행

                          ProcessResult runFtpServResult =
                              await Process.run('powershell', [
                            '-Command',
                            '  Start-Process -WindowStyle hidden -FilePath  "$programDirectoryPath\\MegaFtpServ.exe"'
                          ]);
                          append("Done (${runFtpServResult.stdout})");

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
                          append("Done (${deletaRegResult.stdout})");

                          log("Finish");
                          log('연결 요청이 완료되었습니다. 아래 "다음" 버튼을 눌러 진행하세요.');

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
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  FilledButton(
                      onPressed: setupFinished
                          ? () {
                              Navigator.push(
                                  context,
                                  MaterialPageRoute(
                                      builder: (context) =>
                                          const ConnectionCheckPage()));
                            }
                          : null,
                      child: const Text('다음'))
                ],
              )
            ],
          ),
        ),
      ),
    );
  }
}

class ConnectionCheckPage extends StatefulWidget {
  const ConnectionCheckPage({super.key});

  @override
  State<ConnectionCheckPage> createState() => _ConnectionCheckPageState();
}

class _ConnectionCheckPageState extends State<ConnectionCheckPage> {
  var pcName = "";
  var status = "OFFLINE";
  var isLoading = false;

  @override
  Widget build(BuildContext context) {
    var appState = context.watch<MyAppState>();

    return Scaffold(
        appBar: AppBar(
          foregroundColor: Theme.of(context).colorScheme.onPrimary,
          title: const Text('연결 확인'),
          backgroundColor: Theme.of(context).colorScheme.primary,
        ),
        body: Padding(
          padding: const EdgeInsets.all(20.0),
          child: Center(
            child: Column(
              children: [
                const Row(
                  children: [
                    Text('아래 "연결 확인" 버튼을 눌러 서버가 정상적으로 설치되었는지 확인하세요.'),
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
                  icon: isLoading
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
                  onPressed: isLoading
                      ? null
                      : () async {
                          setState(() {
                            isLoading = true;
                          });
                          http
                              .get(Uri.parse(
                                  'https://$apiHost:$apiPort/api/remote-pcs/${appState.repeaterId}'))
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
                            setState(() {
                              isLoading = false;
                            });
                          });
                        },
                ),
                const SizedBox(
                  height: 20.0,
                ),
                Row(
                  children: [
                    Text('${appState.pcName}의 현재 상태: '),
                    switch (status) {
                      "OFFLINE" => const Text('오프라인'),
                      "STANDBY" => const Text('연결됨 (대기중)'),
                      "ACTIVE" => const Text('연결됨 (사용중)'),
                      _ => const Text('error')
                    }
                  ],
                ),
                const Expanded(child: SizedBox()),
                Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    FilledButton(
                        onPressed: () {
                          exit(0);
                        },
                        child: const Text('완료'))
                  ],
                ),
              ],
            ),
          ),
        ));
  }
}
