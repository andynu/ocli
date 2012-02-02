# I miss the mysql commandline.
Come on oracle! You can do better than sqlplus.

# Installation

We'll be using ruby-oci8 so you'll need a copy of the oracle instant client.
http://www.oracle.com/technetwork/database/features/instant-client/index-097480.html

    git clone https://github.com/andynu/ocli
    cd ocli
    export LD_LIBRARY_PATH=/opt/instantclient_11_2
    bundle install
    export PATH=$PATH:`pwd`/bin

# Usage

    ocli

  * no options at the moment.
  * this drops you into the shell

# Shell

## help

    connect <connect_str> [<username>] [<password>]

    <sql> # execute oracle commands (prereq: use/connect)
    <sql> \g # output as yaml array
    <sql> \G # like mysql's

    show tables # lists all the tables in this connection
    show databases # list all known databases
    desc table_name # lists column details

    help # display this message
    help <command>

## help connect

    use my_db [<username>] [<password>]
          references keys to a hash in ~/ocli.yml
    use //host:port/service_name [<username>] [<password>]
          direct connection
    # TODO
    # use tns_name [<username>] [<password>]
    #       references keys in tnsnames.ora


# Configuration

## ~/.ocli.yml

You can keep full database connection details in your home directory.
I encourage you to lock it down.

    chmod 600 ~/.ocli.yml

Example:

    ---
    my_conn_name:
      # dsn
      dsn: //hostname:port/service_name
      # or long hand
      host: hostname
      port: 1521
      service_name: sn

      username: username
      password: password  # optional

# Examples

    > ocli
    >> use wiki
    >> select id,name from pages
    +----+-----------+
    | id | name      |
    +-------+--------+
    | 1  | top       |
    | 2  | projects  |
    | 3  | ripl      |
    | 4  | github    |
    ...

    >> select id,name from pages \g
    ---
    -
      id: 1
      name: top
    -
      id: 2
      name: projects
    ...

    >> select id,name from pages \G
    ---
    -
        id: 1
      name: top
    -
        id: 2
      name: projects
    ...


# TODO
  - allow tnsnames.ora keys in use()
  - commandline options
  - csv output

