---
title: "systemd-cglsで眺めるアプリ・VM用のcgroups階層"
emoji: ""
type: "tech" # tech: 技術記事 / idea: アイデア
topics: [linux, systemd, cgroups]
published: true
---

# 概要

[前回](https://zenn.dev/khwarizmi6514/articles/20260218-xsession-cgroups)の記事で，プロセスがcgroupsの階層構造で管理されている様子をsystemd-cglsコマンドを用いて観察しました．
またその際に，Xsessionやログインセッションと比較しながら観察を行ったため，ユーザーのログインとプロセスの動きの流れが少し立体的に見えるようになってきました．

今回は，前回の記事では触れなかった少しかわったcgroupsの階層で管理されているプロセス群がありましたので，それらのプロセス群などについて情報を集めていきます．

# /user.slice配下の階層構造の全体見直し

現在のログインセッションは以下のとおりです．
```
$ loginctl list-sessions
SESSION  UID USER      SEAT  LEADER CLASS   TTY IDLE SINCE
      3 1000 khwarizmi -     2063   manager -   no   -
      4 1000 khwarizmi seat0 1933   user    -   no   -

2 sessions listed.
```

あらためて/user.slice配下のcgroupsの階層構造を見てみます．
※以下の出力は見やすいように加工しています．
```
CGroup /user.slice:
└─user-1000.slice
  ├─user@1000.service …
  │ ├─session.slice
  │ │ └─(...)
  │ ├─tmux-spawn-a6b70c95-89a4-4915-913d-84fc42c6602b.scope
  │ │ ├─  6259 -bash
  │ │ └─375449 systemd-cgls /user.slice --no-pager
  │ ├─tmux-spawn-286a4385-c380-4292-9a16-1a866d1345ea.scope
  │ │ ├─  6425 -bash
  │ │ └─(...)
  │ ├─kitty-6181-0.scope
  │ │ ├─6201 /bin/bash --posix
  │ │ ├─6256 tmux -L zenn new
  │ │ └─6258 tmux -L zenn new
  │ ├─app.slice
  │ │ ├─(...)
  │ └─init.scope
  │   ├─2063 /usr/lib/systemd/systemd --user
  │   └─2066 (sd-pam)
  └─session-4.scope
    ├─  1933 lightdm --session-child 13 20
    ├─  3211 i3
    ├─  6181 kitty
    └─(...)
```

まずは前回確認した内容をおさらいしていきます．
先ほど確認したログインセッション(=Xsession)4にあたるcgroupsの階層は `session-4.scope` で，lightdmやi3のプロセスが見えます．kittyを起動しているのにも意味がありますがこれは後述します．
次に，/user.slice/user-1000.slice/user@1000.service 配下に `init.scope` があって，ユーザー向けのsystemdなプロセスを管理するscopeで，実際にPID2063でsystemdのユーザーインスタンスが起動されており，同じ /user.slice/user-1000.slice/user@1000.service 配下にある `session.slice` に，実際にsystemdのユーザーインスタンスで起動されたユーザー向けのサービスが管理されているのでした．

今回確認したいのは，それ以外の部分です．

# 独自のcgroups階層を生成してプロセス管理するソフトウェア
まずは以下の部分に注目します．

```
CGroup /user.slice:
└─user-1000.slice
  │ ├─tmux-spawn-a6b70c95-89a4-4915-913d-84fc42c6602b.scope
  │ │ ├─  6259 -bash
  │ │ └─375449 systemd-cgls /user.slice --no-pager
  │ ├─tmux-spawn-286a4385-c380-4292-9a16-1a866d1345ea.scope
  │ │ ├─  6425 -bash
  │ │ └─(...)
  │ ├─kitty-6181-0.scope
  │ │ ├─6201 /bin/bash --posix
  │ │ ├─6256 tmux -L zenn new
  │ │ └─6258 tmux -L zenn new
  │ ├─app.slice
  │ │ ├─(...)
  └─session-4.scope
    ├─  6165 /bin/bash
    ├─  6181 kitty
```

`kitty-6181-0.scope` に注目します．

kittyは私が普段利用しているターミナルエミュレータです．詳細は省略します．
/user.slice/user-1000.slice/session-4.scope配下にPID6181でkittyが動作しているのが確認できます．
上述したとおりkittyはターミナルエミュレータであるため，その中でシェルはもちろん起動したコマンドを実行するプロセスが多数forkされていることが期待されます．

そのようなkitty配下で動作するプロセスをまとめるためのcgroupsの階層が用意されています．
`/user.slice/user-1000.slice/user@1000.service/kitty-6181-0.scope`です．6181は親となるkittyのPIDでしょう．後ろの0はタブ/ウィンドウ番号でしょうか．
そしてそのkitty-6181-0.scope配下に，bashやその配下で起動したコマンドのプロセスが並んでいるのが確認できます．

実際のプロセスの親子関係とも比較できるように，`ps xf`の結果からkittyのプロセスツリーを抜き出したものを下に示しておきます．
```
   6165 ?        S      0:00 /bin/bash
   6181 ?        Sl     4:39  \_ kitty
   6199 ?        Sl     0:06      \_ /usr/bin/kitten __atexit__
   6201 pts/0    Ss     0:00      \_ /bin/bash --posix
   6256 pts/0    S+     0:00          \_ tmux -L zenn new
```

さらにtmuxを動作させており，tmux用のscopeも用意されているのがわかります．
`/user.slice/user-1000.slice/user@1000.service/tmux-spawn-*.scope`です．おそらくセッションのUUIDがscope名についているのだと思います．
こちらも同様に，そのtmuxのセッションの中で起動したプロセスがこのscope配下で管理されています．

このように，ターミナルエミュレータやマルチプレクサのようなアプリケーションは，独自のcgroups階層(scope)を生成してプロセスを管理することがあるようです．


# 簡単にapp.sliceにふれておく

前節で独自のcgroups階層を生成するソフトウェアについて触れましたが，一般的なソフトウェアが利用する(ことができる)sliceがあるようなので簡単に触れておきます．

```
$ systemd-cgls --no-pager /user.slice/user-1000.slice/user@1000.service/app.slice
CGroup /user.slice/user-1000.slice/user@1000.service/app.slice:
├─app-dbus\x2d:1.19\x2dorg.a11y.atspi.Registry.slice
│ └─dbus-:1.19-org.a11y.atspi.Registry@0.service
│   └─3892 /usr/libexec/at-spi2-registryd --use-gnome-session
├─app-com.google.Chrome-4452.scope
│ ├─  4452 /opt/google/chrome/chrome
│ ├─  4993 /opt/google/chrome/chrome --type=utility --utility-sub-type=audio.mojom.AudioService --lang=en-US --service-sandbox-type=none --crashpad-handler-pid=4459 --enable…
│ └─241561 /opt/google/chrome/chrome --type=utility --utility-sub-type=video_capture.mojom.VideoCaptureService --lang=en-US --service-sandbox-type=none --message-loop-type-u…
├─app-dbus\x2d:1.2\x2dcom.redhat.imsettings.slice
│ └─dbus-:1.2-com.redhat.imsettings@0.service
│   ├─3302 /usr/libexec/imsettings-daemon
│   ├─4308 /usr/bin/ibus-daemon -r --xim
│   └─(...)
├─dconf.service
│ └─4309 /usr/libexec/dconf-service
├─app-dbus\x2d:1.2\x2dorg.freedesktop.portal.IBus.slice
│ └─dbus-:1.2-org.freedesktop.portal.IBus@0.service
│   └─4329 /usr/libexec/ibus-portal
└─xdg-desktop-portal-gtk.service
  └─4408 /usr/libexec/xdg-desktop-portal-gtk
```

`/user.slice/user-1000.slice/user@1000.service/app.slice`です．
少なくとも私の環境では上記のようなプロセスがその配下に存在していました．
dbusやデスクトップ関連ぽいデーモンがいくつかあるほか，chromeのプロセスが見えるのが特筆事項でしょうか．

実はchromeのプロセスはログインセッション(Xsession)のスコープにもあったので何らかの役割分担がされていそうですが，app.slice配下はデーモン的?なプロセスで，ログインセッション(Xsession)配下のプロセスは各ウィンドウとかタブとかのプロセスなのかなと思いました．(これは想像です．)

この記事ではあまり深堀りしないことにします.. が追加でちょっとだけ．

https://systemd.io/DESKTOP_ENVIRONMENTS/#xdg-standardization-for-applications
上はsystemdのドキュメント "Desktop Environments" へのリンクです．
まずこのドキュメントは，本記事公開時点で `NOTE: This document is a work-in-progress.`  とある点に注意してください．

リンクが示す"XDG standardization for applications" には，先ほどのみた `app-*` というプレフィックスを持つユニットに関する情報が書いてあります．
XDGなというかデスクトップなというか，そういうアプリケーション向けのなんらかの統合の施策の試みがあるのかなというところです．

次に一つ章を戻って
https://systemd.io/DESKTOP_ENVIRONMENTS/#pre-defined-systemd-units
"Pre-defined systemd units" では，先ほどの `app.slice` を含むいくつかのsliceユニットに関する情報が書いてあります．
少なくとも私の環境では `background.slice` はありませんでした．

どうやらこのグルーピングでは事前に優先度やリソースの重み付けなどがデフォルトでついており，アプリケーションを適切なsliceに配置することでその恩恵を享受できるといったもののようです．
具体的に私の環境で確認してみると，以下のようにCPUWeightが100に設定されていることは確認できました．

```
$ systemctl --user show app.slice -p CPUWeight,MemoryMax,MemoryHigh,IOWeight,TasksMax
CPUWeight=100
IOWeight=[not set]
MemoryHigh=infinity
MemoryMax=infinity
TasksMax=infinity
```

# 仮想マシン用のcgroups階層

話は大きく変わりますが，仮想マシン用のcgroups階層もありましたのでそれについても触れておきます．

```
$ systemd-cgls --no-pager /machine.slice
CGroup /machine.slice:
└─machine-qemu[machine-name].scope …
  └─libvirt
    ├─6823 /usr/libexec/virtiofsd --fd=24 --shared-dir [/path/to/dir]
    ├─6842 /usr/bin/qemu-system-x86_64 -name guest=(...) ...
    ├─vcpu1
    ├─vcpu0
    └─emulator
```

`/machine.slice`という階層があって，仮想マシン用のcgroups階層として利用されているようです．

[systemd.specialのmanページの"Special Slice Units"](https://www.freedesktop.org/software/systemd/man/latest/systemd.special.html?__goaway_challenge=meta-refresh&__goaway_id=876f8fc1dda0b3418b6a0c4ad40ca0a8&__goaway_referer=https%3A%2F%2Fgemini.google.com%2F#Special%20Slice%20Units) には以下のように説明があって，
> By default, all virtual machines and containers registered with systemd-machined are found in this slice. This is pulled in by systemd-machined.service.

systemd-machinedによって管理(登録)される仮想マシンやコンテナはこの配下に属するようです．
私の環境ではKVM(libvirt+qemu)を利用しているので，それらがsystemd-machinedとうまく連携しているようですね．
また，私の環境では一台の仮想マシンを動作させているので，`/machine.slice`配下に一つのscopeができていますね．複数台立てるとこれが横に伸びていく感じでしょうか．

仮想マシン全体へのリソース分配や，仮想マシンごとへのリソース分配などがうまくできそうです．

例としてあまりよくなかったですが，PID6823でvirtiofsdのプロセスがあるのがわかります．実はホストマシンの特定のディレクトリをゲストマシンに見せています．
PID6842の方がメインになるqemuのプロセスですね．またその配下にvcpu1, vcpu0, emulatorなどがありますが，これはPID6842のqemuのプロセスを親とするスレッドです．

psコマンドでPID6842のスレッド状況を見てみると以下のようになっていました．
```
$ ps  -Lp 6842
    PID     LWP TTY          TIME CMD
   6842    6842 ?        00:00:38 qemu-system-x86
   6842    6849 ?        00:00:00 qemu-system-x86
   6842    6851 ?        00:00:06 vhost-6842
   6842    6852 ?        00:00:00 IO mon_iothread
   6842    6853 ?        00:05:18 CPU 0/KVM
   6842    6854 ?        00:06:46 CPU 1/KVM
   6842    6857 ?        00:00:00 kvm-nx-lpage-re
```

先ほど見たのはvcpu1, vcpu0, emulatorと3つでしたが，スレッドはそれよりも多そうですね．
少しだけ確認したところ，どうやらcgroupsにはスレッドモード(threaded mode)というスレッド単位で個別のcgroups階層に配置できる機能があるようで，ここではそれが使われているのではないかというところでした．
これに関しては次回以降の記事で扱うことにして，今回はこの辺りでおしまいにしたいと思います．

# 参考リンク

- systemd . "Desktop Environments" . https://systemd.io/DESKTOP_ENVIRONMENTS/
- systemd . "The New Control Group Interfaces" aka I want to make use of kernel cgroups, how do I do this in the new world order?” . https://systemd.io/CONTROL_GROUP_INTERFACE/
- systemd\.special . https://www.freedesktop.org/software/systemd/man/latest/systemd.special.html

<!-- *リンクのメモ* -->
<!-- - freedesktop.org配下のsystemd関連の情報を全部obligatedな感じがある．https://www.freedesktop.org/wiki/Software/systemd/ -->
<!--   - freedesktop\.org . "Pax Controla Groupiana" aka "How to behave nicely in the cgroupfs trees" . https://www.freedesktop.org/wiki/Software/systemd/PaxControlGroups/ -->
<!--   - 歴史的経緯を追っていくのはよさそう -->

