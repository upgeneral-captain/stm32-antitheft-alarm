import 'package:flutter/material.dart';

import '../config/app_config.dart';
import '../services/storage_service.dart';
import '../state/app_state.dart';
import '../theme/app_theme.dart';
import 'home_page.dart';

/// 首次启动：设备绑定页
///
/// 只需要三项：巴法云 appID|secretKey + 设备主题（位置/状态/命令）。
/// 为了不给老人增加负担，主题默认值直接填好，通常只要填私钥。
class BindingPage extends StatefulWidget {
  const BindingPage({super.key});

  @override
  State<BindingPage> createState() => _BindingPageState();
}

class _BindingPageState extends State<BindingPage> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _userCtrl;
  late final TextEditingController _gpsCtrl;
  late final TextEditingController _stateCtrl;
  late final TextEditingController _cmdCtrl;
  bool _saving = false;
  bool _showAdvanced = false;

  @override
  void initState() {
    super.initState();
    final s = StorageService.instance;
    _userCtrl = TextEditingController(text: s.mqttUser);
    _gpsCtrl = TextEditingController(text: s.topicGps);
    _stateCtrl = TextEditingController(text: s.topicState);
    _cmdCtrl = TextEditingController(text: s.topicCmd);
  }

  @override
  void dispose() {
    _userCtrl.dispose();
    _gpsCtrl.dispose();
    _stateCtrl.dispose();
    _cmdCtrl.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    setState(() => _saving = true);
    await StorageService.instance.saveBinding(
      user: _userCtrl.text,
      topicGps: _gpsCtrl.text,
      topicState: _stateCtrl.text,
      topicCmd: _cmdCtrl.text,
    );
    await AppState.instance.mqtt.reconnect();
    if (!mounted) return;
    Navigator.of(context).pushReplacement(
      MaterialPageRoute(builder: (_) => const HomePage()),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: Form(
          key: _formKey,
          child: ListView(
            padding: const EdgeInsets.fromLTRB(22, 28, 22, 32),
            children: [
              // 标题区
              Container(
                padding: const EdgeInsets.all(24),
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    colors: [AppColors.primary, AppColors.primaryLight],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  borderRadius: BorderRadius.circular(24),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Icon(Icons.shield_moon_rounded,
                        color: Colors.white, size: 46),
                    const SizedBox(height: 12),
                    const Text(
                      '欢迎使用\n家庭防盗报警',
                      style: TextStyle(
                        fontSize: 30,
                        height: 1.25,
                        fontWeight: FontWeight.w800,
                        color: Colors.white,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      '只需填写一次，以后打开就能用',
                      style: TextStyle(
                        fontSize: 16,
                        color: Colors.white.withValues(alpha: 0.85),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 24),

              _label('巴法云 appID|secretKey'),
              TextFormField(
                controller: _userCtrl,
                maxLines: 2,
                minLines: 1,
                style: AppText.body,
                decoration: _inputDeco(
                  hint: '在 bemfa.com 控制台「MQTT 设备云」里复制',
                  icon: Icons.vpn_key_rounded,
                ),
                validator: (v) {
                  if (v == null || v.trim().split('|').length != 2 || v.trim().split('|').any((p)=>p.isEmpty)) return '请填写巴法云 appID|secretKey';
                  if (v.trim().length < 8) return '连接密钥不完整，请检查 appID 和 secretKey';
                  return null;
                },
              ),
              const SizedBox(height: 20),

              _label('设备主题'),
              Row(
                children: [
                  Expanded(
                    child: _topicField(
                      controller: _gpsCtrl,
                      hint: '位置主题',
                      validatorMsg: '请填写位置主题',
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: _topicField(
                      controller: _stateCtrl,
                      hint: '状态主题',
                      validatorMsg: '请填写状态主题',
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              _topicField(
                controller: _cmdCtrl,
                hint: '命令主题',
                validatorMsg: '请填写命令主题',
              ),

              const SizedBox(height: 12),
              TextButton.icon(
                onPressed: () =>
                    setState(() => _showAdvanced = !_showAdvanced),
                icon: Icon(
                  _showAdvanced
                      ? Icons.expand_less_rounded
                      : Icons.expand_more_rounded,
                  color: AppColors.primary,
                ),
                label: Text(
                  _showAdvanced ? '收起高级选项' : '高级选项（服务器地址）',
                  style: const TextStyle(fontSize: 16, color: AppColors.primary),
                ),
              ),
              if (_showAdvanced)
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: AppColors.divider),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('服务器：${AppConfig.mqttHost}:${AppConfig.mqttPort}',
                          style: AppText.body),
                      const SizedBox(height: 6),
                      Text('如需修改请编辑 lib/config/app_config.dart',
                          style: AppText.bodySmall),
                    ],
                  ),
                ),

              const SizedBox(height: 28),
              SizedBox(
                height: 64,
                child: ElevatedButton(
                  onPressed: _saving ? null : _save,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.primary,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(20),
                    ),
                  ),
                  child: _saving
                      ? const SizedBox(
                          width: 26,
                          height: 26,
                          child: CircularProgressIndicator(
                            strokeWidth: 2.5,
                            valueColor: AlwaysStoppedAnimation(Colors.white),
                          ),
                        )
                      : const Text(
                          '保存并开始使用',
                          style: TextStyle(
                            fontSize: 22,
                            fontWeight: FontWeight.w700,
                            color: Colors.white,
                          ),
                        ),
                ),
              ),
              const SizedBox(height: 18),
              Text(
                '提示：使用巴法云连接密钥页的 appID 与 secretKey，中间用 | 分隔。不要分享连接密钥。\n'
                '所有数据只保存在这台手机上。',
                style: AppText.bodySmall.copyWith(fontSize: 14),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _label(String text) => Padding(
        padding: const EdgeInsets.only(bottom: 8, left: 4),
        child: Text(
          text,
          style: const TextStyle(
            fontSize: 19,
            fontWeight: FontWeight.w600,
            color: AppColors.textPrimary,
          ),
        ),
      );

  Widget _topicField({
    required TextEditingController controller,
    required String hint,
    required String validatorMsg,
  }) {
    return TextFormField(
      controller: controller,
      style: AppText.body,
      decoration: _inputDeco(hint: hint, icon: Icons.tag_rounded),
      validator: (v) => (v == null || v.trim().isEmpty) ? validatorMsg : null,
    );
  }

  InputDecoration _inputDeco({required String hint, required IconData icon}) {
    return InputDecoration(
      hintText: hint,
      hintStyle: const TextStyle(fontSize: 16, color: AppColors.textSecondary),
      prefixIcon: Icon(icon, color: AppColors.primary, size: 24),
      filled: true,
      fillColor: Colors.white,
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 18),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(16),
        borderSide: BorderSide.none,
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(16),
        borderSide: const BorderSide(color: AppColors.divider),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(16),
        borderSide: const BorderSide(color: AppColors.primary, width: 2),
      ),
      errorStyle: const TextStyle(fontSize: 14),
    );
  }
}
