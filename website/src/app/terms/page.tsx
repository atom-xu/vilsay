export const metadata = {
  title: "服务条款 - Vilsay",
  description: "Vilsay 服务条款：使用 Vilsay 产品和服务的条款与条件。",
};

export default function TermsPage() {
  return (
    <main className="mx-auto max-w-3xl px-4 py-16">
      <h1 className="text-3xl font-bold">Vilsay 服务条款</h1>
      <p className="mt-2 text-sm text-vilsay-text-secondary">
        最后更新：2026-03-27 &middot; 生效日期：2026-03-27
      </p>

      <p className="mt-6 text-vilsay-text-secondary">
        欢迎使用 Vilsay。以下条款（以下简称"本条款"）约束您对 Vilsay macOS
        应用程序及相关在线服务（以下统称"服务"）的使用。下载、安装或使用本服务即表示您同意受本条款约束。
      </p>

      {/* 1 */}
      <h2 className="mt-10 text-xl font-semibold">1. 服务说明</h2>
      <p className="mt-4 text-vilsay-text-secondary">
        Vilsay 是一款 macOS
        原生语音润色工具，提供以下核心功能：语音录制与识别（本地 Whisper +
        云端 Paraformer）、AI 文本润色（基于阿里云 Qwen
        大语言模型）、智能文字注入至当前应用程序。
      </p>

      {/* 2 */}
      <h2 className="mt-10 text-xl font-semibold">2. 账号</h2>
      <p className="mt-4 text-vilsay-text-secondary">
        您可以选择注册账号或通过第三方登录使用 Vilsay。您有责任保管好自己的账号凭据。我们有权在发现违规行为时暂停或终止您的账号。
      </p>

      {/* 3 */}
      <h2 className="mt-10 text-xl font-semibold">3. 免费版与 Pro 订阅</h2>

      <h3 className="mt-6 text-lg font-medium">3.1 免费版</h3>
      <p className="mt-2 text-vilsay-text-secondary">
        免费版用户享有每月有限次数的服务使用额度。免费版用户需自行提供阿里云 DashScope API Key 以使用云端润色和语音识别功能。
      </p>

      <h3 className="mt-6 text-lg font-medium">3.2 Pro 订阅</h3>
      <p className="mt-2 text-vilsay-text-secondary">
        Pro 订阅为按月自动续费的付费服务。Pro 用户可享受：
      </p>
      <ul className="mt-2 list-disc space-y-1 pl-5 text-vilsay-text-secondary">
        <li>由 Vilsay 提供的云端语音识别与润色服务，无需自备 API Key</li>
        <li>无月度使用次数限制</li>
        <li>优先获取新功能</li>
      </ul>

      <h3 className="mt-6 text-lg font-medium">3.3 计费与取消</h3>
      <p className="mt-2 text-vilsay-text-secondary">
        Pro 订阅通过 Apple App Store 内购（In-App Purchase）进行计费。订阅费用将从您的 Apple ID
        关联的支付方式中扣除。订阅将在每个计费周期结束时自动续费，除非您在当前周期结束前至少
        24 小时取消。取消后，您仍可在当前计费周期结束前继续使用 Pro 功能。
      </p>
      <p className="mt-2 text-vilsay-text-secondary">
        您可以在 macOS 系统设置 &gt; Apple ID &gt; 媒体与购买项目 &gt; 订阅
        中管理或取消订阅。
      </p>

      {/* 4 */}
      <h2 className="mt-10 text-xl font-semibold">4. 使用规范</h2>
      <p className="mt-4 text-vilsay-text-secondary">使用本服务时，您同意不会：</p>
      <ul className="mt-2 list-disc space-y-1 pl-5 text-vilsay-text-secondary">
        <li>以任何方式滥用、干扰或破坏服务的正常运行</li>
        <li>尝试逆向工程、反编译或反汇编本应用程序</li>
        <li>使用自动化工具批量调用服务 API（超出正常使用范围）</li>
        <li>利用本服务生成违反法律法规或公序良俗的内容</li>
        <li>转售、再许可或以商业目的分发本服务的访问权限</li>
      </ul>

      {/* 5 */}
      <h2 className="mt-10 text-xl font-semibold">5. 知识产权</h2>
      <p className="mt-4 text-vilsay-text-secondary">
        Vilsay 应用程序及相关服务的所有知识产权归 Vilsay
        团队所有。您通过本服务生成的润色文本内容的权利归您所有。
      </p>

      {/* 6 */}
      <h2 className="mt-10 text-xl font-semibold">6. 免责声明</h2>
      <p className="mt-4 text-vilsay-text-secondary">
        本服务按"现状"提供。AI
        润色结果基于大语言模型生成，仅供参考，不保证 100%
        准确性、完整性或适用性。您应在发布或使用润色结果前自行审核。
      </p>
      <p className="mt-2 text-vilsay-text-secondary">
        在法律允许的最大范围内，Vilsay
        不对因使用或无法使用本服务而产生的任何直接、间接、附带、特殊或后果性损害承担责任。
      </p>

      {/* 7 */}
      <h2 className="mt-10 text-xl font-semibold">7. 第三方服务</h2>
      <p className="mt-4 text-vilsay-text-secondary">
        本服务依赖阿里云 DashScope 提供 AI
        推理能力。使用自备 API Key 的用户需同时遵守阿里云的服务条款。Vilsay
        不对第三方服务的可用性或数据处理方式负责。
      </p>

      {/* 8 */}
      <h2 className="mt-10 text-xl font-semibold">8. 服务变更与终止</h2>
      <p className="mt-4 text-vilsay-text-secondary">
        我们保留随时修改、暂停或终止服务（或其任何部分）的权利。对于付费用户，我们将提前合理时间通知重大变更，并按比例退还未使用的订阅费用。
      </p>

      {/* 9 */}
      <h2 className="mt-10 text-xl font-semibold">9. 条款更新</h2>
      <p className="mt-4 text-vilsay-text-secondary">
        我们可能不时更新本条款。更新后的条款将在本页面发布，并更新"最后更新"日期。继续使用本服务即表示您接受更新后的条款。
      </p>

      {/* 10 */}
      <h2 className="mt-10 text-xl font-semibold">10. 适用法律</h2>
      <p className="mt-4 text-vilsay-text-secondary">
        本条款受中华人民共和国法律管辖。因本条款引起的任何争议，双方应友好协商解决；协商不成的，任何一方均有权向
        Vilsay 运营者所在地有管辖权的人民法院提起诉讼。
      </p>

      {/* 11 */}
      <h2 className="mt-10 text-xl font-semibold">11. 联系我们</h2>
      <p className="mt-4 text-vilsay-text-secondary">
        如有任何问题，请联系：
      </p>
      <p className="mt-2 text-vilsay-text-secondary">
        邮箱：
        <a href="mailto:support@vilsay.com" className="underline">
          support@vilsay.com
        </a>
      </p>
    </main>
  );
}
