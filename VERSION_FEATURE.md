# 软件升降级

主面板管理区新增“软件升降级”，仅 App Store 应用显示。中文列表展示当前版本、历史版本和内部版本 ID；选择后确认安装。新文件 ADVersionController.m 已加入 Xcode 的 AppData Sources。

参考用户实测全部功能可用的 com.iosdump.appdata 2.7.5（SHA256 cab015fc1f8634d924bda946af99c7136550b9115470136b379d86797a5950b9）。通过 arm64/arm64e 静态分析重写源码，没有把参考包的二进制加入项目。

- 查询应用：itunes.apple.com/lookup，核对 bundleId 后读取 trackId。
- 查询历史：iosdump.apdoilaan.work/history/{trackId}，读取 data 数组中的 external_identifier、version、created_at。
- 账号检查：SSAccountStore 当前有效账号，与应用旁 iTunesMetadata.plist 的购买账号比较；安装前再次检查。
- 主安装：AppStoreDaemon / ASDPurchase / ASDPurchaseManager startPurchase:withResultHandler:，使用 appExtVrsId 请求选中版本。
- 回退：StoreKitUI / SKUIItemOffer / SKUIItem / SKUIItemStateCenter，复用参考包的字段和调用。
- 回调仅标记请求已提交，不声明安装已完成。

适配区别：不接入参考包的第三方账号切换插件，而是提示用户自行切换购买账号后刷新；不包含禁用更新功能。查询错误可刷新、请求超时25秒、历史记录过滤无效/重复版本ID、接口缺失和KVC异常均显示中文反馈。区域查询使用设备区域与 cn/us/hk/tw/jp/gb 回退列表；并非逐项复刻参考版本所有地区。

version-check.yml 只检查 Xcode 工程格式并使用 Apple SDK 编译新增控制器的 arm64/arm64e 对象，不构建完整 deb，也不验证真实 App Store 服务调用。完整项目仍依赖原 MonkeyDev 构建环境，打包时必须重新编译 AppDataPrefs，不能使用仓库中的旧英文预编译设置程序。待真机验证：列表请求、账号状态、安装主路径/回退、实际版本变化及关闭返回。
