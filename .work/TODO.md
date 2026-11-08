# TODO — Docker-Wechat-Localclient

> 状态唯一判据 = 本文件 checkbox。已完成事项移入「维护说明」指向 LESSONS/思源笔记,不在此堆积。

## 数据缺口 / 待办

- [ ] 上游 PR #2(Songxwn/Docker-Wechat-Localclient)合并 → 切回上游主线,retire fork 内 IME/剪贴板补丁(跟踪2/3/5);issue #3 随合并自动关闭
- [ ] 推送图片 >16 MB:走服务端分片上传 verbs(`cbs/cbd/cbe`,协议已核实未实现)——有实际大图需求再做
- [ ] filebrowser 上游已归档(2026-09-01 起 no fix):出现可靠社区续作镜像时评估替换(卷结构兼容,只换 image)
- [ ] 思源笔记「客户端装法」命令随每次发版更新资产链接(当前 v5.4.0 / `WeChat-Selkies-macos.zip`)

## 待人工验证

- [ ] v5.4.0 资产在第二台机器安装跑通(macOS 资产名已改无版本号,外链脚本注意)
- [ ] filebrowser 首登改密已完成(初始密码出现在部署记录里)

## 维护说明

- 踩坑细节 = 思源笔记「wechat-selkies 部署笔记」踩坑记录节;可复用结论 = 本目录 `LESSONS.md`
- `.work/` 入库随 repo 同步(台账内不含凭证;涉密细节只进思源笔记,思源不进本仓)
- 发版流程:f bump pubspec → tag → `gh workflow run build.yml --ref vX.Y.Z`(tag push 触发在本 fork 失效,见 LESSONS 2026-11-08)
- 部署事实源:Portainer stack 40(wechat-selkies + filebrowser 侧车);思源笔记部署节 compose 与线上逐字一致
