import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../core/api_client.dart';
import '../core/session.dart';
import '../theme/app_theme.dart';
import '../widgets/common.dart';
import 'agreements_page.dart';

class HelpPage extends StatefulWidget {
  const HelpPage({super.key});

  @override
  State<HelpPage> createState() => _HelpPageState();
}

class _HelpPageState extends State<HelpPage> {
  Map<String, dynamic>? _settings;
  int? _open;

  static const _faqs = [
    [
      '借款需要满足什么条件？',
      '年满 22-55 周岁、非在校学生、完成实名认证与人脸识别、授权紧急联系人，即可提交授信申请。系统会综合评估您的信用状况给出额度与利率。'
    ],
    [
      '额度是怎么定的？',
      '额度由收入水平、认证完整度、历史履约记录、多头借贷情况等综合评估。完成公积金、运营商、信用卡账单认证可提升额度并有机会降低利率。'
    ],
    [
      '综合年化利率怎么算？',
      '综合年化利率（IRR）是考虑资金实际占用时间后的年化利率，按每期还款现金流折现计算。借款页会同时展示合同年利率与 IRR，费用透明，无砍头息。'
    ],
    [
      '可以提前还款吗？',
      '支持随时提前结清，仅收取截至结清日的实际用款利息，后续期利息免除，不额外收取违约金（活动期除外）。'
    ],
    [
      '逾期会有什么影响？',
      '逾期将按日计收罚息（日万分之五，总额不超过逾期本金的 20%），并可能影响您的征信记录。如遇还款困难，请及时联系客服协商方案。'
    ],
    [
      '放款失败怎么办？',
      '常见原因为银行卡状态异常（错误码 E1024）、二类账户限额等。请在借款详情页更换本人名下状态正常的储蓄卡后重试，或联系客服协助处理。'
    ],
    [
      '如何保障我的信息安全？',
      '身份证号、银行卡号等敏感信息采用 AES-256 加密存储，页面展示全部脱敏；系统实行最小权限访问与全量操作审计，未经授权不会向第三方提供。'
    ],
    [
      '为什么不向学生放款？',
      '根据监管要求，小额贷款不得向在校学生发放。我们通过年龄、职业信息与学籍核验进行拦截，请理解。'
    ],
  ];

  @override
  void initState() {
    super.initState();
    ApiClient.instance.get('/api/settings').then((d) {
      if (mounted) setState(() => _settings = Map<String, dynamic>.from(d as Map));
    }).catchError((_) {});
  }

  @override
  Widget build(BuildContext context) {
    final phone = _settings?['servicePhone'] as String? ?? '400-000-8888';
    final time = _settings?['serviceTime'] as String? ?? '09:00-21:00';
    return Scaffold(
      backgroundColor: UColors.bg,
      appBar: UNavBar(title: '帮助与客服'),
      body: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 28),
        child: Column(
          children: [
            UCard(
              gradient: UColors.navyGradient,
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Container(
                        width: 42,
                        height: 42,
                        decoration: BoxDecoration(color: UColors.gold.withValues(alpha: 0.16), borderRadius: BorderRadius.circular(12)),
                        child: const Icon(Icons.support_agent_rounded, color: UColors.goldLight, size: 22),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text('在线客服', style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w600)),
                            const SizedBox(height: 3),
                            Text('服务时间 $time', style: TextStyle(color: Colors.white.withValues(alpha: 0.55), fontSize: 11.5)),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  Row(
                    children: [
                      Expanded(
                        child: UButton(
                          text: '拨打 $phone',
                          small: true,
                          onPressed: () {
                            Clipboard.setData(ClipboardData(text: phone));
                            showToast(context, '客服热线已复制：$phone');
                          },
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            const Align(alignment: Alignment.centerLeft, child: Text('常见问题', style: UText.h3)),
            const SizedBox(height: 10),
            UCard(
              padding: EdgeInsets.zero,
              child: Column(
                children: _faqs.asMap().entries.map((e) {
                  final open = _open == e.key;
                  return Column(
                    children: [
                      InkWell(
                        onTap: () => setState(() => _open = open ? null : e.key),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 15),
                          child: Row(
                            children: [
                              Expanded(child: Text(e.value[0], style: UText.body.copyWith(fontSize: 14, fontWeight: FontWeight.w500))),
                              Icon(open ? Icons.remove : Icons.add, size: 18, color: UColors.textLight),
                            ],
                          ),
                        ),
                      ),
                      if (open)
                        Padding(
                          padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                          child: Align(
                            alignment: Alignment.centerLeft,
                            child: Text(e.value[1], style: UText.sub.copyWith(height: 1.75)),
                          ),
                        ),
                      if (e.key < _faqs.length - 1) const Divider(height: 1, indent: 16, endIndent: 16),
                    ],
                  );
                }).toList(),
              ),
            ),
            const SizedBox(height: 16),
            const Align(alignment: Alignment.centerLeft, child: Text('协议与政策', style: UText.h3)),
            const SizedBox(height: 10),
            UCard(
              padding: EdgeInsets.zero,
              child: Column(
                children: [
                  _doc('借款合同（摘要）', 'loan'),
                  const Divider(height: 1, indent: 16, endIndent: 16),
                  _doc('隐私政策', 'privacy'),
                  const Divider(height: 1, indent: 16, endIndent: 16),
                  _doc('个人信息授权书', 'personalInfo'),
                  const Divider(height: 1, indent: 16, endIndent: 16),
                  _doc('征信授权书', 'credit'),
                ],
              ),
            ),
            const SizedBox(height: 20),
            Text('UCash 由持牌小额贷款机构提供资金与服务', style: UText.tiny, textAlign: TextAlign.center),
            const SizedBox(height: 4),
            Text('客服热线 $phone · $time', style: UText.tiny.copyWith(fontSize: 10)),
          ],
        ),
      ),
    );
  }

  Widget _doc(String title, String type) => InkWell(
        onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => AgreementsPage(type: type))),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 15),
          child: Row(
            children: [
              Text(title, style: UText.body.copyWith(fontSize: 14)),
              const Spacer(),
              const Icon(Icons.chevron_right, size: 18, color: UColors.textLight),
            ],
          ),
        ),
      );
}
