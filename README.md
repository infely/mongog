[![asciicast](https://asciinema.org/a/ELWz7L0eNXrn5GZIWfPVFiHb1.svg)](https://asciinema.org/a/ELWz7L0eNXrn5GZIWfPVFiHb1)

# mongog
MongoDB CLI management tool
- View your collections as tables
- Edit your documents as JSON in editor

# Usage
```sh
$ mongog db [collection [query[,projection]]]
```

## -h, --host <ip|domain>
Host
### Example
```sh
$ mongog -h 127.0.0.1 test friends
$ mongog -h domain.com test friends
```

## -p, --port <port>
Port
### Example
```sh
$ mongog -p 27017 test friends
```

## -s, --sort <string|object|order>
Sort order
### Example
```sh
$ mongog test friends -s last_name:1,first_name:1
$ mongog test friends -s '{_id: -1}'
$ mongog test friends -s -1
```

## -l, --limit <number>
Limit rows
### Example
```sh
mongog test friends -l 5
```

## -t, --truncate <number>
Truncate strings
### Example
```sh
mongog test friends -t 16
```

## -c, --create <string>
Create collection
### Example
```sh
mongog test -c friends
```

## -i, --insert
Insert document
### Example
```sh
mongog test friends -i
```

## -d, --delete
Delete document
### Example
```sh
mongog test friends '{char: "Ross Geller"}' -d
mongog test friends _id:5e400e74a5f94d4a974077be -d
mongog test friends 5e400e74a5f94d4a974077be -d
```
