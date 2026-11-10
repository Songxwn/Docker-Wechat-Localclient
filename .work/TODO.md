# TODO — Docker-Wechat-Localclient

> 状态唯一判据 = 本文件 checkbox。已完成事项移入「维护说明」指向 LESSONS/思源笔记,不在此堆积。

## 数据缺口 / 待办

- [ ] 上游 PR #2(Songxwn/Docker-Wechat-Localclient)合并 → 切回上游主线,retire fork 内 IME/剪贴板补丁(跟踪2/3/5);issue #3 随合并自动关闭
- [ ] **服务端版本观察(2026-11-09 盘点:无需更新)**:wechat-selkies 最新 = v0.0.17(2026-10-08,ghcr 数字 tag 封顶、releases 最新),容器已是最新;基镜像 linuxserver/baseimage-selkies:ubuntunoble = Python 老栈,上游 selkies-gstreamer 的 Rust 重写(crates/selkies)尚未被 wechat-selkies 跟进 → Portainer update stack 只会原地重拉同一镜像。触发条件 = 作者 rebase 新基镜像发新版(已提 issue #130);届时剪贴板协议不同,客户端接管方案需适配
- [ ] 推送图片 >16 MB:走服务端分片上传 verbs(`cbs/cbd/cbe`,协议已核实未实现)——有实际大图需求再做
- [ ] filebrowser 上游已归档(2026-09-01 起 no fix):出现可靠社区续作镜像时评估替换(卷结构兼容,只换 image)
- [ ] 思源笔记「客户端装法」命令随每次发版更新资产链接(当前 v5.6.5,已发 release 6 资产,iOS 因 CI runner 容量未附;装法命令已同步 v5.6.5)
- [x] v5.5.0/v5.5.1 FileBrowser 地址:表单填写→按钮显隐(配置+可达探测)→跳转,本地实测通过

## 待人工验证

- [x] 最大化窗口→WS 反复断开(2026-11-09):预设手动分辨率开+1280x720+HiDPI 关,复测修复。根治=客户端分辨率自动钳制已实现(resolutionClampScript,默认上限 1280x720,编辑连接可改)
- [x] v5.5.2 本机已装(2026-11-09):CI release 资产直装替换 `/Applications/wechat_selkies_client.app`,版本 5.5.1→5.5.2,启动进程已验(PID 存活)
- [ ] v5.5.2 装后复测:预设「手动分辨率」撤回「跟随服务端」,最大化窗口验证不再掉线
- [ ] QNAP 间歇瘫窗(2026-11-09 08:29-08:41 两次,13001/9000/13085 全 TCP 超时后自愈):用户已定位并修复,无需跟进
- [ ] v5.4.0/v5.5.0 资产在第二台机器安装跑通(macOS 资产名无版本号,外链脚本注意)
- [ ] filebrowser 首登改密已完成(初始密码出现在部署记录里)

- [x] 剪贴板接管(v5.6.5,文字+图片实机验证通过):`clipboard_in_enabled` 保持 true(否则自家推送被丢弃)、`clipboard_out_enabled`/`clipboard_seamless` pin false、页面自动读用 `clipboard.read*` 拦截;图片按 0.0.17 老版协议 `cbs/cbd/cbe`(无 tid)每片 256KB 分片;服务端加 `SELKIES_ENABLE_BINARY_CLIPBOARD=true`

## 维护说明

- 踩坑细节 = 思源笔记「wechat-selkies 部署笔记」踩坑记录节;可复用结论 = 本目录 `LESSONS.md`
- `.work/` 入库随 repo 同步(台账内不含凭证;涉密细节只进思源笔记,思源不进本仓)
- 发版流程:f bump pubspec → tag → `gh workflow run build.yml --ref vX.Y.Z`(tag push 触发在本 fork 失效,见 LESSONS 2026-11-08)
- 部署事实源:Portainer stack 40(wechat-selkies + filebrowser 侧车);思源笔记部署节 compose 与线上逐字一致
