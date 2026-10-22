# DSH Mobile

**鎶?[DeepSeek Harness](https://github.com/deepseek-ai/deepseek-harness)锛圖SH锛夋墦鍖呮垚涓€涓?Android APK锛氬畨瑁呫€佺偣鍥炬爣銆佺洿鎺ョ敤銆?*

涓嶉渶瑕佺數鑴戙€佷笉闇€瑕?Termux銆佷笉闇€瑕?root銆佷笉闇€瑕佸鍏?rootfs銆佷笉闇€瑕佺矘璐?token 鈥斺€?鎵€鏈夎繍琛屾椂锛圖ebian + Node.js + DSH 鏈綋锛夐兘鍦?APK 閲岋紝瀹夎鍖?894 MB銆?
![DSH Mobile 鍦ㄦ墜鏈轰笂杩愯](docs/images/screenshot-home.png)

---

## 杩欐槸浠€涔?
瀹樻柟 DSH 杩愯鏃舵敮鎸?Linux x64/arm64銆乵acOS銆乄indows锛?*娌℃湁 Android**銆傛湰椤圭洰鐢ㄤ竴鏉°€屽厤 root 鐨?Linux 鐢ㄦ埛绌洪棿銆嶈矾绾挎妸 DSH 鍘熸牱鎼埌鎵嬫満涓婏細

```
APK锛坅ssets 閲屽鐫€ Debian rootfs + Node 24 + DSH 婧愮爜锛?  鈹? 棣栨鍚姩锛氳В鍘嬪埌 App 绉佹湁鐩綍锛堢害 3 GB锛?  鈻?proot锛堢敤鎴锋€?chroot/ptrace锛屾棤闇€ root銆佹棤闇€鍐呮牳鏀寔锛?  鈹?  鈻?Debian 12 (aarch64, glibc)  鈫? Node.js 24  鈫? DSH web server (127.0.0.1:3080)
                                                    鈹?                                                    鈻?                                         App 鍐呯疆 WebView 鐩存帴鎵撳紑
```

瀹樻柟 DSH 鐨勭洰鏍囧钩鍙伴噷 **Linux arm64 + glibc 鏄敮鎸佺殑**锛岃€?Android 鑷甫鐨?Bionic libc 涓嶅吋瀹癸紙sharp銆乶ode-pty銆乶ative/system 绛夐兘浼氬穿锛夈€傛墍浠ュ涓€灞?Debian 灏辩瓑浜庢妸銆孉ndroid銆嶄吉瑁呮垚浜嗐€屽畼鏂规敮鎸佺殑 linux-arm64銆嶁€斺€?杩欐槸鏁存潯璺嚎鑳芥垚绔嬬殑鍏抽敭銆?
## 鐗规€?
- **鍗曟枃浠跺畨瑁?*锛氫竴涓?APK 鍖呭惈杩愯鏃?+ DSH锛岃瀹屽嵆鐢?- **闆堕厤缃?*锛氬惎鍔ㄦ椂鑷姩瑙ｅ帇 rootfs銆佽嚜鍔ㄥ惎鍔?proot/node銆佽嚜鍔ㄦ崟鑾?`dsh web: http://127.0.0.1:3080/?token=...` 骞舵墦寮€ WebView
- **涓嶉渶瑕?root**锛歱root 鏄敤鎴锋€佸疄鐜帮紝鏅€?App 鏉冮檺鍗冲彲
- **绂荤嚎鍙敤**锛氫笉渚濊禆浠讳綍杩滅▼鏈嶅姟鍣紙鍙€夊眬鍩熺綉琛ヤ竵閫氶亾闄ゅ锛?- **鍚庡彴淇濇椿**锛氬墠鍙版湇鍔?+ 甯搁┗閫氱煡锛屽垏鍚庡彴 / 浠庢渶杩戜换鍔″垝鎺夊悗 DSH 缁х画杩愯锛涢€氱煡閲屽彲鐩存帴鍋滄
- **鏃?WebView 鍏煎**锛氭敞鍏?ES2023/2024 polyfill锛坄Promise.withResolvers`銆乣AbortSignal.any` 绛夛級锛孉ndroid 8+ 鑰佸唴鏍镐篃鑳借窇 DSH 鍓嶇
- **淇琛ヤ竵鏈哄埗**锛氬唴缃?`assets/overlay` 瑕嗙洊灞?+ 鍙€?`patch.tar.gz` 灞€鍩熺綉琛ヤ竵锛屽皬淇涓嶇敤閲嶆柊鎵撳寘
- **鍙瘖鏂?*锛氬唴缃棩蹇楋紙鍚綉椤?console / JS 寮傚父 / WebSocket 鐢熷懡鍛ㄦ湡锛夛紝鎮诞銆屸嫰銆嶆寜閽殢鏃舵煡鐪嬨€佸鍒?
## 瀹夎

**涓嬭浇**锛歔Releases 椤甸潰](https://github.com/mutoharohfiqabcd-source/dsh-mobile/releases/latest) 閲岀殑 `DSH-Mobile-*.apk`锛堢害 894 MB锛?
1. 涓嬭浇 APK锛圧elease 璧勪骇锛?2. 鍏佽銆屽畨瑁呮湭鐭ユ潵婧愬簲鐢ㄣ€嶏紝瀹夎
3. 棣栨鎵撳紑浼氳姹傚瓨鍌ㄦ潈闄愶紙鍏佽鍚?DSH 鍙互璇诲啓鎵嬫満鏂囦欢锛夛紱瑙ｅ帇 rootfs 绾﹂渶 8鈥?5 鍒嗛挓
4. 瑙ｅ帇瀹屾垚鑷姩杩涘叆 DSH 鐣岄潰

**闇€瑕?*锛歛rm64 鎵嬫満銆丄ndroid 8.0+銆佺害 4 GB 绌洪棽绌洪棿锛圓PK 894 MB + 瑙ｅ帇鍚庣害 3 GB锛夈€?
> APK **涓嶅寘鍚换浣?API key / 璐﹀彿淇℃伅**锛岄娆′娇鐢ㄨ鍦?DSH 閲岀櫥褰曟垨閰嶇疆鑷繁鐨勬ā鍨嬨€?
## 鑷繁鏋勫缓

瀹屾暣姝ラ瑙?[docs/BUILD.md](docs/BUILD.md)銆傛瑕侊細

```powershell
# 0. 鍑嗗锛欽DK 17銆丄ndroid build-tools 34.0.0銆乸latform android-34
# 1. 浠?Termux 鍙栧嚭 proot 杩愯鏃讹紙proot / loader / libtalloc / libandroid-shmem锛?bash scripts/fetch-runtime.sh            # 鍦?Termux 閲岃窇锛屼骇鍑?apk/assets/runtime/
# 2. 鍙栧師鐢熸ā鍧楋紙flock 鐨?system.node / landlock-run锛屾潵鑷?npm锛?bash scripts/fetch-overlay.sh            # 浜у嚭 apk/assets/overlay/
# 3. 鍑嗗 rootfs.tar.gz锛圖ebian + Node + DSH锛岃 rootfs/ 涓嬬殑鑴氭湰锛?#    鏀惧埌 apk/rootfs-asset/rootfs.tar.gz
# 4. 鎵撳寘
powershell -ExecutionPolicy Bypass -File build-apk.ps1
# 浜х墿锛歞ist/DSH-Mobile.apk
```

娌℃湁 Gradle锛氭瀯寤洪摼鏄?`aapt2 鈫?javac 鈫?d8 鈫?杩藉姞 dex/rootfs 鈫?zipalign 鈫?apksigner`锛屽叏閮ㄦ墜鍐欏湪涓€涓?PowerShell 鑴氭湰閲岋紙鍘熷洜锛欰ndroid 涓婂彲鎵ц鏂囦欢蹇呴』鍦?targetSdk 鈮?28 鐨勫簲鐢ㄩ噷鐢ㄨ€佸紡鎵撳寘鏂瑰紡锛孏radle 閭ｅ鍦ㄨ繖閲屽弽鑰屾洿楹荤儲锛夈€?
## 宸茬煡闄愬埗

- 鍙湁 **arm64-v8a**锛堟病鏈?x86/armv7 鐨?rootfs锛?- rootfs 涓庡師鐢熸ā鍧楅兘鏄?`linux-arm64 + glibc`锛寈86 妯℃嫙鍣ㄨ窇涓嶄簡
- proot 鏈夋€ц兘寮€閿€锛堢害 10鈥?0%锛夛紝鑰楃數姣斿師鐢熼珮
- 鏋佺鎯呭喌涓嬬郴缁熶粛鍙兘鍥炴敹杩涚▼锛堢渷鐢电瓥鐣ャ€佷綆鍐呭瓨锛夛紱闀挎湡鍚庡彴浣跨敤寤鸿鎶?App 鍔犲叆鐢垫睜浼樺寲鐧藉悕鍗?- 894 MB 浣撶Н涓昏鏉ヨ嚜 rootfs锛堝鍒跺紡 node_modules锛夛紱鍚庣画鍙互鍋氬幓閲嶅帇缂?- 浠呯敤浜庝釜浜哄涔?鑷敤锛岄潪瀹樻柟 DSH 鍙戣鐗?
## 鐩綍缁撴瀯

```
apk/
  AndroidManifest.xml        # targetSdk 28锛堝叧閿細鍏佽 exec/dlopen 搴旂敤绉佹湁鐩綍锛?  src/com/dsh/mobile/        # MainActivity锛圵ebView+鏃ュ織妗ワ級銆丳rootServer銆丷untimeInstaller銆乀arGzExtractor
  res/                       # 鍥炬爣锛堝畼鏂?DSH favicon 娓叉煋锛夈€佸竷灞€銆佷富棰?  assets/
    polyfill.js              # ES2023/2024 polyfill
    instrument.js            # console/寮傚父/WebSocket 璇婃柇妗?    runtime/                 # proot 浜岃繘鍒讹紙鐢?scripts/fetch-runtime.sh 鐢熸垚锛?    overlay/                 # 鍘熺敓妯″潡瑕嗙洊灞傦紙鐢?scripts/fetch-overlay.sh 鐢熸垚锛?    rootfs.tar.gz            # 鐢?rootfs 鑴氭湰鐢熸垚鍚庢斁鍏ワ紙涓嶅叆搴擄級
rootfs/                      # 鍦?Termux 閲屾瀯寤?Debian+Node+DSH rootfs 鐨勮剼鏈?scripts/                     # 渚濊禆鑾峰彇銆佸浘鏍囨覆鏌撱€佹牎楠岃剼鏈?legacy/termux/               # 鏃╂湡銆孴ermux 閲岃窇銆嶆柟妗堬紝浠呭瓨妗ｅ弬鑰?docs/                        # 鏋勫缓銆佹灦鏋勩€佽俯鍧戣褰?build-apk.ps1                # 鏃?Gradle 鎵撳寘鑴氭湰
```

## 韪╁潙璁板綍

鏋勫缓杩欑被銆屾妸 Linux 杩愯鏃跺杩?Android銆嶇殑椤圭洰鏈変竴鍫嗗弽鐩磋鐨勫潙锛坱argetSdk銆乸root loader銆乣--link2symlink`銆乸npm workspace銆乤apt2 澶ц祫浜у帇缂┿€乄ebView 缂烘柊 API鈥︹€︼級锛岄兘鍐欏湪 [docs/LESSONS.md](docs/LESSONS.md) 閲屼簡锛屼簩娆″紑鍙戝墠寤鸿鍏堣銆?
## 璁稿彲璇?
鏈」鐩唬鐮佷互 [MIT](LICENSE) 鍙戝竷銆?
绗笁鏂圭粍浠跺悇鑷伒寰叾璁稿彲璇侊細
- **DeepSeek Harness**锛氳鍏朵粨搴撹鍙瘉锛涙湰椤圭洰鍙槸鎶婂畼鏂瑰彂琛屽唴瀹硅杩?APK
- **proot**锛圱ermux 鏋勫缓锛夛細GPL-2.0
- **Debian rootfs**锛氬悇杞欢鍖呭悇鑷殑璁稿彲璇侊紙涓昏涓?GPL/LGPL/BSD/MIT锛?- **Node.js**锛歁IT
- **鍥炬爣**锛氬彇鑷?DSH 瀹樻柟浠撳簱 `apps/web/public/favicon.svg`

鏈」鐩笌 DeepSeek 瀹樻柟鏃犲叧锛屼粎渚涘涔犵爺绌躲€?
## 鑷磋阿

- [deepseek-ai/deepseek-harness](https://github.com/deepseek-ai/deepseek-harness) 鈥?DSH 鏈綋
- [Termux](https://termux.dev) / [proot](https://proot-me.github.io) 鈥?鍏?root Linux 鐜
- [proot-distro](https://github.com/termux/proot-distro) 鈥?Debian rootfs 绠＄悊鎬濊矾
