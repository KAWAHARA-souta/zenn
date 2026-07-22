This repository is for zenn contents

* [📘 How to use Zenn CLI](https://zenn.dev/zenn/articles/zenn-cli-guide)



## How to use zenn-cli container

### Enviroment
On fedora, 
- podman (Docker)
- podman-compose

```
 # dnf install podman podman-compose
```

### Build the container image
```
 $ podman compose build
```

### Start the preview server
```
 $ podman compose up -d
```
Open http://localhost:8000 in your browser to preview articles.

### Stop the preview server
```
 $ podman compose down
```

### Run any other zenn-cli command
i.e.) create a new article
```
 $ podman compose run --rm zenn npx zenn new:article
```

#### My own template to create a new article

**Create a new article**
```
$ podman compose run --rm zenn npx zenn new:article --slug hogehuga --title "awful document"
```

**lint (using list subcommand as a alternative)**
(There isn't dedicated lint subcommand. list subcommand cat be used as a alternative for lint for all articles/books)
```
$ podman compose run --rm zenn npx zenn list:articles
```

