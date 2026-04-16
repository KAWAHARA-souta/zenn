---
title: "パイプとプロセス置換"
emoji: ""
type: "tech" # tech: 技術記事 / idea: アイデア
topics: [shell, IPC, pipe]
published: true
---

# 概要

シェルのプロセス置換(Process Substitution)およびパイプについて，コマンドの観察から分かる範囲で考察したいと思います．
コードは参照しないため考察の域を出ません．あしからず．

前半のプロセス置換については，パイプを使ってどのようにプロセス置換したプロセスがつながっているかを観察します．
後半はシンプルなパイプにもどってシステムコールの流れなどを追います．

なお，筆者の環境は以下のとおりです．
```
$ rpm -q bash
bash-5.3.0-2.fc43.x86_64
$ bash --version
GNU bash, version 5.3.0(1)-release (x86_64-redhat-linux-gnu)
Copyright (C) 2025 Free Software Foundation, Inc.
License GPLv3+: GNU GPL version 3 or later <http://gnu.org/licenses/gpl.html>

This is free software; you are free to change and redistribute it.
There is NO WARRANTY, to the extent permitted by law.
```

# プロセス置換について

## プロセス置換とは

プロセス置換とは，シェルにおいてコマンドの出力結果をファイルのように扱える機能です．
例えば，diffコマンドでは以下のようにfile1とfile2の差分を確認することができますが，
```
$ diff file1 file2
```
これを以下のようにすると，command1, command2の標準出力の差分を確認することができます．
```
$ diff <(command1) <(command2)
```

## プロセス置換で起動したプロセスのツリー

ちょっと強引ですが，以下のようにすると綺麗にツリーが見れました．
```
$ echo $$
741888
khwarizmi@khwarizmi-fedolaptop:~/git/github.com/KAWAHARAsouta$ (sleep 0.1; ps -o pid,ppid,comm --forest) & cat <(sleep 1)
[1] 2478481
    PID    PPID COMMAND
 741888    6258 bash
2478481  741888  \_ ps
2478483  741888  \_ sleep
2478484  741888  \_ cat
[1]+  Done                       ( sleep 0.1; ps -o pid,ppid,comm --forest )
```
741888がシェルのPIDです．psはプロセスツリー観察用のプロセスのため無視してよいです．
catとsleepがきれいに並んでいるのが見えます．
一つおもしろい点としては，プロセス置換されるsleepの方がPIDが若いため，おそらく先にforkされているという点でしょうか．もちろんシェルによって異なると思いますが．

## プロセスの出力のつながりを見る．

これまたさらに強引ですが，以下のようにして，それぞれのプロセスからfdがどのように生えているか見てみようと思います．
```
$ SHELL_PID=$$; (sleep 0.3; ls -la /proc/$(pgrep -P $SHELL_PID cat)/fd; ls -la /proc/$(pgrep -P $SHELL_PID sleep)/fd) & cat <(sleep 1); wait
[1] 2489204
total 0
dr-x------. 2 khwarizmi khwarizmi  5 Apr 16 14:53 .
dr-xr-xr-x. 9 khwarizmi khwarizmi  0 Apr 16 14:53 ..
lrwx------. 1 khwarizmi khwarizmi 64 Apr 16 14:53 0 -> /dev/pts/12
lrwx------. 1 khwarizmi khwarizmi 64 Apr 16 14:53 1 -> /dev/pts/12
lrwx------. 1 khwarizmi khwarizmi 64 Apr 16 14:53 2 -> /dev/pts/12
lr-x------. 1 khwarizmi khwarizmi 64 Apr 16 14:53 3 -> 'pipe:[4525124]'
lr-x------. 1 khwarizmi khwarizmi 64 Apr 16 14:53 63 -> 'pipe:[4525124]'
total 0
dr-x------. 2 khwarizmi khwarizmi  3 Apr 16 14:53 .
dr-xr-xr-x. 9 khwarizmi khwarizmi  0 Apr 16 14:53 ..
lrwx------. 1 khwarizmi khwarizmi 64 Apr 16 14:53 0 -> /dev/pts/12
l-wx------. 1 khwarizmi khwarizmi 64 Apr 16 14:53 1 -> 'pipe:[4525124]'
lrwx------. 1 khwarizmi khwarizmi 64 Apr 16 14:53 2 -> /dev/pts/12
[1]+  Done                       ( sleep 0.3; ls --color=auto -la /proc/$(pgrep -P $SHELL_PID cat)/fd; ls --color=auto -la /proc/$(pgrep -P $SHELL_PID sleep)/fd )

```

1つ目のlsコマンドの結果は，catコマンドのプロセスのfdを示しています．fd 63が`pipe:[4525124]`につながっていることを覚えておきます．なお，fd 3も同じパイプに伸びているのは，たぶん引数に指定されたファイルをopenするようにcatができているからだと思います．
2つ目のlsコマンドの結果は，シェルでプロセス置換されたsleepコマンドのプロセスのfdを示しています．fd 1が`pipe:[4525124]`につながっています．
先ほどcatのfd 63と同じパイプにつながっています．また，fd 1は標準出力が流れますから，sleepの標準出力が`pipe:[4525124]`を通じてcatに流れることが確認できたと思います．

# パイプ(無名パイプ)

先ほどみたように，プロセス置換されたプロセスはパイプで出力が別のプロセスにつながれていました．
この流れのままパイプの扱われ方，システムコールの流れや操作方法などを，少しシェルの気持ちになりながら想像で追っていきます．

## システムコールを追う

```
$ strace -f -e trace=pipe2,dup2,execve,clone bash -c 'cat /etc/hostname | grep -v xxx'
execve("/usr/bin/bash", ["bash", "-c", "cat /etc/hostname | grep -v xxx"], 0x7ffcac72d128 /* 70 vars */) = 0
pipe2([3, 4], 0)                        = 0
clone(child_stack=NULL, flags=CLONE_CHILD_CLEARTID|CLONE_CHILD_SETTID|SIGCHLDstrace: Process 2503114 attached, child_tidptr=0x7fd6293f2a10) = 2503114
[pid 2503113] clone(child_stack=NULL, flags=CLONE_CHILD_CLEARTID|CLONE_CHILD_SETTID|SIGCHLD <unfinished ...>
[pid 2503114] dup2(4, 1)                = 1
strace: Process 2503115 attached
[pid 2503113] <... clone resumed>, child_tidptr=0x7fd6293f2a10) = 2503115
[pid 2503115] dup2(3, 0)                = 0
[pid 2503114] execve("/usr/bin/cat", ["cat", "/etc/hostname"], 0x557bed8e39d0 /* 70 vars */) = 0
[pid 2503115] execve("/usr/bin/grep", ["grep", "-v", "xxx"], 0x557bed8e39d0 /* 70 vars */) = 0
[pid 2503114] +++ exited with 0 +++
khwarizmi-fedolaptop
[pid 2503115] +++ exited with 0 +++
--- SIGCHLD {si_signo=SIGCHLD, si_code=CLD_EXITED, si_pid=2503114, si_uid=1000, si_status=0, si_utime=0, si_stime=0} ---
+++ exited with 0 +++
```

実行されるコマンドとしては，`bash -c 'cat /etc/hostname | grep -v xxx'`となります．
まず親となるbashプロセスが`execve(2)`で起動されます．ちなみにこのbashプロセスのPIDは2503113です．(これは下のほうの出力を眺めるとわかります．)
```
execve("/usr/bin/bash", ["bash", "-c", "cat /etc/hostname | grep -v xxx"], 0x7ffcac72d128 /* 70 vars */) = 0
```

パイプを使う場合には，forkの前にまず`pipe2(2)`によってパイプが作られます，pipe2(2)の第一引数が`[3, 4]`となっているということは，fd 3と4が新たに生成され，その両方がパイプとつながっています．
```
pipe2([3, 4], 0)                        = 0
```
なお，4が書き込み用で，3が読み取り用です．すなわち，catはその出力をfd 4に向けて流すことでパイプに流れて，それがfd 3にそのままでてくる．grep はそれを拾うという流れです．

次に`clone(2)`によってプロセスがforkされます．使われているシステムコールはcloneですが，ここではほぼforkと思って構わないです．
また，catとgrepの2つのプロセスが必要なため2回実行されていますね．PID2503114とPID2503115ができています．
```
clone(child_stack=NULL, flags=CLONE_CHILD_CLEARTID|CLONE_CHILD_SETTID|SIGCHLDstrace: Process 2503114 attached, child_tidptr=0x7fd6293f2a10) = 2503114
[pid 2503113] clone(child_stack=NULL, flags=CLONE_CHILD_CLEARTID|CLONE_CHILD_SETTID|SIGCHLD <unfinished ...>
```

次に，`dup2(2)`というシステムコールが呼ばれています．
これは，第一引数の番号のfdを，第二引数の番号のfdとしても扱うようというようなシステムコールです．わかりづらいと思いますが，実例を見るとわかります．
注目すべきは，PID2502114(cat)では`dup2(4, 1)`が実行されており，PID2503115(grep)では`dup2(3, 0)`が実行されているところです．
```
[pid 2503114] dup2(4, 1)                = 1
[pid 2503115] dup2(3, 0)                = 0
```

fd 4は，パイプの書き込み用のfdでした．それをfd 1としても扱うということです．
fd 1は標準出力として使われるfdです．つまり，catが本来標準出力(=fd 1)に流すはずだったものは，パイプの書き込み(=fd 4)に流れるという仕組みになります．
これと同様に，grep側も本来の入力である標準入力(=fd 0)が，パイプの読み込み(=fd 3)からとられることになります．

このように，forkした後に各プロセスにてパイプへのつなぎ換えを適切に行っているのですね．
なお，pipe2(2)でできるパイプは無名パイプとも呼ばれるとおりで，名前やファイルシステム上での実態をもたないため，先に作成してからforkすることにより子プロセスに同じものがコピーされるので，無理なくパイプを扱えるという仕組みになっています．

そして最後にそれぞれのプロセスにexecveすればOKというところです．
```
[pid 2503114] execve("/usr/bin/cat", ["cat", "/etc/hostname"], 0x557bed8e39d0 /* 70 vars */) = 0
[pid 2503115] execve("/usr/bin/grep", ["grep", "-v", "xxx"], 0x557bed8e39d0 /* 70 vars */) = 0
```

## システムコールから追えなかった細かい部分

システムコールから追えなかった細かい部分について少し書いておきます．

### EOFの扱い

ファイルを扱う場合，全体を読み終えるとEOFが帰ってきて終了を知らせる仕組みとなっています．パイプはファイルではないため，EOFの扱いが難しいです．
そのため，パイプの書き込み用fd(先ほどの例だと4)がすべてcloseされるとEOFを送る仕組みになっています．

man 7 pipeより
```
If all file descriptors referring to the write end of a pipe have been closed, then an attempt to read(2) from the pipe will see end-of-file (read(2) will return  0).
```

なお，すべてプロセスで書き込み用fdをcloseしている必要があります．先ほどの例だと，親プロセスとなるbashと，cat, grepの3つが同じパイプへのfdを持っているはずなので，それらすべてでfd 4がcloseされている必要があります．


