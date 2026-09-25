// =============================================================================
//  GithubToken —— 检查更新用的仓库访问令牌
// =============================================================================
//
//  这一行现在是**空的**，而它是量出来的结论，不是偷懒。两条事实（2026-09-25 实测，
//  `curl` 直打 GitHub API，命令与返回都记在下面，谁都能复算）：
//
//   ① 上一版写进去的那把令牌**无效**。用户报的第 9 条就是它：界面上弹出一整块
//      原始 JSON ——`{"message":"Bad credentials","status":"401"}`。
//      实测：
//        curl -H "Authorization: Bearer <那把 key>" https://api.github.com/user
//        → HTTP 401  {"message": "Bad credentials"}
//        curl -H "…" https://api.github.com/repos/monsm/CarInfo  → HTTP 401
//      形状是完整的（`github_pat_` + 82 个字符，共 93），但 GitHub 不认 ——
//      过期、被吊销、或者复制时错了一个字符，这三种在服务端是同一种回答。
//      **无法从客户端补救**：本地没有任何办法把它变成一把好令牌。
//
//   ② 更要紧的一条：**这个仓库是公开的**，所以检查更新根本不需要令牌。
//      实测（同一个时刻，完全不带 Authorization 头）：
//        curl https://api.github.com/repos/monsm/CarInfo
//        → 200,  "private": false, "visibility": "public"
//        curl https://api.github.com/repos/monsm/CarInfo/releases/tags/latest
//        → 200, 附件 CarKeeper-unsigned.ipa（2544318 字节）、CarKeeper-unsigned.zip
//      GitHub 的 releases 接口对公开库匿名可读 —— 私库才会 404。
//      这一条推翻了本文件上一版的其中一句假设（「本仓 monsm/CarInfo 是私库」）：
//      那时它确实是私库，或者当时没核。现在核了，是公开库。
//
//  ⚠️ 顺带纠正一个此前记进文档的判断：用户曾说「我的是私库和个人 ipa，没有任何泄露」。
//  后一半成立（ipa 只自己侧载），前一半不成立（匿名能读到这个仓库的 Release）。
//  这不改变「要不要令牌」的结论，但改变「令牌泄露了会怎样」的结论 —— 而现在
//  这一行是空的，所以这条账上没有任何东西可泄露。
//
//  留着这一个空位而不是把整个机制删掉，理由只有一条：**匿名有配额**
//  （60 次/小时/IP）。哪天限流了（403），在这里放一把 fine-grained、只读该仓库的
//  令牌就立刻恢复，**改动只有这一行** —— `UpdateService.githubToken` 只是它的只读转发。
//
//  令牌为空**不是错误路径**：`fetchLatestRelease` 只是不带 Authorization 头去打
//  同一个地址（见 `UpdateService`）。所以「没配令牌」这句话已经从界面上消失了 ——
//  它此前会让按钮按下去只吐一句「暂时无法检查更新」。
// =============================================================================

enum GithubToken {
    /// 令牌本体。**留空 = 匿名访问**（当前状态，够用）。
    /// 形状是 `github_pat_…`（fine-grained）或 `ghp_…`（经典）。填进去只为一个理由：匿名限流。
    static let value = ""
}
