---
title: "git add/commit を使わずに変更をコミットする"
emoji: ""
type: "tech" # tech: 技術記事 / idea: アイデア
topics: []
published: true
---

# 本記事の概要

本記事では，まず始めにGit Objectについて簡単に確認したあと，実際に各オブジェクトを生成しながら，`git add/commit`を使わずに変更をコミットすることで理解を深めることを目的とします．

# 筆者の環境

```
$ rpm -q git git-core git-core-doc
git-2.52.0-1.fc43.x86_64
git-core-2.52.0-1.fc43.x86_64
git-core-doc-2.52.0-1.fc43.noarch
```

# Gitオブジェクト

本章の説明は，[Pro Git book](https://git-scm.com/book/en/v2)の10章`Git Internals`の冒頭以下2節

 - [10.1 Git Internals - Plumbing and Porcelain](https://git-scm.com/book/en/v2/Git-Internals-Plumbing-and-Porcelain)
 - [10.2 Git Internals - Git Objects](https://git-scm.com/book/en/v2/Git-Internals-Git-Objects)

を参照し，必要な事項のみを簡単に説明しなおしたものとなっています．
また，説明の中で出てくるgit固有の用語については，その初出の際に可能な限り[gitglossary](https://git-scm.com/docs/gitglossary)のリンクをつけるように努力しています．
なお，gitglossaryは`git help gitglossary`と実行すると手元の環境で参照できます．(fedoraでは`git-core-doc`パッケージで配布されている)

Gitは「コンテンツアドレッシング可能なファイルシステム(content-addressable filesystem)」として実装されています．
Pro Git bookの10.2節冒頭では次のように説明されています．

> Git is a content-addressable filesystem. Great. What does that mean? It means that at the core of Git is a simple key-value data store. What this means is that you can
> insert any kind of content into a Git repository, for which Git will hand you back a unique key you can use later to retrieve that content.

つまり，Gitの中核にあるのは単純な「キーバリューストア(key-value data store)」であり，各データには一意なキーが紐付いており，データを引き出す際はその一意なキーを指定するという仕組みでデータを扱っています．

そして，そのデータはGit内では，「[Git Object](https://git-scm.com/docs/gitglossary#Documentation/gitglossary.txt-object)」と呼ばれ，`.git/objects`([Object Database](https://git-scm.com/docs/gitglossary#Documentation/gitglossary.txt-objectdatabase))配下に格納されています．

Git Pro book 10.1節より，
> The objects directory stores all the content for your database,

また，Git Pro book 10.2節より，
> As a demonstration, let’s look at the plumbing command git hash-object, which takes some data, stores it in your .git/objects directory (the object database), and gives you back the unique key that now refers to that data object.

Git Objectは，[blob](https://git-scm.com/docs/gitglossary#Documentation/gitglossary.txt-blobobject), [tree](https://git-scm.com/docs/gitglossary#Documentation/gitglossary.txt-treeobject), [commit](https://git-scm.com/docs/gitglossary#Documentation/gitglossary.txt-commitobject), [tag](https://git-scm.com/docs/gitglossary#Documentation/gitglossary.txt-tagobject) の4種類が存在します．

`man git-hash-object`より
>  -t <type>
>      Specify the type of object to be created (default: "blob"). Possible values are commit, tree, blob, and tag.

| [Object Type](https://git-scm.com/docs/gitglossary#Documentation/gitglossary.txt-objecttype) | 概要 |
| ---- | ---- |
| [blob](https://git-scm.com/docs/gitglossary#Documentation/gitglossary.txt-blobobject) | ファイルの中身そのもの<br/>ファイル名などのメタデータは含まないことに注意 |
| [tree](https://git-scm.com/docs/gitglossary#Documentation/gitglossary.txt-treeobject) | ディレクトリ構造を示す<br/>保持するファイルやサブディレクトリを，blobやtreeへの対応として保持する |
| [commit](https://git-scm.com/docs/gitglossary#Documentation/gitglossary.txt-commitobject) | 一般的にコミットとして扱われるものの正体<br/>その時点(リビジョン)の状態として，tree・親コミット・authorなどの値やポインタを保持する |
| [tag](https://git-scm.com/docs/gitglossary#Documentation/gitglossary.txt-tagobject) | ほかのオブジェクトを指す注釈付きタグ<br/>本記事では扱わない |

commitオブジェクトは，我々が普段コミットとして扱っているものの正体です．またGitにおいて中心的で代表的なGitオブジェクトと言ってよいでしょう．
そんなcommitオブジェクトは，`blob`および`tree`オブジェクトによって構成されています．
以下はcommitオブジェクトの構成の例を示しています．
※Git Pro book 10.2節 Figure 173 と同等の構成を示している

```
commit
 └── tree（ルートディレクトリ）
      ├── blob（README）
      ├── blob（Rakefile）
      └── tree（lib(サブディレクトリ)）
           └── blob（simplegit.rb）
```

`commit`オブジェクトは必ず一つの`tree`オブジェクトへのポインタを持ちます．そのツリーオブジェクトはそのcommitオブジェクトのルートディレクトリを示すことになります．

`tree`オブジェクトは，さらに任意の数の`blob`および`tree`オブジェクトによって構成されます．
ファイルがある場合はblobオブジェクトによって示され，配下にサブディレクトリがある場合はtreeオブジェクトによってそれが示され，そのサブディレクトリ配下にファイルがあればまたblobオブジェクトが存在します．

つまり先ほどのcommitオブジェクトの例を(treeコマンド風の)ディレクトリ構造で示すと以下のようになります．
```
.
├── README
├── Rakefile
└── lib
    └── simplegit.rb
```

commitオブジェクトはまた，親コミットとなるcommitオブジェクトへのポインタをもつことにより，[DAG](https://git-scm.com/docs/gitglossary#Documentation/gitglossary.txt-DAG)(Directed Acyclic Graph, 有向非巡回グラフ)または[commit graph](https://git-scm.com/docs/gitglossary#Documentation/gitglossary.txt-commitgraphconceptrepresentationsandusage)を形成します．

なお，本記事内では `コミットチェーン` という呼び方をしています．[chain](https://git-scm.com/docs/gitglossary#Documentation/gitglossary.txt-chain)はglossaryでも定義がありますが，`コミットチェーン`という呼び方自体は一般的でない可能性があることに注意してください．


# `git add/commit` を使わずに変更をコミットする．

では本題にはいりましょう．
一般的に「変更をコミットする」と言った場合，Gitオブジェクトにまつわる以下の処理を行うことになります．

1. 新規に追加された，または変更があったファイルの中身を新たなblobオブジェクトとして生成する
2. 新たなルートディレクトリを示すtreeオブジェクトを生成する．変更がなかったファイルにはすでに生成済みのblobオブジェクトが使える．
3. commitオブジェクトを生成する．既存のコミットチェーンの最新コミットを親とすることで，そのコミットチェーンの最新コミットとしてそのcommitオブジェクトをつなげることができる．

そのほか，indexやref(reference)の更新もありますが，実際の処理の説明の中で必要があれば簡単な説明をはさむ予定です．

以下では，新規ファイルを追加した場合と，既存のファイルを修正した場合の2つのパターンでそれぞれ処理を行おうと思います．

## 開始前の状態の確認

```
$ git branch
* master
$ git log --oneline
40ca6cc (HEAD -> master) first commit
$ ls
hello.txt
```

## 新規ファイル追加の場合

### blobオブジェクトの生成

新規ファイルとしてworld.txtを作成します．
```
$ echo "world" > world.txt
```

追加したworld.txtを指定して以下のコマンドを実行し，blobオブジェクトを生成します．
```
$ git hash-object -w world.txt
cc628ccd10742baea8241c5924df992b5c019f71
```

念のため`git status`を確認しておきますが，Untracked filesにworld.txtが見えているだけです．
```
$ git status
On branch master
Untracked files:
  (use "git add <file>..." to include in what will be committed)
        world.txt

nothing added to commit but untracked files present (use "git add" to track)
$ git status --short
?? world.txt
```
※これ以降はstatusは`--short`をつけて確認します．

出力されたハッシュ値は，生成されたblobオブジェクトのハッシュ値で，そのオブジェクトは`.git/objects`配下に格納されています．
```
$ ls .git/objects/
40  aa  cc  ce  info  pack
$ ls .git/objects/cc/628ccd10742baea8241c5924df992b5c019f71
.git/objects/cc/628ccd10742baea8241c5924df992b5c019f71
$ file .git/objects/cc/628ccd10742baea8241c5924df992b5c019f71
.git/objects/cc/628ccd10742baea8241c5924df992b5c019f71: zlib compressed data
```
`.git/objects`直下にある`aa`,`cc`などはディレクトリになっていて，ハッシュ値の先頭2文字となっています．
また，ファイルは圧縮ファイルになっています．

git objectの中身を確認したい場合には，`git cat-file`コマンドが活用できます．
```
$ git cat-file -t cc628ccd10742baea8241c5924df992b5c019f71
blob
$ git cat-file -p cc628ccd10742baea8241c5924df992b5c019f71
world
```
なお，まだ現時点ではblobオブジェクトを作成しただけなので，statusは変わっておらずstagingもされていません
```
$ git status --short
?? world.txt
$ git ls-files --stage
100644 ce013625030ba8dba906f756967f9e9ca394464a 0       hello.txt
```

### indexのアップデート

次に，indexをアップデートしますが，これについては少し前説明が必要ですね．
`.git/index`というファイルがあります．
```
$ ls .git/index
.git/index
$ file .git/index
.git/index: Git index, version 2, 1 entries
$ strings .git/index
DIRC
        hello.txt
TREE
```

さて，次のコマンドでこのindexをアップデートします．
```
$ git update-index --add --cacheinfo 100644,cc628ccd10742baea8241c5924df992b5c019f71,world.txt
$ file .git/index
.git/index: Git index, version 2, 2 entries
$ strings .git/index
DIRC
        hello.txt
        world.txt
TREE
-1 0
```
`.git/index`ファイルが更新されていることが分かります．
world.txtが追加されています．ほかの差分についてはこの記事では言及は控えます．
stringsコマンドは参考のために実行したものであり，多くの情報が失われてしまっていますが，world.txtが追加されていることは分かるでしょう．

この状態でstatusなどを見ると，
```
$ git status --short
A  world.txt
$ git ls-files --stage
100644 ce013625030ba8dba906f756967f9e9ca394464a 0       hello.txt
100644 cc628ccd10742baea8241c5924df992b5c019f71 0       world.txt
```

つまりここまでの操作で，`git add world.txt`コマンドを実行したのと同等の操作を行ったことになります．
また，先ほどの`.git/index`をstringsコマンドで確認したときには分かりませんでしたが，world.txtには先ほど作成したblobオブジェクトのハッシュ値が紐付いていることがわかります．
これ以降から`git commit`相当の操作を行っていきます．

### treeオブジェクトの生成

`git write-tree`コマンドでtreeオブジェクトを作成します．
```
$ git write-tree
88e38705fdbd3608cddbe904b67c731f3234c45b
$ ls .git/objects/88/e38705fdbd3608cddbe904b67c731f3234c45b
.git/objects/88/e38705fdbd3608cddbe904b67c731f3234c45b
$ file .git/objects/88/e38705fdbd3608cddbe904b67c731f3234c45b
.git/objects/88/e38705fdbd3608cddbe904b67c731f3234c45b: zlib compressed data
```
ここで作成したオブジェクトも`.git/object`配下に格納されています．

さてここで，作成したtreeオブジェクトの中身を確認してみます．
```
$ git cat-file -t 88e38705fdbd3608cddbe904b67c731f3234c45b
tree
$ git cat-file -p 88e38705fdbd3608cddbe904b67c731f3234c45b
100644 blob ce013625030ba8dba906f756967f9e9ca394464a    hello.txt
100644 blob cc628ccd10742baea8241c5924df992b5c019f71    world.txt
```

treeオブジェクトは，ある時点でのディレクトリ構造をそのまま表します．
ファイルの内容は直接保持せずに，対応するblobオブジェクトのポインタを持つように設計されています．
サブディレクトリが存在する場合にはそれをtreeオブジェクトで表現するため，ディレクトリ構造が深い場合にはtreeオブジェクトが入れ子構造になります．
また，treeオブジェクトはindexファイルから情報を簡略化し変換して作成したもので，例えばgit statusでも，indexファイルとHEADが指す(ref(branch)が指すコミットオブジェクトに対応する)treeオブジェクトの差分を確認する仕様となっています．

さて，treeオブジェクトは生成しましたが，またコミットは完了していません．
以下のようにstatusやステージング状況を見てもまだ変わっていません．
```
$ git status --short
A  world.txt
```

### commitオブジェクトの生成

さて，次はコミットオブジェクトを生成にいきましょう．
具体的には以下のコマンドを実行します．-p オプションに指定したハッシュ値が親コミットのハッシュ値です．
なお，コミットには親子の概念が存在します．親を指定しない場合，root commitになってしまい，あらたなコミットチェインを作ることになってしまいます．
```
$ git commit-tree 88e38705fdbd3608cddbe904b67c731f3234c45b -p 40ca6cc29fa043699f3257fa447bdf0135070292 -m "add world.txt"
fe8f49491b89fb073c5b17d5aa0a21c9f9a4d490
$ ls .git/objects/fe/8f49491b89fb073c5b17d5aa0a21c9f9a4d490
.git/objects/fe/8f49491b89fb073c5b17d5aa0a21c9f9a4d490
$ file .git/objects/fe/8f49491b89fb073c5b17d5aa0a21c9f9a4d490
.git/objects/fe/8f49491b89fb073c5b17d5aa0a21c9f9a4d490: zlib compressed data
```
ここで作成したcommitオブジェクトも当然`.git/objects`配下に格納されています．
内容は以下のとおりです．
```
$ git cat-file -t fe8f49491b89fb073c5b17d5aa0a21c9f9a4d490
commit
$ git cat-file -p fe8f49491b89fb073c5b17d5aa0a21c9f9a4d490
tree 88e38705fdbd3608cddbe904b67c731f3234c45b
parent 40ca6cc29fa043699f3257fa447bdf0135070292
author xxx yyy <zzz@example.com> 1786267141 +0900
committer xxx yyy <zzz@example.com> 1786267141 +0900

add world.txt
```

注目すべきは一行目に記されているtreeオブジェクトのハッシュ値でしょうか．
`tree 88e38705fdbd3608cddbe904b67c731f3234c45b`
commitオブジェクトそれ自身には，その時点でのリポジトリ内のファイルの中身などの情報は一切記録されていません．
そのため，それを示すtreeオブジェクトのポインタ(ハッシュ値)を持つように設計されています．

ここまででcommitオブジェクトの生成までは完了です．

### refの更新

さて，commitオブジェクトを作成しましたが，statusはどうでしょうか．
```
$ git status --short
A  world.txt
$ git log --oneline
40ca6cc (HEAD -> master) first commit
$ git log --oneline --all
40ca6cc (HEAD -> master) first commit
```
どうやらまだ`git commit`相当の処理は完了できていないようです．
ref(branchなど)が古いコミットを指したままだとこのようにステージング状態のように見えてしまうので，最後にrefを更新する作業が必要です．
(厳密には，HEADを更新する必要がある，と言った方が正しいでしょうか．git statusは，ワーキングディレクトリと`.git/index`および`.git/index`とHEADが指すtreeの差分を示すものであるため．)
```
$ git update-ref refs/heads/master fe8f49491b89fb073c5b17d5aa0a21c9f9a4d490
```
これでstatusなどを確認してみると..
```
$ git status --short
$ git log --oneline
fe8f494 (HEAD -> master) add world.txt
40ca6cc first commit
```
masterブランチが更新されています．これで私たちが普段行っている`git add/commit`までの処理が完了したことになるでしょう．

## 既存ファイルの修正の場合

### blobオブジェクトの生成

まずは既存のhello.txtを書き換えるところから始めます．
```
$ echo "hello world" > hello.txt
$ git status --short
 M hello.txt
$ git ls-files --stage
100644 ce013625030ba8dba906f756967f9e9ca394464a 0       hello.txt
100644 cc628ccd10742baea8241c5924df992b5c019f71 0       world.txt
```

まずは変更したhello.txtファイルをベースに新しいblobオブジェクトを生成します．
```
$ git hash-object -w hello.txt
3b18e512dba79e4c8300dd08aeb37f8e728b8dad
$ file .git/objects/3b/18e512dba79e4c8300dd08aeb37f8e728b8dad
.git/objects/3b/18e512dba79e4c8300dd08aeb37f8e728b8dad: zlib compressed data
$ git cat-file -t 3b18e512dba79e4c8300dd08aeb37f8e728b8dad
blob
$ git cat-file -p 3b18e512dba79e4c8300dd08aeb37f8e728b8dad
hello world
```

### indexの更新

続いて，先ほど作成したblobオブジェクトを指定してindexを更新します．
以前の新規ファイル作成のときと比べて--addオプションがありません．既存のファイルを修正，つまり対応するblobファイルのポインタ(ハッシュ)を変更しているからです．
```
$ git update-index --cacheinfo 100644,3b18e512dba79e4c8300dd08aeb37f8e728b8dad,hello.txt
```

さて，この状況で，`git ls-files --stage`でindex(ステージングされた)情報を見てみてください．
```
$ git ls-files --stage
100644 3b18e512dba79e4c8300dd08aeb37f8e728b8dad 0       hello.txt
100644 cc628ccd10742baea8241c5924df992b5c019f71 0       world.txt
```
以前と比較してhello.txtのblobのポインタ(ハッシュ値)が，新しく作成したblobオブジェクトのポインタに変わっているのがわかります．

### treeオブジェクトの生成

ここからは先ほどと同様です．まずはtreeオブジェクトを生成します．
```
$ git write-tree
520c0bff646a543c8df291fbeb1711ce2eecbfb3
$ git cat-file -t 520c0bff646a543c8df291fbeb1711ce2eecbfb3
tree
$ git cat-file -p 520c0bff646a543c8df291fbeb1711ce2eecbfb3
100644 blob 3b18e512dba79e4c8300dd08aeb37f8e728b8dad    hello.txt
100644 blob cc628ccd10742baea8241c5924df992b5c019f71    world.txt
```

### commitオブジェクトの生成

続いてcommitオブジェクトを生成します．親コミットを指定するのを忘れないように．
```
$ git commit-tree 520c0bff646a543c8df291fbeb1711ce2eecbfb3 -p fe8f49491b89fb073c5b17d5aa0a21c9f9a4d490 -m "modify hello.txt"
685147ae7b215963a659a6d7d20b62a8388a44af
$ git cat-file -t 685147ae7b215963a659a6d7d20b62a8388a44af
commit
$ git cat-file -p 685147ae7b215963a659a6d7d20b62a8388a44af
tree 520c0bff646a543c8df291fbeb1711ce2eecbfb3
parent fe8f49491b89fb073c5b17d5aa0a21c9f9a4d490
author xxx yyy <zzz@example.com> 1786273969 +0900
committer xxx yyy <zzz@example.com> 1786273969 +0900

modify hello.txt
```

### refの更新

最後にupdate-refを実行します．
```
$ git update-ref refs/heads/master 685147ae7b215963a659a6d7d20b62a8388a44af
$ git log --oneline
685147a (HEAD -> master) modify hello.txt
fe8f494 add world.txt
40ca6cc first commit
```

# 次回記事

続編として以下の記事を作成しました．
`git merge`相当の処理を行うことを主題にしています．
@[card](https://zenn.dev/khwarizmi6514/articles/20260810-git-manual-merge)

