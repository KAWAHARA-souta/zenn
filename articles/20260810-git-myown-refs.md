---
title: "refs/heads の外側に独自コミットチェーンを作る"
emoji: ""
type: "tech" # tech: 技術記事 / idea: アイデア
topics: []
published: true
---

# 本記事の概要

[前回の記事](https://zenn.dev/khwarizmi6514/articles/20260810-git-manual-merge)では，`git merge`を使わずにマージを行いました．

@[card](https://zenn.dev/khwarizmi6514/articles/20260810-git-manual-merge)

今回は，`references`(`refs`)を扱って，`refs/heads`およびGitが管理するrefs空間の外に独自のコミットチェーンを作るということをしてみようと思います．

この記事でも，[前回の記事](https://zenn.dev/khwarizmi6514/articles/20260810-git-manual-merge)で利用していたディレクトリをそのまま活用しています．

# Git References

本章の説明は，[Pro Git book](https://git-scm.com/book/en/v2)の10章`Git Internals`の以下の節

 - [10.3 Git Internals - Git References](https://git-scm.com/book/en/v2/Git-Internals-Git-References)
 <!-- - [10.7 Git Internals - Git Objects](https://git-scm.com/book/en/v2/Git-Internals-Git-Objects) -->

を参照し，必要な事項のみを簡単に説明しなおしたものとなっています．
また，説明の中で出てくるgit固有の用語については，その初出の際に可能な限り[gitglossary](https://git-scm.com/docs/gitglossary)のリンクをつけるように努力しています．

10.3節の冒頭では，以下のような説明があります．

> If you were interested in seeing the history of your repository reachable from commit, say, 1a410e, you could run something like git log 1a410e to display that history, but you would still have to remember that 1a410e is the commit you want to use as the starting point for that history. Instead, it would be easier if you had a file in which you could store that SHA-1 value under a simple name so you could use that simple name rather than the raw SHA-1 value.
> In Git, these simple names are called “references” or “refs”; you can find the files that contain those SHA-1 values in the .git/refs directory.

そのソースコードの履歴を確認したいとき，commitオブジェクトのハッシュ値を指定しますが，ハッシュ値は人間にとっては非常に扱い辛いでしょう．
そのハッシュ値を指す人間にやさしい名前それ自体がGitにおける `[references](https://git-scm.com/docs/gitglossary#Documentation/gitglossary.txt-ref)` および `refs` であると説明されており，これらは`.git/refs`配下に格納されるようです．

実際に，現在のディレクトリ配下の`.git/refs`を確認してみると，以下のようにここまで扱ってきたブランチの名前を確認することができます．
```
$ find .git/refs/
.git/refs/
.git/refs/tags
.git/refs/heads
.git/refs/heads/master
.git/refs/heads/feature-x
```

このファイルの中身を確認してみると，単純にcommitオブジェクトのハッシュ値が格納されているだけであることが分かります．
```
$ cat .git/refs/heads/master
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

すでに見たように，`.git/refs`配下にはいくつかのサブディレクトリがGitにおいて予約して利用されているものが存在します．
そのうち代表的なもの3つについて，`man gitrepository-layout`から引用しながら説明を進めたいと思います．


**refs/heads**
> records tip-of-the-tree commit objects of branch name

つまり，`refs/heads/<name>`は，`<name>`という名前のブランチの，最新(tip)のcommitオブジェクトを記録する場所であると説明されています．
これまでの実験で`git update-ref refs/heads/<name> <commit>`として何度も直接操作してきた場所そのものであり，また我々が一般的に「ブランチ」と読んでいるものの正体がこの配下にあるということです．

ちなみにブランチ([branch](https://git-scm.com/docs/gitglossary#Documentation/gitglossary.txt-branch))はgitglossarryで以下のように説明されています．

> A "branch" is a line of development. The most recent commit on a branch is referred to as the tip of that branch. The tip of the branch is referenced by a branch head,

先ほどの最新(tip)のcommitオブジェクトとありましたが，これは開発の最新(tip)という意味です．
念のため記載しておきますが，最新というのはかならずしもコミットチェーン([DAG](https://git-scm.com/docs/gitglossary#Documentation/gitglossary.txt-DAG) または [commit graph](https://git-scm.com/docs/gitglossary#Documentation/gitglossary.txt-commitgraphconceptrepresentationsandusage))の最新であるとは限りません．

**refs/tags**
> records any object name (not necessarily a commit object,
> or a tag object that points at a commit object).

`refs/heads`と違い，指す先はcommitオブジェクトに限らない点が特徴です．commitオブジェクトを指す場合もあれば，tagオブジェクトを指す場合もあります．
前者はlightweight(軽量)タグ，後者はannotated(タグ)と呼ばれることもあるようです．
`tag`オブジェクトは今まで扱ってきませんでしたが，ユーザー視点で簡単に理解すると，「`git tag`コマンドでタグを作成すると，特定のコミットを指すtagオブジェクト(annotatedタグ)が生成され，`.git/refs/tags`配下にはその生成されたtagオブジェクトを指すreferenceが生成される」というイメージです．

**refs/remotes**
> records tip-of-the-tree commit objects of branches copied
> from a remote repository.

リモートリポジトリから取得した(fetch・pushした)ブランチの，最新commitオブジェクトを記録する場所です．
refs/headsとの違いとして，Pro Git book 10.3節では次のように説明されています．

> Remote references differ from branches (refs/heads references) mainly in that they're considered read-only.

つまり，ユーザーが直接コミットを積んで進めていくrefs/headsとは異なり，refs/remotesはあくまでリモートの状態を反映するための読み取り専用の記録である，という位置づけです．

# Git Reference と `git gc`

`git gc`のgcは`garbage collection`です．
本記事ではこの`git gc`の詳細については触れませんが，Referenceと関係がある部分についてのみ簡単に触れます．

Git Pro book [10.7 `Git Internals - Maintenance and Data Recovery`](https://git-scm.com/book/en/v2/Git-Internals-Maintenance-and-Data-Recovery)においては以下のような説明があります．

> The “gc” stands for garbage collect, and the command does a number of things:
> (中略..)
> and it removes objects that aren’t reachable from any commit and are a few months old.

garbage collectionはタイミングによって様々な動作をしますが，到達不可能なobjectが削除される可能性があります．
上記のGit Pro bookの説明では，`from any commit`とありますがこれは微妙に情報不足で，実際にはReferenceを起点にその最新コミットからの到達可能性が削除の判定基準となります．

つまり例えば，既存のコミットチェーンの先端にcommitオブジェクトを生成しても，Reference(ブランチ)を更新していなかった場合は，そのcommitオブジェクトが削除される可能性があるということです．

実際には複合的に条件がからむのでそこまで怯える必要はありませんが，Referenceはobjectの到達可能性の判定の起点とされていることは認識しておくと役に立つことがあるかもしれません．

# refs/heads の外側に独自コミットチェーンを作る

## 実現したいこと

先ほど`refs`配下にはGitが標準で予約して利用しているいくつかの名前空間があることを確認しました．
また，先ほど紹介したもの以外にも特定の機能で利用するために予約されているものが複数存在します．

しかし実は，予約されている名前を避ければ，自分で独自の名前空間をrefs配下に掘って利用することが可能です．

また，すでに学んだ通り，Gitではコミットチェーンを作ってリポジトリのルートディレクトリの履歴を管理していますが，すでに管理しているコミットチェーンとはまったく別のコミットチェーンを作って，本来そのリポジトリで管理したいもの以外のデータ・履歴を管理することができてしまいます．

本記事では実際にそれを手元で実験してみて，理解を深めることを目的としたいと思います．

なお，ここでは前回まで利用していたローカルリポジトリを使って実験を進めていきます．
```
$ git branch
  feature-x
* master
$ git log --oneline --graph --all
*   6cd2d6c (HEAD -> master) merge feature-x into master
|\
| * 26bc132 (feature-x) add feature-x.txt
* | 685147a modify hello.txt
|/
* fe8f494 add world.txt
* 40ca6cc first commit
```

## 独自のコミットチェーンを作る

さて，独自コミットチェーンを作るわけですが，本来のリポジトリの内容と完全に関連がないことを示す例として，空のtreeオブジェクトを作って，保持しているデータがなにもないコミットチェーンを作ってみようと思います．

さて，中身は空ですので，blobオブジェクトを生成する必要はありません．
treeオブジェクトを生成しますが，空ですので，/dev/nullを入力にしてみます．
```
$ git mktree < /dev/null
4b825dc642cb6eb9a060e54bf8d69288fbee4904
$ git cat-file -t 4b825dc642cb6eb9a060e54bf8d69288fbee4904
tree
$ git cat-file -p 4b825dc642cb6eb9a060e54bf8d69288fbee4904
```

さて，空のtreeができました．
ちなみにこのハッシュ値`4b825dc642cb6eb9a060e54bf8d69288fbee4904`は，空のtreeのハッシュ値として有名なようです．
ではcommitオブジェクトも作ります．
```
$ git commit-tree 4b825dc642cb6eb9a060e54bf8d69288fbee4904 -m "entry 1"
a068bd565f57ebb4059972e9a3aafc56ac3d2d05
$ git cat-file -t a068bd565f57ebb4059972e9a3aafc56ac3d2d05
commit
$ git cat-file -p a068bd565f57ebb4059972e9a3aafc56ac3d2d05
tree 4b825dc642cb6eb9a060e54bf8d69288fbee4904
author xxx yyy <zzz@example.com> 1786359519 +0900
committer xxx yyy <zzz@example.com> 1786359519 +0900

entry 1
```

では，このcommitオブジェクトを親に，もう一つcommitオブジェクトをつなげてしまいます．
もちろん空のtreeを指定します．
```
$ git commit-tree 4b825dc642cb6eb9a060e54bf8d69288fbee4904 -p a068bd565f57ebb4059972e9a3aafc56ac3d2d05 -m "entry 2"
b2899427a32affd188910695c148b0234262b69e
$ git cat-file -t b2899427a32affd188910695c148b0234262b69e
commit
$ git cat-file -p b2899427a32affd188910695c148b0234262b69e
tree 4b825dc642cb6eb9a060e54bf8d69288fbee4904
parent a068bd565f57ebb4059972e9a3aafc56ac3d2d05
author xxx yyy <zzz@example.com> 1786359673 +0900
committer xxx yyy <zzz@example.com> 1786359673 +0900

entry 2
```

さて，ここまでで作ったコミットチェーンは，以前までにmasterブランチやfeature-xで扱っていたものとは完全に異なる別のコミットチェーンとして作成されました．
しかし，そのツリーを指すrefやブランチはないので，一切参照を持たないコミットチェーンになってしまっています．

## 独自の参照を作成してみる

そこで参照を作成しますが，通常のブランチとは異なる独自の参照を作ってみようと思います．

```
$ git update-ref refs/mine/myref b2899427a32affd188910695c148b0234262b69e
$ cat .git/refs/mine/myref
b2899427a32affd188910695c148b0234262b69e
```
第一引数には，`refs/mine/myref`と指定されています．
これは，refs空間に新たにmineという名前空間を用意し，さらにその配下にmyrefという参照を作成するということになります．
そして当然，先ほど作成したコミットチェーンを指すように作成しました．

さて，この参照がどのような見え方をするか確認してみます．
```
$ git branch
  feature-x
* master
$ git branch --list
  feature-x
* master
$ git show-ref
26bc1326083057c158d96f3dea003331cd976af5 refs/heads/feature-x
6cd2d6c9e57aad1b7338c769714cc11d70b01376 refs/heads/master
b2899427a32affd188910695c148b0234262b69e refs/mine/myref
```
先ほど作成した`refs/mine/myref`は，git branchのような通常のブランチを確認するコマンドでは確認できませんでした．
`git show-ref`ユーティリティを使うと，refs配下に独自に拡張した名前空間配下に存在するrefも表示されるため，`refs/mine/myref`を確認することができました．

```
$ git log --all --graph --oneline
* b289942 entry 2
* a068bd5 entry 1
*   6cd2d6c (HEAD -> master) merge feature-x into master
|\
| * 26bc132 (feature-x) add feature-x.txt
* | 685147a modify hello.txt
|/
* fe8f494 add world.txt
* 40ca6cc first commit
$ git log --oneline refs/mine/myref
b289942 entry 2
a068bd5 entry 1
```
また，通常どおりに`git log`コマンドを実行しても，`refs/mine/myref`のコミットチェーンを確認することはできません．
`git log`コマンドに明示的に参照名を指定することで，指定した参照のコミットチェーンが確認できました．

ここで確認できたコミットチェーンは，このリポジトリが本来管理しているデータとはまったく異なります．
このような手順を踏むことで，リポジトリ内に含められない・含めたくないようなデータを，まったく別のコミットチェーン上で管理することができるのです．

