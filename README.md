### RSstatus
mongo replica set status command line tool

### Why ?

Since mongo 3.x HTTP api is [not available](https://docs.mongodb.com/manual/release-notes/3.0-compatibility/#http-status-interface-and-rest-api-compatibility)  
(challenge-response user authentication mechanism is not suported)   
but the information in human readable format is needed.

### OMG why bash ?

If you know the madness of mongo ruby / python changes in gems / libraries,  
moreover, having pinned a specific version (of mentioned libraries) for tools that you already have  
makes everything complex to handle.  

So, to be agnostic from that, 
it was the only reasonable choice.  

### Requirements

Script is based on jshon or jq - JSON parser tools
just install one of it, like:

`apt-get install jshon || yum install jshon`
or
`apt-get install jq || yum install jq`

If system is secured,
create `readolny` user in mogodb with `clusterMonitor` role:

```
  db.createUser({
    "user": "readonly",
    "pwd": "readonly",
    "roles": [{
      "role": "clusterMonitor",
      "db": "admin"
    },]
  })

```

### Run

```
$ ./rsstatus.sh 
+---------------------------------------------------------------------------------------+
| Member               | Id | Up | Votes | Priority | State              | optime       |
| mongo-ams1-001:27017 | 0  | 1  | 1     | 2        | PRIMARY            | 593b1518:3   |
| mongo-ams1-002:27017 | 1  | 1  | 1     | 2        | SECONDARY          | 593b1518:3   |
| mongo-ams2-001:27017 | 2  | 1  | 0     | 0        | RECOVERING(hidden) | 5937d173:393 |
| mongo-ams2-002:27017 | 3  | 1  | 1     | 1        | SECONDARY          | 593b1518:3   |
+---------------------------------------------------------------------------------------+
```
