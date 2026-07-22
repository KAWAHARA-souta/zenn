---
title: "Podmanのrootless containerの基本理解"
emoji: ""
type: "tech"
topics: []
published: true
---


# 本記事の概要

PodmanはDockerと同様にコンテナを管理するためのツールです．公式ドキュメントの冒頭では次のように説明されています．

> Podman is a daemonless, open source, Linux native tool designed to make it easy to find, run, build, share and deploy applications using Open Containers Initiative (OCI) Containers and Container Images.
> (中略)
> Containers under the control of Podman can either be run by root or by a non-privileged user.
> — [What is Podman? — Podman documentation](https://docs.podman.io/en/stable/index.html#what-is-podman)

ここで挙げられている `daemonless` および `can either be run by root or by a non-privileged user`(特権/非特権ユーザーのどちらからでも実行できること)は，Podmanを特徴付ける代表的な2つの要素です．特に後者(非特権ユーザーでの実行)は，一般的に `rootlessコンテナ` とも呼ばれます．

Podmanが `daemonless` であるということは，本来root権限を持つdaemonが担っていたコンテナ実行時のセットアップ処理を，コマンドを実行したプロセス自身が行わなければならない，ということでもあります．そしてこの処理を非特権ユーザーのまま行えるようにする仕組みこそが，rootlessコンテナを成立させています．

本記事では，この `rootlessコンテナ` を成立させている仕組みについて調査を行います．

# 本記事の注意

Podmanのrootlessコンテナの説明のためにDockerとの差分について観察する箇所がありますが，Dockerは特別な設定をせずにデフォルトのまま使うことを想定しています．
具体的には，現在ではDockerをrootless modeで動作させることで，daemon設計の差分はそのままながらも，Dockerでもrootlessコンテナを利用することは可能で，その場合には本記事のような差分が確認できない可能性があるため注意してください．
 参考: [Docker Docs - Rootless mode](https://docs.docker.com/engine/security/rootless/)

この記事では，Podmanのrootless containerの実現方法の理解に注力することとし，技術要素(とくにuser namespace)の深堀りは別記事で行う予定です．

また，筆者の環境は以下のとおりです．
```
$ cat /etc/fedora-release
Fedora release 43 (Forty Three)
$ uname -r
6.17.9-300.fc43.x86_64
$ rpm -q kernel podman
kernel-6.17.9-300.fc43.x86_64
podman-5.7.1-1.fc43.x86_64
```

# daemonless

Podmanの大きな特徴の1つに，daemon(常駐プロセス)を持たないことが挙げられます．これはコンテナを起動・管理する方式そのものに関わる設計上の違いです．

Dockerはclient/serverモデルを採用しています．ユーザーが docker コマンドを実行すると，そのコマンドはクライアントとして動作し，バックグラウンドで常駐しているdockerd(daemon)にUnixソケット等を介して指示を送ります．
実際のコンテナプロセスの生成は，この dockerd の管理下で行われます．
一方Podmanはfork/execモデルを採用しており，常駐するdaemonを持ちません．podman コマンドの管理下でコンテナプロセスが生成されます．

このモデルの違いについて，Podman開発チームのDan Walsh氏は次のように説明しています．

> Podman uses a traditional fork/exec model for the container, so the container process is an offspring of the Podman process.
> (中略)
> Using a fork/exec container runtime for launching containers (instead of a client/server container runtime) allows you to maintain better security through audit
> logging.
>  — [Podman: A more secure way to run containers](https://opensource.com/article/18/10/podman-more-secure-way-run-containers)

この違いは，実際にホスト上でのプロセスの様子を確認することで裏付けることができます．
「コンテナプロセスがどのユーザーの権限で動作しているか」を確認してみます．

## Podman上で起動したコンテナプロセスのツリー確認

まず，わたしの環境では現在以下のようなコンテナが動作しています．このコンテナのプロセスがホストマシン上でどのように見えているかを確認しましょう．
それからpodmanコンテナを起動したユーザーのuidを確認しておきましょう．
起動のログは省略しますが，以下に示す`1000`がこのユーザーのuidで，これは非常に典型的な一般ユーザーのuidです．

```
  $ podman ps
  CONTAINER ID  IMAGE                       COMMAND           CREATED         STATUS         PORTS                   NAMES
  9303f272194a  localhost/zenn_zenn:latest  npx zenn preview  15 minutes ago  Up 15 minutes  0.0.0.0:8000->8000/tcp  zenn_zenn_1
  $ id -u
  1000
```

このコンテナのPIDは以下のように取得できます．

```
  $ podman inspect --format '{{.State.Pid}}' zenn_zenn_1
  845833
```

ホストマシン上でのPIDは`845833`であることが分かったので，このPIDのプロセスがどうなっているか確認を進めましょう．
`pstree`コマンドで確認してみます．
```
  $ pstree -s 845833
  systemd───conmon───npm exec zenn p─┬─MainThread───10*[{MainThread}]
                                     └─10*[{npm exec zenn p}]
  $ pstree -p -s 845833
  systemd(1)───conmon(845831)───npm exec zenn p(845833)─┬─MainThread(845851)─┬─{MainThread}(845852)
                                                        │                    ├─{MainThread}(845853)
                                                       (..以下スレッド数だけ出力が続く..)
```

-pオプションをつけるとスレッド数分だけ出力されるので出力は省略しています．
pstreeコマンドが環境にない場合は，`ps`コマンドなどでも代用して親子関係を見ることができます．
```
  $ ps -o pid,ppid,uid,comm xf | grep -A4 845831
  845831       1  1000 conmon
  845833  845831  1000  \_ npm exec zenn p
  845851  845833  1000      \_ MainThread
  (..省略..)
```

これらの出力を見てわかる通りで，コンテナのプロセスは `conmon(845831)` の子プロセスになっており，さらに親をたどるとどうやら `systemd(1)` が祖先のようです．
ここで，conmonというプロセスおよびコンテナのプロセスのuidがどうなっているかを確認してみます．
```
  $ ps -o pid,ppid,uid,comm -p 845831,845833
   PID     PPID    UID  COMMAND
   845831       1  1000 conmon
   845833  845831  1000 npm exec zenn p
```

uidが`1000`になっています．これは先ほど確認した，コンテナを起動した一般ユーザーのuidです．

また，cgroups的にどのような階層にこのプロセスが存在するかも確認しておきましょう．
`systemd-cgls`を使って確認してみます．
※階層全体を眺めておきたいため階層指定なしで全体を示します．コンテナプロセスに関わる階層と補助的情報のみが見えるように出力は整形しています．
```
  $ systemd-cgls --no-pager
  CGroup /:
  -.slice
  ├─user.slice
  │ ├─user-0.slice
  │ │ └─user@0.service …
  │ │   └─init.scope
  │ │     ├─411626 /usr/lib/systemd/systemd --user
  │ │     └─411629 (sd-pam)
  │ └─user-1000.slice
  │   ├─user@1000.service …
  │   │ ├─user.slice
  │   │ │ ├─user-libpod_pod_7bdc7e210d3215c36959a67c68b4a68fa0cda7c535e0effd5344618a2e125d81.slice
  │   │ │ │ ├─libpod-conmon-<コンテナID>.scope
  │   │ │ │ │ └─845831 /usr/bin/conmon --api-version 1 -c <コンテナID> -u <コンテナID>
  │   │ │ │ └─libpod-<コンテナID>.scope
  │   │ │ │   └─container
  │   │ │ │     ├─845833 npm exec zenn preview
  │   │ │ │     └─845851 node /work/node_modules/.bin/zenn preview
  │   │ │ ├─rootless-netns-a9c58c65.scope
  │   │ │ │ └─845790 /usr/bin/pasta --config-net --pid /run/user/1000/containers/networks/rootless-netns/rootless-netns-conn.pid --dns-forward 169.254.1.1 (...)
  │   │ │ └─podman-pause-d4a0f089.scope
  │   │ │   └─742091 catatonit -P
```

参考 `/user.slice/user-1000.slice/user@1000.service/user.slice` の階層のみ表示
```
  $ systemd-cgls --no-pager /user.slice/user-1000.slice/user@1000.service/user.slice
  CGroup /user.slice/user-1000.slice/user@1000.service/user.slice:
  ├─user-libpod_pod_7bdc7e210d3215c36959a67c68b4a68fa0cda7c535e0effd5344618a2e125d81.slice
  │ ├─libpod-conmon-<コンテナID>.scope
  │ │ └─845831 /usr/bin/conmon --api-version 1 -c <コンテナID> -u <コンテナID>
  │ └─libpod-<コンテナID>.scope
  │   └─container
  │     ├─845833 npm exec zenn preview
  │     └─845851 node /work/node_modules/.bin/zenn preview
  ├─rootless-netns-a9c58c65.scope
  │ └─845790 /usr/bin/pasta --config-net --pid /run/user/1000/containers/networks/rootless-netns/rootless-netns-conn.pid --dns-forward 169.254.1.1 (...)
  └─podman-pause-d4a0f089.scope
    └─742091 catatonit -P
```



## Docker上で起動したコンテナプロセスのツリー確認

Docker環境で適当なコンテナを起動させます．
```
  $ docker run -d --name test alpine:latest sleep infinity
  $ docker ps
  CONTAINER ID   IMAGE           COMMAND            CREATED         STATUS         PORTS     NAMES
  a8444d0fd9e1   alpine:latest   "sleep infinity"   3 minutes ago   Up 3 minutes             test
```

この環境でもコンテナを起動したユーザーのuidを確認しておき，またコンテナのホスト側でのPIDを確認しておきます．
```
  $ id -u
  1000
  $ docker inspect --format '{{.State.Pid}}' test
  13676
```

pstree と ps の結果を示します．
```
  $ pstree -p -s 13676
  systemd(1)───containerd-shim(13652)───sleep(13676)
  
  $ ps -o pid,ppid,uid,comm axf | grep -A4 13652
    13652       1     0 containerd-shim
    13676   13652     0  \_ sleep
```
Dockerの場合は，`containerd-shim` というプロセスが間に挟まっているようですね．

さて，uidを確認します．
```
  $ ps -o pid,ppid,uid,comm -p 13652,13676
      PID    PPID   UID COMMAND
    13652       1     0 containerd-shim
    13676   13652     0 sleep
```
Podmanのときと比較して，`containerd-shim`および`sleep`プロセスがどちらもuid 0になっていることが確認できます．

Docker環境でも，`systemd-cgls`の結果を確認してみましょう．
```
  $ systemd-cgls --no-pager
  Control group /:
  -.slice
  ├─user.slice (#1208)
  │ └─user-1000.slice (#3718)
  │   ├─user@1000.service … (#3796)
  │   │ └─init.scope (#3835)
  │   │   ├─1527 /usr/lib/systemd/systemd --user
  │   │   └─1529 (sd-pam)
  ├─init.scope (#24)
  │ └─1 /usr/lib/systemd/systemd --switched-root --system --deserialize 31
  └─system.slice (#63)
    ├─containerd.service … (#5046)
    ├─dbus-broker.service (#2392)
    ├─docker.service … (#5102)
    │ └─13444 /usr/bin/dockerd -H fd:// --containerd=/run/containerd/containerd.sock
    ├─docker-a8444d0fd9e130c2f59f14aa0e15e76dde8b83e127ae590eb5c8e2d888528ecf.scope … (#5214)
    │ └─13676 sleep infinity
```

出力の最後の方にかかれている`system.slice`配下を見てください．
まず，`docker.service`が動作しているのが分かります．そしてそこと同列になるように，起動したコンテナ向けのscopeがあり，その配下にコンテナ内で動作しているプロセスがあることが分かります．


## Podman環境とDocker環境の差分に関する考察

コンテナ内のプロセスの権限(UID)の見え方について
- Podmanでは，**コンテナを起動したユーザーのUID**がそのままコンテナのプロセスにもついていた
- Dockerでは，**コンテナを起動したユーザーによらず**root(UID: 0)でコンテナのプロセスが動作していた
  - ※起動方法によってroot(UID: 0)以外でも起動することはできますが，ここでは「コンテナを起動したユーザーによらない」という点が重要です．

cgroupsを見ても，似たような情報を見ることができました．
- Podmanでは，**コンテナを起動したユーザー**の`user.slice`配下に所属していた
- Dockerでは，**コンテナを起動したユーザーによらず**`system.slice`配下に所属していた


# Docker・Podmanのコンテナ環境の作り方の違いとuser namespace

## 強力なdocker.service・dockerグループの権限

さて，すでに話しているとおりで，Dockerではdocker.service(dockerd)というデーモンをroot権限で起動する必要があります．
コンテナを起動するためにはdockerコマンドを利用しますが，dockerコマンドはdockerグループに所属している必要があります．root権限で動作するdockerdと通信するためのUnixソケット(docker.sock)へのアクセス権を持つグループで，dockerdへの命令を介してrootの振る舞いができる強い権限です．

Docker公式ドキュメントでも次のように明記されています．
> The docker group grants root-level privileges to the user.
> — [Post-installation steps for Linux — Docker Docs](https://docs.docker.com/engine/install/linux-postinstall/)


さて，なぜDockerコンテナを起動するためにはこのように強い権限が必要なのでしょうか．

ここでnamespaceについて少しだけ理解を深める必要があります．
namespaceはLinuxのリソース分割のための機能で，コンテナごとの隔離環境を作るためにDockerでもPodmanでも利用されている機能です．
`unshare`コマンド(システムコール)を使うと手元のシェルでも簡単にnamespaceを切ることができることで有名ですが..

```
$ id -u
1000
$ unshare --net bash
unshare: unshare failed: Operation not permitted
```

上記は試しにnetwork namespaceを切ってみるようにunshareコマンドを実行してみた例ですが，権限の問題によってうまく実行できなかったことが分かります．
このように，namespaceの操作には特定のCapabilityが必要で，十分なコンテナ隔離環境を用意するためにはほとんどrootに近い権限が必要になります．
このためDockerでは，このように強力な権限が必要な操作をDockerdによって実行し，十分に隔離されたコンテナ環境を用意する必要がありました．
  ※もちろん，namespace以外にも様々な機能が使われていますが，それでも強力な権限が必要なことは変わりません．

ここでPodmanに関して疑問が生じます．
Podmanでは，このような強力な権限をもったデーモンは存在せず，また一般ユーザーから平気でコンテナを起動することができていました．これはどういうことなのでしょうか．

## Podmanとuser namespace，そしてrootlessコンテナ

結論からいうと，`user namespace`という特殊なnamespaceを利用しています．
`user namespace`は，namespaceのリソース分割という観点で見ると，uid・gidテーブルを分割するという意味でリソース分割を担うものです．
が，`user namespace`はその特性から，リソース分割よりも，namespace全体に権限管理モデル機能を追加したものと考えると理解しやすいと思います．

`user namespace`についての詳しい説明は別の記事で扱う予定です．

ここで重要な点は以下の2点です．
- `user namespace`の作成は一般ユーザーでも行うことができる
- 自身が作成した`user namespace`内ではrootとして振る舞うことができる

Podmanではこの`user namespace`を利用することにより，ホストマシンでroot権限がなくてもnamespace作成を行って隔離コンテナ環境のセットアップを行うことができるようになっています．
 ※namespace作成以外にも越えなければならないハードルはありますが，ここではそこまで扱いません．

そしてこれこそがrootlessコンテナそのものです．
rootlessコンテナという単語には様々な意味やとらえ方があると思いますが，もっとも本質的には，「動作にホストマシンの特権が一切必要ないコンテナ」でしょう．
前述の実例でみたように，Dockerの単純な例ではrootに近い権限が必要でした．Podmanでは`user namespace`を採用し，一切の特権を必要とせずにリソースの分離を実現しています．

# user namespaceとuid map・権限分離の簡単な確認

さて，ここでは少しだけ`user namespace`の技術的な理解に踏み込んで見ようと思います．

再度注意ですが，ここでは`user namespace`および`namespace`の技術的理解にはあまり踏み込まず，別記事にまとめる予定です．
しかし，`user namespace`を活用したrootlessコンテナ技術を扱う以上，コンテナ内での振る舞いを大まかに理解しておくためにuid mapを簡単にでも理解すること，またリソース分離(セキュリティ)性を体感しておくことは重要だと思うため，簡単に触れておく必要があると考えてこの章を書いています．

## user namespaceとuid map

`user namespace`を利用した隔離(コンテナ)環境では，コンテナ内のプロセスの見え方が，ホスト側から見たときとコンテナ内から見たときで大きな差分があります．
まずはそれを観察しましょう．

まずは新しい`user namespace`を作成しましょう．

```
(ホスト)$ unshare --user --map-root-user bash
(コンテナ)# echo $$
1468205
```

上記のとおりにunshareコマンドを打つことで新たな`user namespace`を作成することができます．
unshareコマンドはそのまま新たなbashプロセスを起動してくれるため，コンテナ内でシェルを叩くことができる状態となります．
なおそのコンテナ内のシェルのPIDは`1468205`でした．このPIDのプロセスが，ホスト側から見たときとコンテナ内から見たときで見え方がどう違うかを見ていきます．

なお，この章では上記のように，プロンプトの前に `(ホスト)` または `(コンテナ)` というprefixをつけることとします．
`(ホスト)` というprefixは，そのコマンドが，unshareコマンドを実行していないホスト側の環境で実行されたことを示します．
`(コンテナ)` というprefixは，そのコマンドが，unshareコマンドを実行したコンテナ(隔離)環境で実行されたことを示します．

では，psコマンドでホストおよびコンテナそれぞれの環境からのプロセスの見え方を確認しましょう．UIDに注目です．
```
(ホスト)$ ps -o pid,uid,comm -p 1468205
    PID   UID COMMAND
1468205  1000 bash

(コンテナ)# ps -o pid,uid,comm -p 1468205
    PID   UID COMMAND
1468205     0 bash
```
ホスト側から見た場合には，uid 1000，すなわちコンテナを起動したユーザーのプロセスに見えています．
それに対して，コンテナ内から見た場合には，uid 0，すなわちrootのプロセスとして見えているのです．

このように，ホスト側とコンテナ内でuidの見え方が違ってきます．
そしてこれは，`/proc/<PID>/uid_map`という`user namespace`のインタフェースによってそのマッピングが管理されています．

```
$ cat /proc/1468205/uid_map
         0       1000          1
```

一要素目の0は，コンテナ内のUID，二要素目の1000は，ホスト側のUIDを表します．
つまり，「コンテナ内のUID 0は，ホスト側ではUID 1000として扱う」というマッピングを表しています．
※三要素目は範囲を示しますが，ここでは説明は割愛します．
※ちなみに，unshareコマンドの`--map-root-user`オプションは，この一行のマッピングを追加するためのオプションでした．

冷静に`user namespace`について考え直すと，「uid・gid空間を分離する」ためのものですからこの差分は自然なものですが，その具体的な効果がこの様に現れることを理解しておくのは非常に重要です．

## user namespaceの権限分離性の確認

`user namespace`の権限分離性についても簡単に確認しておきます．

先ほど見た通りで，`user namespace`はuid・gid空間を分離するもので，具体的な効果として例えば，ホスト側から見ると一般ユーザーだが，ある`user namespace`内ではrootであるという状況を作り出すことができます．

ところで，先ほど`user namespace`を分離した例では以下のようにunshareコマンドを実行していました．
```
(ホスト)$ unshare --user --map-root-user bash
```

すなわち，`user namespace`だけを分離しているため，ほかのnamespaceを分離していません．
同じrootfsを共有していて，PID空間も一緒のためホストの全プロセスが見え，ネットワークインタフェースもホストと同じものが見え.. などなどuid・gid空間以外はすべてがホストマシンと同じものが見えています．

user namespace内でroot権限を持っているために，コンテナから見えているものに対してroot権限でアクセスできると誤解してしまいそうですが，それは違うということを明確に確認しておきます．

確認方法は簡単で，明らかにホストマシンでroot権限を持っていないとアクセスできなそうなリソースにアクセスしてみましょう．
例えば以下のように
```
  (コンテナ)# cat /etc/shadow
  cat: /etc/shadow: Permission denied

  (コンテナ)# mount -t tmpfs tmpfs /mnt
  mount: /mnt: permission denied.
         dmesg(1) may have more information after failed mount system call.
```

`/etc/shadow`は明らかにホスト側のroot権限を持っていないと参照できないファイルでしょう．
コンテナ内ではrootに見えても，所詮ホスト側からはただの一般ユーザーであるためちゃんと`Permission denied`で弾かれます．
また，`mount namespace`も分離していませんから，mountも試してみますが，当然ながらホストのmount namespaceに対する十分な権限がないため`Permission denied`で弾かれます．

このように，ある`user namespace`内でrootに見えていたとしても，その外にあるリソースに対してはその外の権限でアクセスが判定されますから，十分にセキュアであるということができるでしょう．
※この記事の範囲内ではこの説明は腑に落ちない不十分なものかも知れません．別の記事でもう少し詳しく扱う予定のためそちらを参照いただきたいです．

