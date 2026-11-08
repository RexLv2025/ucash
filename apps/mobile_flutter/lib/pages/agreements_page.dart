import 'package:flutter/material.dart';

import '../theme/app_theme.dart';
import '../widgets/common.dart';

class AgreementsPage extends StatelessWidget {
  final String type;
  const AgreementsPage({super.key, required this.type});

  static const _docs = <String, Map<String, dynamic>>{
    'privacy': {
      'title': '隐私政策',
      'updated': '2026-01-01',
      'sections': [
        ['一、我们收集的信息', '为向您提供借款服务，我们会收集您的手机号、姓名、身份证件信息、银行卡信息、设备信息（设备型号、操作系统、设备标识符）、位置信息（仅用于反欺诈核验）以及您在申请过程中主动填写的职业与收入信息。'],
        ['二、信息的使用', '上述信息仅用于身份核验、授信评估、反欺诈、借款发放、还款管理、争议处理及法律法规要求的其他用途。我们不会将您的信息用于与服务无关的用途。'],
        ['三、信息的共享', '除取得您的单独同意或法律法规另有规定外，我们不会向第三方共享您的个人信息。因放款、支付、征信等必要环节需向合作机构传输的，我们将以最小必要为原则，并要求其承担同等保密义务。'],
        ['四、信息的存储与保护', '您的个人信息存储于中华人民共和国境内，采用加密存储、访问控制、脱敏展示等措施。身份证号、银行卡号等敏感信息在数据库中以密文形式保存，展示时进行掩码处理。'],
        ['五、您的权利', '您有权查询、更正、复制、删除您的个人信息，有权撤回授权同意、注销账户。撤回同意不影响撤回前基于同意已进行的处理活动的效力。'],
        ['六、未成年人保护', '本服务仅面向年满 18 周岁且非在校学生的完全民事行为能力人。我们不会主动收集未成年人的个人信息。'],
        ['七、联系我们', '如您对本政策有任何疑问，可通过 App 内客服或客服热线 400-000-8888 与我们联系。'],
      ],
    },
    'personalInfo': {
      'title': '个人信息查询授权书',
      'updated': '2026-01-01',
      'sections': [
        ['授权范围', '本人同意并授权 UCash 及其合作机构，在本人申请授信、借款及贷后管理期间，向依法设立的征信机构、数据服务机构查询、使用本人的身份信息、信贷信息、履约信息及其他与信用评估相关的信息。'],
        ['授权用途', '上述信息仅用于本人授信额度评估、借款审批、风险定价、反欺诈识别、贷后管理及监管报送，不得用于其他用途。'],
        ['授权期限', '自本人签署之日起至本人授信额度终止或相关借款结清后五年止。法律法规另有规定的，从其规定。'],
        ['授权撤销', '本人可通过客服渠道书面申请撤销本授权，撤销后 UCash 将停止基于本授权的信息查询，但不影响撤销前已完成处理的信息。'],
        ['重要提示', '本人已充分理解本授权书的全部内容，知悉授权可能产生的法律后果，并自愿作出上述授权。'],
      ],
    },
    'loan': {
      'title': '借款合同（摘要）',
      'updated': '2026-01-01',
      'sections': [
        ['合同主体', '甲方（出借人）：UCash 合作持牌小额贷款公司；乙方（借款人）：本 App 实名认证用户。'],
        ['借款金额与期限', '以乙方在借款页面确认并经甲方审批通过的金额、期限为准，具体以《借款确认单》及还款计划表载明为准。'],
        ['利率与费用', '本合同项下借款执行年化利率（单利）按审批结果确定，综合年化利率（IRR）在借款页面明示。除合同约定利息外，甲方不收取任何砍头息、服务费、会员费等费用。'],
        ['还款方式', '等额本息，按月还款。每期应还本息金额以还款计划表为准。乙方应于每期还款日 24:00 前将足额款项存入还款账户。'],
        ['提前还款', '乙方可随时申请提前结清，甲方仅收取截至结清日的实际用款利息，不收取额外违约金（另有约定除外）。'],
        ['逾期责任', '乙方未按期还款的，自逾期之日起按日计收罚息，日罚息率为万分之五，罚息总额不超过逾期本金的 20%。同时可能影响乙方的征信记录。'],
        ['争议解决', '因本合同发生的争议，双方应协商解决；协商不成的，任何一方可向甲方所在地有管辖权的人民法院提起诉讼。'],
      ],
    },
    'credit': {
      'title': '征信授权书',
      'updated': '2026-01-01',
      'sections': [
        ['授权内容', '本人同意并授权 UCash 及其合作机构向中国人民银行金融信用信息基础数据库及其他依法设立的征信机构报送本人的信贷信息，包括但不限于授信额度、借款金额、还款记录、逾期信息。'],
        ['报送范围', '上述报送信息仅限本人与 UCash 及其合作机构之间发生的信贷业务相关信息。'],
        ['异议处理', '本人如对报送信息有异议，可通过客服渠道提出异议申请，UCash 将在收到异议之日起 20 日内完成核查并反馈处理结果。'],
      ],
    },
  };

  @override
  Widget build(BuildContext context) {
    final doc = _docs[type] ?? _docs['privacy']!;
    final sections = doc['sections'] as List<List<String>>;
    return Scaffold(
      backgroundColor: UColors.bg,
      appBar: UNavBar(title: doc['title'] as String),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
        children: [
          UCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(doc['title'] as String, style: UText.h3),
                const SizedBox(height: 6),
                Text('更新日期：${doc['updated']}', style: UText.tiny),
                const SizedBox(height: 16),
                ...sections.map(
                  (s) => Padding(
                    padding: const EdgeInsets.only(bottom: 16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(s[0], style: UText.body.copyWith(fontWeight: FontWeight.w600, fontSize: 14)),
                        const SizedBox(height: 6),
                        Text(s[1], style: UText.sub.copyWith(height: 1.7)),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
