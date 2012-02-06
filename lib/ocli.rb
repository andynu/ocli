
require 'ripl'
require 'ripl/color_result'
require 'ripl/color_streams'
require 'ripl/rc'

require 'logger'
require 'yaml'
require 'bigdecimal'

require 'oci8' # database adapter
require 'highline/import'
require 'terminal-table'

module Ocli

  ORACLE_KEYWORDS = %w[
    access  else  modify  start add exclusive noaudit select
    all exists  nocompress  session alter file  not set
    and float notfound  share any for nowait  size
    arraylen  from  null  smallint as  grant number  sqlbuf
    asc group of  successful audit having  offline synonym
    between identified  on  sysdate by  immediate online  table
    char  in  option  then check increment or  to
    cluster index order trigger column  initial pctfree uid
    comment insert  prior union compress  integer privileges  unique
    connect intersect public  update create  into  raw user
    current is  rename  validate date  level resource  values
    decimal like  revoke  varchar default lock  row varchar2
    delete  long  rowid view desc  maxextents  rowlabel  whenever
    distinct  minus rownum  where drop  mode  rows  with
    describe
  ]

  module Shell

    def oracle_keywords
      @oracle_keywords = ORACLE_KEYWORDS + ORACLE_KEYWORDS.map(&:upcase)
      @oracle_keywords
    end
    def before_loop
      super
    end

    def loop_eval(expression)
      ret = nil
      expressions = [expression.split(/;/)].flatten.compact
      expressions.each do |expression|
        expression.strip!
        case expression
        when ""
          # do nothing.

        # ::Runtime commands
        when /^(commit|connect\s+|query\s+|use\s+|show\s+|show_tables|show_databases|help|echo\s+|desc\s+)/
          Ripl.config[:rocket_mode] = false
          args = expression.split /\s+/
          Shell.runtime.send(*args)

        when /^(#{oracle_keywords.join("|")})\s+.*\\g/
          Shell.runtime.ascii_pivot_query(expression.gsub(/\\g$/,''))

        when /^(#{oracle_keywords.join("|")})\s+.*\\G/
          Shell.runtime.ascii_pivot_right_query(expression.gsub(/\\G$/,''))

        # Oracle SQL Commands (ascii)
        when /^(#{oracle_keywords.join("|")})\s+/
          Shell.runtime.ascii_query(expression)

        # Ripl (like irb)
        else
          ret = super
        end
      end
      if ret.nil?
        Ripl.config[:rocket_mode] = false
      else
        Ripl.config[:rocket_mode] = true
      end
      ret
    end

    def print_result(result)
      super unless result.nil?
    end

    def self.runtime
      @runtime ||= ::Ocli::Runtime.new
    end
  end

  class Runtime

    def initialize
      @log = Logger.new(STDERR)
      @log.level = Logger::INFO
      @log.formatter = proc do |severity, datetime, progname, msg|
        "#{severity}: #{msg}\n"
      end

      @config = {}
      yaml = File.join(ENV["HOME"] || "~", ".ocli.yml")
      @config = YAML.load_file(yaml) || {} if File.exists?(yaml)

      @tns_names ||= {}

      @databases = @config.keys + @tns_names.keys
      @databases.sort!
    end

    def log
      @log
    end

    # connection_string
    #   yaml_name [username] [password]
    #   tns_name username [password]
    #   //host:port/service_name username [password]
    #
    #  yaml_name
    #   references the keys from ~/.ocli.yml
    #   ---
    #   my_conn_name:
    #    # dsn
    #    dsn: //hostname:port/service_name
    #    # or long hand
    #    host: hostname
    #    port: 1521
    #    service_name: sn
    #
    #    username: username
    #    password: password  # optional
    def connect(connection_string,*args)

      case connection_string
      when *@config.keys
        # YAML
        config = @config[connection_string]
        if config['dsn']
          @dsn = config['dsn']
        else
          host = config['host'] || 'localhost'
          port = config['port'] || 1521
          service_name = config['service_name']
          @dsn = "//%s:%s/%s" % [ host, port, service_name ]
        end

        @username = config['username'] unless config['username'].nil?
        @password = config['password'] unless config['password'].nil?

      # TNS: tns_name [username] [password]
      when *@tns_names.keys
        log.info "Establishing tns_name connection"
        @dsn = connection_string

      when /^\/\//
        # Oracle: //host:port/service_name [username] [password]
        @dsn = connection_string

      else
        log.error "unknown connection string '#{connection_string}'"
      end

      # args overrides
      username, password = args
      password = nil if @username != username # dependent
      @username = username unless username.nil?
      @password = password unless password.nil?

      # ensure variables
      @dsn ||= ask("dsn: ")
      @username ||= ask("username: ")
      @password ||= ask("password: ") {|q| q.echo = false } # shh

      log.info "Connecting to #{@dsn} as #{@username}"
      begin
        @db = OCI8.new(@username,@password, @dsn)
      rescue OCIError => e
        log.error e
        return
      end

      cursor = query("select table_name from user_tables")
      @tables = to_arr(cursor).flatten.sort.map(&:downcase)

      @result = {
        db: @db,
        time: Time.new,
        tables: @tables.count,
      }
      log.debug @result
      #@db = OCI8.new(username, password, dsn)
    end
    alias :use :connect

    def query(sql, params={})
      log.debug [sql,params]
      cursor = @db.parse(sql)
      sql_params = sql.scan(/:(\w+)/).flatten.uniq
      params.each_pair do |name, value|
        log.debug "bind :#{name} => #{value}"
        cursor.bind_param(":#{name}", value)
      end
      cursor.exec()
      cursor
    end

    def commit
      @db.commit
    end

    def to_arr(cursor)
      rows = []
      while (row = cursor.fetch)
        rows << row
      end
      rows
    end

    def to_txt(cursor)
      table = Terminal::Table.new

      while (row = cursor.fetch)
        txt_row = row.map{|e| 
          case e
          when BigDecimal # why is the default to_s in scientific notation?!
            e.to_f
          else
            e
          end
        }
        table.add_row txt_row
      end

      columns = []
      cursor.column_metadata.each_with_index do |meta,i|
        columns << meta.name
        if [:number, :binary_float, :binary_double].include?(meta.data_type)
          table.align_column(i, :right) 
        end
      end
      table.headings = columns

      puts table
    end

    def to_pivot_txt(cursor, justify=:left)
      columns = []
      max_col_len = 10
      cursor.column_metadata.each do |meta|
        col = meta.name.downcase
        columns << col
        max_col_len = col.length if col.length > max_col_len
      end

      case justify
      when :left
        fmt = "  %s: %s"
      else
        fmt = "  %0#{max_col_len}s: %s"
      end

      puts "---"
      while (row = cursor.fetch)
        puts "-"
        row.each_with_index do |val,i|
          puts(fmt % [columns[i],val])
        end
      end
    end

    def ascii_query(sql,params={})
      result = query(sql,params)
      case sql
      when /^select/
        to_txt(query(sql,params))
      else
        p result
      end
      nil
    end

    def ascii_pivot_query(sql,params={})
      to_pivot_txt(query(sql,params))
    end

    def ascii_pivot_right_query(sql,params={}, justify=:right)
      to_pivot_txt(query(sql,params), justify)
    end

    def show_tables
      puts @tables
    end

    def show_databases
      puts @databases
    end

    def show(obj,*args)
      case obj
      when 'tables'
        show_tables
      when 'databases'
        show_databases
      else
        log.error "Unknown show object '#{obj}'"
      end
    end

    def desc(obj,*args)
      case obj
      when *@tables
        # | TABLE_NAME | COLUMN_NAME                    | DATA_TYPE | DATA_TYPE_MOD | DATA_TYPE_OWNER | DATA_LENGTH | DATA_PRECISION | DATA_SCALE | NULLABLE | COLUMN_ID | DEFAULT_LENGTH | DATA_DEFAULT | NUM_DISTINCT | LOW_VALUE                | HIGH_VALUE                 | DENSITY              | NUM_NULLS | NUM_BUCKETS | LAST_ANALYZED             | SAMPLE_SIZE | CHARACTER_SET_NAME | CHAR_COL_DECL_LENGTH | GLOBAL_STATS | USER_STATS | AVG_COL_LEN | CHAR_LENGTH | CHAR_USED | V80_FMT_IMAGE | DATA_UPGRADED | HISTOGRAM   
        ascii_query("select column_name, data_type, nullable from user_tab_columns where table_name=:table_name", table_name: obj.upcase)
      else
        ascii_query([obj,args].flatten.join(" "))
      end
    end

    def echo(str="")
      puts "-- #{str}"
    end

    def help(usage_for=nil)
      case usage_for
      when 'readme'
      when 'connect', 'use'
        puts <<-HELP
  use my_db [<username>] [<password>]
        references keys to a hash in ~/ocli.yml
  use //host:port/service_name [<username>] [<password>]
        direct connection
  # TODO
  # use tns_name [<username>] [<password>]
  #       references keys in tnsnames.ora
        HELP
      else
        puts <<-HELP
  help # for a list of commands
  help <command>
  connect <connect_str> [<username>] [<password>]
  show tables # lists all the tables in this connection
  show databases # list all known databases
  desc table_name # lists column details
  <sql> # execute oracle commands (prereq: use/connect)
        HELP
      end
    end
  end


  def self.init
    Shell.runtime
  end


  def to_s
    "ocli"
  end

end

Ripl::Commands.send :include, Ocli
Ripl::Shell.send :include, Ocli::Shell
require 'ripl/multi_line'

