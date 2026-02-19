---
title: "Xsession/ログインセッション と systemd/cgroups"
emoji: ""
type: "tech" # tech: 技術記事 / idea: アイデア
topics: ["linux", "systemd", "cgroups", "X11"]
published: true
---


# 概要

Linuxディストリビューションを利用していると，例えばユーザーランドに限っても自分のマシンで動作しているアプリケーション/プロセスのすべてを理解できているわけがないので，小さな問題に当たったときにどこから問題を考えればよいのか悩むことが多くあります．
そのような時の理解の助けとして，systemdおよびcgroupsの階層構造と，Xsession/ログインセッションを念頭において状況を整理すると，全体的なプロセスの流れを立体的にとらえることができ，問題の早期解決につながることがありました．

しかし，ここではsystemd/cgroupsおよびXsession/ログインセッションを同時に扱うため，なんとなくでも双方に知識がないとかえって理解し辛い可能性がある点に注意してください．
ただし，両面からプロセスの流れを見ることにより，より立体的に構造をみることができるようになって，全体的な理解が進むと思いました．

**注意**
筆者はXやWaylandについて明るくありません．
多分に推察を含むことや，単語や表現が正しくない可能性が多分にあることに注意してください．
また，ここではWaylandおよびXWaylandについても一切触れません．


# 筆者の環境について

まずOSはFedora 43です．
Display managerはlightdmを使っていて，そこからWindow managerとしてi3を起動しています．

記事の内容に関わる主要なソフトウェアのバージョンを以下に示します．
```bash
$ rpm -q kernel systemd lightdm
kernel-6.17.9-300.fc43.x86_64
systemd-258.3-2.fc43.x86_64
lightdm-1.32.0-22.fc43.x86_64
```

筆者環境においてi3上で起動した特定のアプリケーションでibusへの入力がうまくいかない問題がありました．
その調査でXsessionの起動の流れを追いかける際に，Xsessionとcgroupsの関連の知識が役にたちました．その周辺について調査したことを書いています．


<!-- sliceとscopeの違いと，例えばkitty, tmuxなどが自分でscopeを生成してプロセスを管理していることは別の記事で触れる予定． -->

# 前提知識

**注意**
以下の内容は概要のため，意図的にぼやかした書き方をしています．

## Xsession(ログインセッション) とは

LinuxにおいてGUIな環境を提供するための歴史的なコンポーネントとしてX Window Systemがあります．
GUIがターゲットに設定されたシステムを起動すると，まずdisplay managerが起動します．私の環境ではlightdmです．
このlightdmがGUI環境のブートローダのような役割を果たします．まずはXserverを起動します．このXserverがGUIの下地を提供します．
lightdmはその後，いわゆるログイン画面を表示し，私たちはそこにユーザー名/パスワードを入力してマシンにログインすることになります．
これによってlightdmが，実際にGUI操作に使うWindow manager，私の環境ではi3を起動し，マシンの操作をGUIで快適に行えるようにしてくれます．

このユーザーログインのときlightdmは，Xsessionという概念に分けてユーザーをログインさせ，またi3を起動しています．
このように，多数のユーザーや，多数の環境に対して個別にX環境を提供できるようにするために分けられたものがXsessionといい，システム内で管理されています．
<!-- 例えばこのとき，'ctrl+alt+F2' あたりを押して別のVCを開いてlightdmからログインすると，新たなXsessionが生成され，分けて管理されることになります． -->

Xsessionは`loginctl`コマンドによってその情報を確認できます．
なお，`loginctl`で管理されるセッションはXに限らずログインセッション全般を含みます．本記事では，loginctlで管理されるセッションを広く「ログインセッション」と呼び，そのうちX上で動作するもの(Type: x11)を「Xsession」と呼ぶことにします．
例えば，lightdmからログインしてi3が起動された状態で，以下のようにログインセッションを確認します．

```bash
$ loginctl list-sessions
SESSION  UID USER      SEAT  LEADER CLASS   TTY IDLE SINCE
      2 1000 khwarizmi seat0 1981   user    -   no   -
      3 1000 khwarizmi -     2098   manager -   no   -

2 sessions listed.
```

SESSION 2がまさしく先ほど説明したXsessionになっています．
詳細や，SESSION 3は何であるかなどについては後述します．


## 理解しておきたいcgroupsとsystemdな要素

cgroupsは，プロセスをグループにまとめて管理できるもので，またリソース制限なども含めた包括的な管理をすることができます．
現時点でcgroupsv2が使われています．またsystemdはcgroupsを全面的に活用しており，両者は密に連携しています．
ここではその正確な説明はしません．

cgroupsは階層構造になっており，その構造は`systemd-cgls`コマンドで確認できます．

一般的なシステム(少なくとも私のfedora43環境)では，最上位には以下のようなグループがあります．
 - user.slice
 - system.slice
 - init.scope

それぞれの説明については省略します．
user.sliceが名前のとおり，ユーザーごとにプロセスを管理してくれそうなsliceで，以降はこの範囲で説明を続けます．

実際の私の環境で，/user.slice 配下の階層構造は以下のとおりになっています．
※表示する深さを指定するオプションがないため，出力結果は加工しています．

```bash
$ systemd-cgls /user.slice --no-pager
CGroup /user.slice:
└─user-1000.slice
  ├─user@1000.service …
  │ ├─session.slice
  │ │ ├─(...)
  │ ├─kitty-4357-0.scope
  │ │ ├─(...)
  │ ├─init.scope
  │ │ ├─2098 /usr/lib/systemd/systemd --user
  │ │ └─2100 (sd-pam)
  └─session-2.scope
    ├─  1981 lightdm --session-child 13 20
    ├─  2116 i3
```
詳細な説明は省きますが，.sliceはその下にさらに階層構造を作っていくための区分で，.scopeはプロセスをひとまとめにグループ化するための単位です．
数字から始まっている行はプロセスを表します．当然数字はPIDです．

例えば上記の例において上から8行目に`2098 /usr/lib/systemd/systemd --user`というプロセスがありますが，これはその階層構造から，
`/user.slice/user-1000.slice/user@1000.service/init.scope`という階層構造の下に属するプロセスだ．という意味です．
この`systemd --user`は，systemdのユーザーインスタンスと呼ばれるプロセスで，ユーザーがログインした際にそのユーザー向けのサービスを管理します．
またこのinit.scopeはsystemdプロセス自体が配置される階層で，ここではsystemdのユーザーインスタンスが配置されています．


# Xsession(ログインセッション)をcgroupsの階層構造と比較しながら解釈する．

ここでもう一度，現在のログインセッションのリストを確認し，先ほどの階層構造との関連性を見ていきます．

```bash
$ loginctl list-sessions
SESSION  UID USER      SEAT  LEADER CLASS   TTY IDLE SINCE
      2 1000 khwarizmi seat0 1981   user    -   no   -
      3 1000 khwarizmi -     2098   manager -   no   -

2 sessions listed.
```

"CLASS"というフィールドがそのセッションが何者であるかを理解するのを助けます．
セッション2は，CLASSが"user"になっていることからも分かるとおり，ユーザーが利用するためのXsessionです．
セッション3は，CLASSが"manager"になっています．これはsystemdのユーザーインスタンス，すなわち`systemd --user`に対応するものです．

"LEADER"の値はPIDで，俗っぽくいうと，そのセッションのリーダーとなるプロセスといったところでしょうか．そのセッションを開始したプロセスと読み替えてもいいと思います．
実際にセッション2, 3のLEADERのPIDを，先ほどのsystemd-cglsの結果と見比べてみます．

## セッション2

まずセッション2です．LEADERのPIDは1981です．このPIDをもつプロセスとそこまでの階層構造は以下のとおりになっています．
※systemd-cglsコマンドの出力から抜粋
```bash
CGroup /user.slice:
└─user-1000.slice
  └─session-2.scope
    ├─  1981 lightdm --session-child 13 20
    ├─  2116 i3
```
`session-2.scope`の配下の`lightdm`のプロセスです．
つまり，lightdmのログイン処理を通じて新たなXsessionが作られ，またその対応するcgroupsの階層`session-2.scope`も作られたと考えてよさそうです．
厳密には，lightdmが起動した時点でXsessionおよびsession-2.scopeが作られていると考えるべきだとは思います．
i3上でアプリケーションを起動すると，このsession-2.scopeの下にどんどんプロセスが追加されていきます．
**注意** ただしこれには例外があります．今はその例外については扱いません．

ここで，このセッションの情報を見てみようと思います．
`loginctl session-status`コマンドで確認することができます．
```bash
$ loginctl session-status 2 --no-pager
2 - khwarizmi (1000)
  Since: Tue 2026-02-17 23:40:38 JST; 10h ago
  State: active
 Leader: 1981 (lightdm)
   Seat: seat0; vc1
Display: :0
 Remote: no
Service: lightdm
   Type: x11
  Class: user
Desktop: i3
   Idle: no
   Unit: session-2.scope
         ├─  1981 lightdm --session-child 13 20
         ├─  2116 i3
         ├─  (...)

(ログは省略)
```
一番下のUnit部分に，先ほど対応すると話したsession-2.scopeが示されており，プロセスツリーも表示されています．

## セッション3

次にセッション3です．LEADERのPIDは2098です．このPIDをもつプロセスとそこまでの階層構造は以下のとおりになっています．
※systemd-cglsコマンドの出力から抜粋
```bash
CGroup /user.slice:
└─user-1000.slice
  ├─user@1000.service …
  │ ├─session.slice
  │ │ ├─(...)
  │ ├─kitty-4357-0.scope
  │ │ ├─(...)
  │ ├─init.scope
  │ │ ├─2098 /usr/lib/systemd/systemd --user
  │ │ └─2100 (sd-pam)
```
さきほど確認した`systemd --user`のプロセスです．
つまり，systemdのユーザーインスタンスが起動される流れの中で新たなログインセッションが生成されているということになります．
ただ残念ながら，init.scopeはセッション3に対応するcgroupsの階層かというと違います．
init.scopeは，systemdプロセスを配置する階層で，ログインセッションとは関係ありません．
また，実際にsystemdのユーザーインスタンス`systemd --user`によって起動された各サービスは，`session.slice`の配下に属します．

こちらもログインセッションの情報を確認してみます．
```bash
$ loginctl session-status 3 --no-pager
3 - khwarizmi (1000)
  Since: Tue 2026-02-17 23:40:38 JST; 10h ago
  State: active
 Leader: 2098 (systemd)
 Remote: no
Service: systemd-user
   Type: unspecified
  Class: manager
   Idle: no
```
こちらにはセッション2にあったUnitの行がありません．
対応するcgroupsの階層もなく，またそのためプロセスツリーも表示されません．


# 別のVCからログインして新たなログインセッションを生やしてみる

例えば`ctrl+alt+F2`などを押下すると，別のVirtual Consoleに切り替えることができます．
CUIからログインだけして，特になにもせずにGUIに戻ってログインセッションを確認してみます．
```bash
$ loginctl list-sessions
SESSION  UID USER      SEAT  LEADER CLASS   TTY  IDLE SINCE
      2 1000 khwarizmi seat0 1981   user    -    no   -
      3 1000 khwarizmi -     2098   manager -    no   -
      5 1000 khwarizmi seat0 14198  user    tty2 no   -

3 sessions listed.
```
非常におもしろいことにセッション5が新しく生えています．
"TTY"が"tty2"になっており，仮想コンソールが接続されているのでこれはコンソール接続(CUI)だということがわかります．

systemd-cglsも見てみます．
```bash
$ systemd-cgls /user.slice --no-pager
CGroup /user.slice:
└─user-1000.slice
  ├─user@1000.service …
  │ ├─session.slice
  │ │ ├─(...)
  │ ├─kitty-4357-0.scope
  │ │ ├─(...)
  │ ├─init.scope
  │ │ ├─2098 /usr/lib/systemd/systemd --user
  │ │ └─2100 (sd-pam)
  ├─session-2.scope
  │ ├─  1981 lightdm --session-child 13 20
  │ ├─  2116 i3
  │ ├─  (...)
  └─session-5.scope
    ├─ 14198 login -- khwarizmi
    └─145156 -bash
```
session-5.scopeが，session-2.scopeと同じ階層にできており，その中にプロセスが属しています．
ログインしただけなので，ログイン処理をしたloginとその後起動されたbashしかプロセスがなく，非常にわかりやすいです．

ログインセッションの情報も見ておきます．
```bash
$ loginctl session-status 5
5 - khwarizmi (1000)
  Since: Wed 2026-02-18 22:01:56 JST; 48min ago
  State: online
 Leader: 14198 (login)
   Seat: seat0; vc2
    TTY: tty2
 Remote: no
Service: login
   Type: tty
  Class: user
   Idle: yes since Wed 2026-02-18 22:02:00 JST (48min ago)
   Unit: session-5.scope
         ├─ 14198 "login -- khwarizmi"
         └─145156 -bash

(ログは省略)
```

# システム起動後，lightdmのログイン画面が表示された段階の状態はどうなっているのか

本記事の中で次のような発言をしました．
> つまり，lightdmのログイン処理を通じて新たなXsessionが作られ，またその対応するcgroupsの階層`session-2.scope`も作られたと考えてよさそうです．

ところで，Xsessionはlightdmのログイン処理を通じて生成されますが，lightdmのプロセス自身もそのセッションのcgroupsの階層の中に入っていました．
そして，Xsessionを生成するタイミングが，ログイン情報を入力してenterを押した直後なのだとしたら，その前のログイン画面が表示されているだけの段階のときはlightdmのプロセスはどの階層にいるのでしょうか．またXsessionはほんとうにまだその段階では生成されていないのでしょうか．

実験してみたいと思います．手順は以下のとおりです．
まずはマシンを再起動して一度まっさらな状態にします．(i3からログアウトしてlightdmのログイン画面に戻るだけでもいいかもしれませんが)
この状態で，`ctrl+alt+F2`などを押下して別のVCに入りCUIでログイン，その後`loginctl`でログインセッションを確認します．

この状態であれば，lightdmからログインしていないため，Xsessionはないと期待できます．
しかし直感的にはすこしまずいことが起こりそうです．詳しい説明は省きますが，ログインセッションごとにseatで入出力を管理などしていますが，実際にlightdmが起動した時点でXserverは起動しているのですから，その管理はどのように行っているのかなどの疑問があります．
私の予想としては，その時点では仮となるログインセッションを生成しているのではないかと思っています．
そしてログイン情報が入力された段階でそのユーザー向けのXsessionを作るのではないでしょうか．

実際にやってみます．
`loginctl list-sessions`コマンドの結果は以下のとおりでした．
```bash
$ loginctl list-sessions
SESSION  UID USER      SEAT  LEADER CLASS         TTY   IDLE SINCE
      1  990 lightdm   -     1593   manager-early -     no   -
      2 1000 khwarizmi seat0 1991   user          tty2  no   -
      3 1000 khwarizmi -     2063   manager       -     no   -
     c1  990 lightdm   seat0 1542   greeter       -     no   -

4 sessions listed.
```

非常におもしろいことがわかりました．
まず，セッション2はCUIからのログインセッション，セッション3はsystemdのユーザーインスタンス`systemd --user`に相当するログインセッションであり，これは既知です．
以下のセッション情報も示しておきます．
セッション2
```bash
$ loginctl session-status 2 --no-pager
2 - khwarizmi (1000)
  Since: Wed 2026-02-18 23:14:33 JST; 1min 26s ago
  State: active
 Leader: 1991 (login)
   Seat: seat0; vc2
    TTY: tty2
 Remote: no
Service: login
   Type: tty
  Class: user
   Idle: no
   Unit: session-2.scope
         ├─  2051 "login -- khwarizmi"
         ├─  2127 -bash
         └─  2215 loginctl session-status 2 --no-pager

(ログは省略)
```
セッション3
```bash
$ loginctl session-status 3 --no-pager
3 - khwarizmi (1000)
  Since: Wed 2026-02-18 23:14:33 JST; 1min 26s ago
  State: active
 Leader: 2107 (systemd)
 Remote: no
Service: systemd-user
   Type: unspecified
  Class: manager
   Idle: no
```

それ以外に，セッション1・c1というものもあります．USERがlightdmになっているため，予想はある程度当たっていると思っていいと思います．

セッション1・c1の情報も記載します．

セッション1
```bash
$ loginctl session-status 1 --no-pager
1 - lightdm (990)
  Since: Wed 2026-02-18 23:14:33 JST; 1min 26s ago
  State: active
 Leader: 1593 (systemd)
 Remote: no
Service: systemd-user
   Type: unspecified
  Class: manager-early
   Idle: no
```
セッションc1
```bash
$ loginctl session-status c1 --no-pager
c1 - lightdm (990)
  Since: Wed 2026-02-18 23:14:33 JST; 1min 26s ago
  State: online
 Leader: 1542 (lightdm)
   Seat: seat0; vc1
Display: :0
 Remote: no
Service: lightdm-greeter
   Type: x11
  Class: greeter
   Idle: no
   Unit: session-c1.scope
         ├─  1542 lightdm --session-child 17 20
         └─  1765 /usr/bin/lightdm-gtk-greeter

(ログは省略)
```

まずセッションc1については，`lightdm-gtk-greeter`が動作しているため，ログイン画面を表示するためのセッションだと思って間違いなさそうです．
Serviceも`lightdm-greeter`に，Classも`greeter`になっています．

セッション1は，Serviceが`systemd-user`となっているため，`systemd --user`に相当するlightdm向けのものと思って良いかと思います．
ただ，Classが`manager-early`となっているので，初期準備用とかなにかしらの違いはありそうです．

/user.slice配下のcgroupsの階層構造も見ておきましょう．
```bash
$ systemd-cgls /user.slice --no-pager
CGroup /user.slice:
├─user-990.slice
│ ├─session-c1.scope
│ │ ├─  1542 lightdm --session-child 17 20
│ │ ├─  1765 /usr/bin/lightdm-gtk-greeter
│ └─user@990.service …
│   ├─session.slice
│   │ ├─(...)
│   ├─app.scope
│   │ ├─(...)
│   ├─init.scope
│   │ ├─1593 /usr/lib/systemd/systemd --user
│   │ └─1616 (sd-pam)
└─user-1000.slice
  ├─user@1000.service …
  (...)
```
UID990，すなわちlightdm向けのsliceができています．
c1のログインセッションに対応する`session-c1.scope`も生えていますね．プロセスツリーも先ほど見た情報と同じです．
`init.scope`内に`systemd --user`のプロセスもありますね．
Classが`manager-early`となっているような，なにか通常のユーザー向けの`systemd --user`と区別されているような情報は，少なくともぱっと見ではわかりませんでした．
ただ，これによって起動されるサービスは基本的に`session.slice`の配下に生えるので，通常のユーザーがログインした際の`session.slice`配下のプロセスツリーと比較してみると，もしかしたら差分があるかもしれないですね．ここではそこまでは追わないことにします．

# lightdmのプロセスの流れを追う

最後に，この状態のlightdmのプロセスがどのようになっているかを少しだけ追っておきたいと思います．
ここまではcgroupsのプロセスツリーを見てきました．
例えば先ほどのlightdmのログイン前の状態では，lightdmユーザーのsliceの配下にログイン画面を表示しているプロセス(lightdm-greeter)がありました．
lightdmユーザーの範囲だと突然このプロセスが生えてきたように見えますが，当然まずはsystemdがsystemのmanagerとしてlightdmのデーモンを立ち上げて，そこからlightdmのログイン画面の子プロセスを生成している流れが予想できます．
その流れを実際に確認しておきましょう．

先ほどの，GUIではまだログインしておらず，CUIからログインしていた状態で，`ps f`コマンドでプロセスツリーを見てみます．fをつけると親子関係を表示してくれます．
※lightdm関連の出力のみ抜粋．
```bash
$ ps auxf
(...)
root        1468  0.0  0.0 379468  7676 ?        Ssl  09:58   0:00 /usr/sbin/lightdm
root        1505  0.1  0.2 523652 79960 tty1     Ssl+ 09:58   0:46  \_ /usr/libexec/Xorg -core -noreset :0 -seat seat0 -auth /run/lightdm/root/:0 -nolisten tcp vt1 -novtswitch
root        1542  0.0  0.0 179692 13812 ?        Sl   09:58   0:00  \_ lightdm --session-child 17 20
lightdm     1765  0.2  0.2 1726928 93752 ?       Ssl  10:10   0:00  │   \_ /usr/bin/lightdm-gtk-greeter
root        1933  0.0  0.0  23300 10000 ?        S    09:58   0:00  \_ lightdm --session-child 13 20
lightdm     1593  0.0  0.0  23856 14712 ?        Ss   10:10   0:00 /usr/lib/systemd/systemd --user
(..以下，systemd --userによって起動されたサービスのため割愛)
(...)
```

まず，PID1468は起動時にsystemdによって起動されたlightdmのデーモンと思われます．あとでcgroupsを見て確認しましょう．
その子プロセスとしてXorg(Xserver)があるので，やはりlightdmのデーモンが起動した時点でXが起動しています．
またPID1468の子プロセスとして1542のlightdmの子プロセスがあり，こちらは配下に`lightdm-gtk-greeter`すなわちログイン画面のプロセスがあります．
このプロセスから実行ユーザーがlightdmに切り替わっており，cgroupsの階層的にも1542のプロセスは`/user.slice/user-990.slice/session-c1.scope`配下にあることを以前確認していますね．
現時点ではPID1933のlightdmの子プロセス何に該当するのか不明ですが，あとで明らかになります．

では，このpsのプロセスツリーと見比べる形でcgroupsの階層構造をみてみたいと思います．
```bash
$ systemd-cgls / --no-pager
CGroup /:
├─user.slice
  (...)
├─init.scope
  (...)
├─system.slice
  (...)
  ├─lightdm.service
  │ ├─  1468 /usr/bin/lightdm
  │ ├─  1505 /usr/libexec/Xorg -core -noreset :0 -seat seat0 -auth /run/lightdm/root/:0 -nolisten tcp vt1 -novtswitch
  │ └─  1933 lightdm --session-child 13 20
```

いままで触れてきませんでしたが，systemdが起動するサービスユニットは`system.slice`配下に位置しています．
`lightdm.service`があり，配下に先ほど確認した1468, 1505が含まれています．

さて，1933のプロセスも確認したいですが，その前に今この状態でGUIからログインしたあとの`ps f`コマンドの結果を見てください．
```bash
$ ps auxf
root        1468  0.0  0.0 379468  7676 ?        SLsl 09:58   0:00 /usr/sbin/lightdm
root        1505  0.1  0.2 523652 79960 tty1     Ssl+ 09:58   0:46  \_ /usr/libexec/Xorg -core -noreset :0 -seat seat0 -auth /run/lightdm/root/:0 -nolisten tcp vt1 -novtswitch
root        1933  0.0  0.0 179692 13812 ?        Sl   09:58   0:00  \_ lightdm --session-child 13 20
khwariz+    3211  0.0  0.0 226928 23752 ?        Ssl  10:10   0:00      \_ i3
khwariz+    3392  0.0  0.0   8668  1800 ?        Ss   10:10   0:00          \_ /usr/bin/ssh-agent /bin/sh -c exec -l /bin/bash -c "i3"
khwariz+    3421  0.0  0.0 306156  6376 ?        Ssl  10:10   0:00          \_ xss-lock --transfer-sleep-lock -- i3lock --nofork
khwariz+    3422  0.0  0.1 1321356 41388 ?       Ssl  10:10   0:01          \_ nm-applet
khwariz+    3423  0.0  0.0  97408 16088 ?        Ssl  10:10   0:13          \_ i3bar --bar_id=bar-0 --socket=/run/user/1000/i3/ipc-socket.3211
khwariz+    3432  0.0  0.0   2588  1912 ?        S    10:10   0:04              \_ i3blocks
```

注目したいのは，1933のlightdmの子プロセスの配下に，i3が生えていることがわかります．
つまりlightdm起動時点からあったこのプロセスは，ログインされたあとにユーザーセッションを用意するために事前に起動していたプロセスであったことがわかりました．

