---
title: "git merge を使わずにマージコミットを生成する"
emoji: ""
type: "tech" # tech: 技術記事 / idea: アイデア
topics: []
published: true
---

# 本記事の概要

[前回の記事](https://zenn.dev/khwarizmi6514/articles/20260808-git)では，`git add/commit`を使わずにコミットを行いました．

@[card](https://zenn.dev/khwarizmi6514/articles/20260808-git)

本記事では，マージコミットの生成を行います．
マージコミットもGit内では通常のコミットと同じ`commit`オブジェクトですが，親コミットが2つになるという特徴があります．手順自体には大きな変化はありませんが，親が複数になる例(特徴的なコミットチェーンのトポロジーの一例)として扱っておくのは価値があると考えて取り組んで見ようと思います．
また，本記事の中でもコミットを積む手順が発生しますが，微妙に手順を変えています．具体的には`tree`オブジェクトの生成方法が変わっています．

なお，本記事では3-way MergeやMerge Algorithm/Strategyについては扱わず，また踏み込まないようにしています．

さらに番外編として，ブランチの切り替え(`git switch`)を扱っています．
マージコミット生成や，今まで扱ってきたGitオブジェクトには関係しませんが，index/HEADとその関係性の理解の助けになると思って扱うことにしました．

# `git merge`を使わずにマージコミットを生成する

この記事では，[前回の記事](https://zenn.dev/khwarizmi6514/articles/20260808-git)で利用していたディレクトリをそのまま活用しています．
現在ブランチはmasterのみ存在しますが，もう一つブランチを作成し，それぞれに独自の変更を入れたあとにマージをする方針で進めます．

## ブランチの作成

手順はとしては簡単で，update-refを以下のように実行するだけです．
今回の作業でのポイントとして，feature-xは，最新コミットではなく，一つ前のコミット(`fe8f494 add world.txt`)を指すようにしようと思います．

```
$ git update-ref refs/heads/feature-x fe8f49491b89fb073c5b17d5aa0a21c9f9a4d490
$ git branch
  feature-x
* master
$ git status --short
$ git log --oneline --all
685147a (HEAD -> master) modify hello.txt
fe8f494 (feature-x) add world.txt
40ca6cc first commit
```

## 番外編: ブランチの移動(`git switch`)

先ほど作成したfeature-xブランチへの移動を例に，`git switch feature-x`コマンド相当の操作を行ってみようと思います．
作業上ブランチを移動する必要はなく，本記事の作業上も本章はスキップした(ブランチは移動しない)状態で進みます．

ブランチの移動は，以下の3の作業が必要です．

1. index(`.git/index`)を目的のtreeの内容で置き換える → プランビングコマンドgit read-tree
2. ワーキングディレクトリのファイルを、indexの内容に合わせて書き出す → プランビングコマンドgit checkout-index
3. HEADが指すrefを切り替える → `git symbolic-ref HEAD refs/heads/<branch>`（または.git/HEADを直接書き換えても同じ）

まずはindexの内容を書き換えます．
`git read-tree`コマンドによって，特定のコミットハッシュを指定すると，そのcommitオブジェクトに紐付くtreeオブジェクトの内容をindexに書き出してくれます．
treeオブジェクトのハッシュを直接指定することもできます．
コマンド実行前後で，`git ls-files --stage`でindexの内容を比較しながら行ってみましょう．
```
$ git ls-files --stage
100644 3b18e512dba79e4c8300dd08aeb37f8e728b8dad 0       hello.txt
100644 cc628ccd10742baea8241c5924df992b5c019f71 0       world.txt
$ git read-tree fe8f49491b89fb073c5b17d5aa0a21c9f9a4d490
$ git ls-files --stage
100644 ce013625030ba8dba906f756967f9e9ca394464a 0       hello.txt
100644 cc628ccd10742baea8241c5924df992b5c019f71 0       world.txt
```
当然ですが，この時点でgit statusを見ると差分がでています．
```
$ git status --short
MM hello.txt
```
ブランチ移動中なので少しおかしな状態に見えますが，しょうがないです．
さて，ではワーキングディレクトリの状態もこのtreeのものを反映していきます．
```
$ cat hello.txt
hello world
$ git checkout-index -a -f
$ cat hello.txt
hello
```
とりあえず，hello.txtが修正前の状態にもどったことだけは確認できるかなと思います．
※この状態でstatusを見ると，hello.txtがステージングされていることになるのはおもしろいです．

さて，最後にHEADを移動すればブランチの移動が完了して正常な状態にもどります．
`.git/HEAD`を手書きで変更する方法もありますが，それっぽいコマンドを使ってみることにします．
```
$ cat .git/HEAD
ref: refs/heads/master
$ git symbolic-ref HEAD refs/heads/feature-x
$ cat .git/HEAD
ref: refs/heads/feature-x
$ git branch
* feature-x
  master
$ git status --short
$ git log --oneline --all
685147a (master) modify hello.txt
fe8f494 (HEAD -> feature-x) add world.txt
40ca6cc first commit
```

さて，ここまでで`git switch feature-x`相当の操作が完了です．

しかし，今回の作業は，ブランチを移動せずmasterブランチ上から作業してみようと思っているため，次章ではまたmasterブランチにいる想定で作業を再開します．

## feature-xに独自の変更を積む

さて，masterにマージするためにfeature-xブランチの独自変更を積んでおこうと思います．
また，趣向を変えて，masterブランチにいたままfeature-x上に変更を積んでみようと思います．
作業手順としては，indexの操作やtreeオブジェクトの作成方法が少し変わります．
masterブランチ上にいますので，indexの更新は基本的にできませんし，indexをベースにtreeオブジェクトを作成することはできませんので，`git mktree`というコマンドを使ってtreeオブジェクトを作ることになります．

まずは独自変更としてfeature-x.txtを作り，blobオブジェクトを生成します．
```
$ git branch
  feature-x
* master
$ echo "feature x" > feature-x.txt
$ git hash-object -w feature-x.txt
7eba4c935e3b71b85da6d23995b70bdecebd7aa9
```

実はもうこの時点でfeature-x.txtはいらないので，削除しておきます．
```
$ rm feature-x.txt
$ git cat-file -t 7eba4c935e3b71b85da6d23995b70bdecebd7aa9
blob
$ git cat-file -p 7eba4c935e3b71b85da6d23995b70bdecebd7aa9
feature x
```

さて，次にtreeオブジェクトを作る必要があります．
冒頭で述べたように，今回はindexをアップデートできないので，ベースになる情報を自分で作る必要があります．
わたしは手元にtreeというファイルを作ってそこに情報を作ってみました．

まずベースとなる情報は，以下のようにfeature-xブランチが指すコミットのtreeオブジェクトの内容をそのままに持ってきます．git cat-fileで確認できます．
下に一行追加して，ハッシュ値とファイル名をfeature-x.txtのものに変えるだけです．
一点だけ注意ですが，ハッシュ値とファイル名の間はタブ(='\t')です．
```
$ git cat-file -p 88e38705fdbd3608cddbe904b67c731f3234c45b
100644 blob ce013625030ba8dba906f756967f9e9ca394464a    hello.txt
100644 blob cc628ccd10742baea8241c5924df992b5c019f71    world.txt
$ cat tree
100644 blob ce013625030ba8dba906f756967f9e9ca394464a    hello.txt
100644 blob cc628ccd10742baea8241c5924df992b5c019f71    world.txt
100644 blob 7eba4c935e3b71b85da6d23995b70bdecebd7aa9    feature-x.txt
```

これで`git mktree`コマンドを実行します．
なお，コマンドが正常終了したら，treeファイルももちろん削除してよいです．
```
$ git mktree < tree
33e742646decf5c989eabd5ef306bf1cbe6f6eef
$ git cat-file -t 33e742646decf5c989eabd5ef306bf1cbe6f6eef
tree
$ git cat-file -p 33e742646decf5c989eabd5ef306bf1cbe6f6eef
100644 blob 7eba4c935e3b71b85da6d23995b70bdecebd7aa9    feature-x.txt
100644 blob ce013625030ba8dba906f756967f9e9ca394464a    hello.txt
100644 blob cc628ccd10742baea8241c5924df992b5c019f71    world.txt
$ rm tree
```

さあ，そうしたらこれをベースにcommitオブジェクトを生成します．
親コミットを指定するのを忘れずに．当然親コミットは，現在feature-xが指しているコミットにします．
```
$ git log --oneline --all
685147a (HEAD -> master) modify hello.txt
fe8f494 (feature-x) add world.txt   <--- コレ!!
40ca6cc first commit

$ git commit-tree 33e742646decf5c989eabd5ef306bf1cbe6f6eef -p fe8f49491b89fb073c5b17d5aa0a21c9f9a4d490 -m "add feature-x.txt"
26bc1326083057c158d96f3dea003331cd976af5
$ git cat-file -t 26bc1326083057c158d96f3dea003331cd976af5
commit
$ git cat-file -p 26bc1326083057c158d96f3dea003331cd976af5
tree 33e742646decf5c989eabd5ef306bf1cbe6f6eef
parent fe8f49491b89fb073c5b17d5aa0a21c9f9a4d490
author xxx yyy <zzz@example.com> 1786281087 +0900
committer xxx yyy <zzz@example.com> 1786281087 +0900

add feature-x.txt
```

最後にupdate-refをしましょう．もちろんfeature-xを更新します．
```
$ git log --oneline --all --graph
* 685147a (HEAD -> master) modify hello.txt
* fe8f494 (feature-x) add world.txt
* 40ca6cc first commit
$ git update-ref refs/heads/feature-x 26bc1326083057c158d96f3dea003331cd976af5
$ git log --oneline --all --graph
* 26bc132 (feature-x) add feature-x.txt
| * 685147a (HEAD -> master) modify hello.txt
|/
* fe8f494 add world.txt
* 40ca6cc first commit
```

以上で，masterブランチにいながら，ブランチを移動せずにfeature-xブランチにコミットを積み上げることができました．
現実的にこのような手順で作業を行うことはありえませんが，gitオブジェクトについての理解があるとこのような芸当もできてしまうようですね．

## マージコミットとしてcommitオブジェクトを生成する

feature-xの変更をmasterブランチにマージします．

mergeする際の一般的な手順として，まずは`merge-base(共通祖先)`を確認する必要があります．
今回の場合はmerge-baseは分かりきっていますし，ツリーが単純なのでgit logを見ればすぐに分かりますが，`git merge-base`というユーティリティを使って確認することができます．
```
$ git merge-base master feature-x
fe8f49491b89fb073c5b17d5aa0a21c9f9a4d490
$ git log --all --oneline --graph
* 26bc132 (feature-x) add feature-x.txt
| * 685147a (HEAD -> master) modify hello.txt
|/
* fe8f494 add world.txt
* 40ca6cc first commit
```
`fe8f494`のコミットを根元にして分岐していますので，これが`merge-base(共通祖先)`になります．

ここからは，真面目に扱おうとするとMerge Algorithm/Strategyなどを扱う必要がでてきますが，この記事ではそこまで扱いません．

今回は，それぞれのブランチで別のファイルを修正していますので，そこまで深く考えずにシンプルにマージ可能です．
各ブランチにおいて更新した最新のファイルのblobオブジェクトがどれかを整理し，その情報からtreeオブジェクトを生成し，そのtreeをルートディレクトリとしてcommitオブジェクトを，親を2つ指定して作成すればよいです．

実際にtreeオブジェクト生成のために作ってみた情報がこちらです．
```
$ cat tree
100644 blob 7eba4c935e3b71b85da6d23995b70bdecebd7aa9    feature-x.txt
100644 blob 3b18e512dba79e4c8300dd08aeb37f8e728b8dad    hello.txt
100644 blob cc628ccd10742baea8241c5924df992b5c019f71    world.txt
```
world.txtは内容が同じなので，どちらから持ってきてもハッシュ値は変わりません．
hello.txtはmasterから，feature-x.txtはfeature-xからそれぞれ持ってきただけです．

この内容をベースにtreeオブジェクトを作成します．
```
$ git mktree < tree
142c9afafdc1cdaf975f44815d013e11842dd375
$ rm tree
$ git cat-file -t 142c9afafdc1cdaf975f44815d013e11842dd375
tree
$ git cat-file -p 142c9afafdc1cdaf975f44815d013e11842dd375
100644 blob 7eba4c935e3b71b85da6d23995b70bdecebd7aa9    feature-x.txt
100644 blob 3b18e512dba79e4c8300dd08aeb37f8e728b8dad    hello.txt
100644 blob cc628ccd10742baea8241c5924df992b5c019f71    world.txt
```

次にcommitオブジェクトを作ります．
冒頭で述べた注意を再度書きますが，masterの最新・feature-xの最新の両方2つを親に持つようにcommitオブジェクトを作ります．
`git commit-tree`は，`-p`を複数受け入れる仕様になっているようであるため，以下のように実行します．
```
$ git commit-tree 142c9afafdc1cdaf975f44815d013e11842dd375 \
      -p 685147ae7b215963a659a6d7d20b62a8388a44af \
      -p 26bc1326083057c158d96f3dea003331cd976af5 \
      -m "merge feature-x into master"
6cd2d6c9e57aad1b7338c769714cc11d70b01376
$ git cat-file -t 6cd2d6c9e57aad1b7338c769714cc11d70b01376
commit
$ git cat-file -p 6cd2d6c9e57aad1b7338c769714cc11d70b01376
tree 142c9afafdc1cdaf975f44815d013e11842dd375
parent 685147ae7b215963a659a6d7d20b62a8388a44af
parent 26bc1326083057c158d96f3dea003331cd976af5
author xxx yyy <zzz@example.com> 1786283851 +0900
committer xxx yyy <zzz@example.com> 1786283851 +0900

merge feature-x into master
```
commitオブジェクトを見たときに，parent行が2行あることがわかります．期待どおりです．


最後にupdate-refでmasterブランチを更新します．
これによってgit logでもマージされたことが分かるようにツリーが作れているはずです．
```
$ git update-ref refs/heads/master 6cd2d6c9e57aad1b7338c769714cc11d70b01376
$ git log --all --oneline --graph
*   6cd2d6c (HEAD -> master) merge feature-x into master
|\
| * 26bc132 (feature-x) add feature-x.txt
* | 685147a modify hello.txt
|/
* fe8f494 add world.txt
* 40ca6cc first commit
```
すばらしい!! 期待した通りに綺麗にマージできています．

最後に，indexをいじっていなかったのでgit statusすると見覚えのない変更がステージングされていることになっています．
```
$ git status
On branch master
Changes to be committed:
  (use "git restore --staged <file>..." to unstage)
        deleted:    feature-x.txt

$ git ls-files --stage
100644 3b18e512dba79e4c8300dd08aeb37f8e728b8dad 0       hello.txt
100644 cc628ccd10742baea8241c5924df992b5c019f71 0       world.txt
$ ls
hello.txt  world.txt
```
もともとmasterブランチにfeature-x.txtはなかったですから，indexはfeature-x.txtがない状態のままになっています．
そしていまだにワーキングディレクトリにもfeature-x.txtはないままですね．
マージによってfeature-x.txtが増えたので，現状の状態としては，feature-x.txtの削除の変更がステージングされている状態に見えてしまっているということですね．
ということで，ちょっとindexの修正とワーキングディレクトリへの反映が必要です．
```
$ git read-tree HEAD
$ git checkout-index -a -f
$ git status
On branch master
nothing to commit, working tree clean
$ git ls-files --stage
100644 7eba4c935e3b71b85da6d23995b70bdecebd7aa9 0       feature-x.txt
100644 3b18e512dba79e4c8300dd08aeb37f8e728b8dad 0       hello.txt
100644 cc628ccd10742baea8241c5924df992b5c019f71 0       world.txt
$ ls
feature-x.txt  hello.txt  world.txt
```

これでindexやカレントディレクトリのつじつま合わせも完了しましたので，`git merge`相当の処理は終了できたことになります．


# 次回記事

続編として以下の記事を作成しました．
`Reference/Refs`を扱っています．
@[card](https://zenn.dev/khwarizmi6514/articles/20260810-git-myown-refs)

