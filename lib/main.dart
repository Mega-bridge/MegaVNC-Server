import 'dart:collection';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:megavnc_server/config.dart';
import 'package:megavnc_server/uvnc_ini.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:path_provider/path_provider.dart';
import 'package:provider/provider.dart';
import 'package:window_manager/window_manager.dart';

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

  runApp(const MyApp());
}

class MyAppState extends ChangeNotifier {
  String? username;
  String? password;
  int? repeaterId;
  String? pcName;

  void setUsername(String username) {
    this.username = username;
  }

  void setPassword(String password) {
    this.password = password;
  }

  void setRepeaterId(int repeaterId) {
    this.repeaterId = repeaterId;
  }

  void setPcName(String pcName) {
    this.pcName = pcName;
  }
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider(
      create: (context) => MyAppState(),
      child: MaterialApp(
        title: 'MegaVNC Server',
        theme: ThemeData(
          colorScheme: ColorScheme.fromSeed(seedColor: Colors.blue),
          useMaterial3: true,
        ),
        home: const LoginPage(),
      ),
    );
  }
}

class LoginPage extends StatefulWidget {
  const LoginPage({super.key});

  @override
  State<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage> {
  final _formKey = GlobalKey<FormState>();
  TextEditingController usernameController = TextEditingController();
  TextEditingController passwordController = TextEditingController();

  String versionInfo = '';

  void getVersionInfo() async {
    PackageInfo packageInfo = await PackageInfo.fromPlatform();
    setState(() {
      versionInfo = 'v${packageInfo.version} - Windows x64';
    });
  }

  @override
  void initState() {
    super.initState();
    getVersionInfo();
  }

  var isLoginProcessing = false;

  @override
  Widget build(BuildContext context) {
    var appState = context.watch<MyAppState>();

    return Scaffold(
      appBar: AppBar(
          foregroundColor: Theme.of(context).colorScheme.onPrimary,
          backgroundColor: Theme.of(context).colorScheme.primary,
          title: const Text('MegaVNC Server')),
      body: Form(
        key: _formKey,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(
                'MegaVNC 로그인',
                style: Theme.of(context).textTheme.titleLarge,
              ),
              const SizedBox(height: 20.0),
              TextFormField(
                controller: usernameController,
                decoration: const InputDecoration(
                  border: OutlineInputBorder(),
                  labelText: '사용자명',
                ),
                validator: (value) {
                  if (value == null || value.isEmpty) {
                    return '사용자명을 입력하세요.';
                  }
                  return null;
                },
              ),
              const SizedBox(
                height: 10,
              ),
              TextFormField(
                controller: passwordController,
                obscureText: true,
                decoration: const InputDecoration(
                    border: OutlineInputBorder(), labelText: '비밀번호'),
                validator: (value) {
                  if (value == null || value.isEmpty) {
                    return '비밀번호를 입력하세요.';
                  }
                  return null;
                },
              ),
              const SizedBox(
                height: 20,
              ),
              FilledButton.icon(
                icon: isLoginProcessing
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
                label: const Text('로그인'),
                onPressed: isLoginProcessing
                    ? null
                    : () async {
                        if (_formKey.currentState!.validate()) {
                          setState(() {
                            isLoginProcessing = true;
                          });

                          var username = usernameController.text;
                          var password = passwordController.text;

                          requestLogin(username, password).then((res) {
                            if (res.statusCode == 200) {
                              appState.setUsername(username);
                              appState.setPassword(password);

                              ScaffoldMessenger.of(context)
                                  .hideCurrentSnackBar();

                              Navigator.push(
                                  context,
                                  MaterialPageRoute(
                                      builder: (context) =>
                                          const ServerSetupPage()));
                            } else {
                              ScaffoldMessenger.of(context)
                                ..removeCurrentSnackBar()
                                ..showSnackBar(SnackBar(
                                  content:
                                      const Text('사용자명 또는 비밀번호가 올바르지 않습니다.'),
                                  action: SnackBarAction(
                                    label: '닫기',
                                    onPressed: () {},
                                  ),
                                ));
                            }

                            setState(() {
                              isLoginProcessing = false;
                            });
                          });
                        } else {
                          ScaffoldMessenger.of(context)
                            ..removeCurrentSnackBar()
                            ..showSnackBar(SnackBar(
                              content: const Text('사용자명과 비밀번호를 입력하세요.'),
                              action: SnackBarAction(
                                label: '닫기',
                                onPressed: () {},
                              ),
                            ));
                        }
                      },
              ),
              const SizedBox(height: 10),
              Text(versionInfo, style: Theme.of(context).textTheme.bodySmall)
            ],
          ),
        ),
      ),
    );
  }

  Future<http.Response> requestLogin(String username, String password) {
    return http.post(
      Uri.parse('https://$apiHost:$apiPort/api/auth/check'),
      headers: <String, String>{
        'Content-Type': 'application/json; charset=UTF-8',
      },
      body: jsonEncode(
          <String, String>{'username': username, 'password': password}),
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
  var isProcessing = false;
  final _pcInfoFormKey = GlobalKey<FormState>();
  var pcNameController = TextEditingController();
  var passwordInputController = TextEditingController();
  var setupFinished = false;

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
  Widget build(BuildContext context) {
    var appState = context.watch<MyAppState>();

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
                  Text('1. 이 PC의 이름과, 접속할 때 사용할 비밀번호를 입력하세요.'),
                ],
              ),
              const SizedBox(
                height: 20,
              ),
              Form(
                key: _pcInfoFormKey,
                child: Column(
                  children: [
                    TextFormField(
                      controller: pcNameController,
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
                      controller: passwordInputController,
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
              const SizedBox(
                height: 20,
              ),
              const Row(
                children: [
                  Text('2. 아래 "서버 설치" 버튼을 눌러 설정을 완료해주세요. (관리자 권한이 필요합니다.)'),
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
                label: const Text('서버 설치'),
                onPressed: isProcessing
                    ? null
                    : () async {
                        if (!_pcInfoFormKey.currentState!.validate()) {
                          return;
                        }

                        setState(() {
                          isProcessing = true;
                        });

                        output.clear();

                        log("Start");

                        log("Read uVNC executable from asset... ");
                        var exeBytes = await rootBundle
                            .load('assets/UltraVNC_1436_X64_Setup.exe');
                        append("Done");

                        log("Read install configuration from asset... ");
                        var configBytes =
                            await rootBundle.load('assets/config.txt');
                        append("Done");

                        log("Get application directory... ");
                        final appDir = await getApplicationDocumentsDirectory();
                        append("Done");

                        log("Locate destination file... ");
                        var exeFile =
                            File('${appDir.path}\\UltraVNC_1436_X64_Setup.exe');
                        append("Done");

                        log("Locate install configuration file... ");
                        var configFile = File('${appDir.path}\\config.txt');
                        append("Done");

                        log("Copy uVNC executable to destination file... ");
                        exeFile.writeAsBytesSync(exeBytes.buffer.asUint8List());
                        append("Done");

                        log("Copy configuration to destination file... ");
                        configFile
                            .writeAsBytesSync(configBytes.buffer.asUint8List());
                        append("Done");

                        log("Run uVNC executable process... ");
                        ProcessResult result = await Process.run(exeFile.path, [
                          '/verysilent',
                          '/loadinf=${configFile.path}',
                          '/norestart'
                        ]);
                        append("Done (${result.exitCode})");

                        log("Stop service... ");
                        ProcessResult stopServiceResult =
                            await Process.run('net', ['stop', 'uvnc_service']);
                        append("Done (${stopServiceResult.exitCode})");

                        log("Request repeater ID... ");
                        http.Response response = await http.post(
                          Uri.parse("https://$apiHost:$apiPort/api/remote-pcs"),
                          headers: <String, String>{
                            'Content-Type': 'application/json; charset=UTF-8',
                          },
                          body: jsonEncode(<String, String>{
                            'username': appState.username ?? '',
                            'password': appState.password ?? '',
                            'remotePcName': pcNameController.text
                          }),
                        );

                        if (response.statusCode != 200) {
                          append("Failed");
                          return;
                        }

                        Map<String, dynamic> json = jsonDecode(response.body);
                        if (!json.containsKey('repeaterId')) {
                          append("Failed");
                          return;
                        }

                        int repeaterId = json['repeaterId']!;
                        appState.setRepeaterId(repeaterId);
                        appState.setPcName(pcNameController.text);
                        append("Done (ID:$repeaterId)");

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
                        ProcessResult setPasswordResult = await Process.run(
                            setPasswordPath, [passwordInputController.text]);
                        append("Done (${setPasswordResult.exitCode})");

                        log("Start service... ");
                        ProcessResult startServiceResult =
                            await Process.run('net', ['start', 'uvnc_service']);
                        append("Done (${startServiceResult.exitCode})");

                        log("Remove install files... ");
                        await exeFile.delete();
                        await configFile.delete();
                        append("Done");

                        log("Finish");

                        setState(() {
                          isProcessing = false;
                          if (startServiceResult.exitCode == 0) {
                            setState(() {
                              setupFinished = true;
                            });
                          }
                        });

                        log('설정이 완료되었습니다. 아래 "다음" 버튼을 눌러 진행하세요.');
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
