require 'ripl'
require 'ripl/color_result'
require 'ripl/color_streams'
require 'ripl/rc'

require 'ripl/silence_ruby'
require 'ripl/echo'

require 'oci8' # database adapter



require 'ripl/multi_line'

class Ocli

  ORACLE_KEYWORDS = %w[
    access  else  modify  start
    add exclusive noaudit select
    all exists  nocompress  session
    alter file  not set
    and float notfound  share
    any for nowait  size
    arraylen  from  null  smallint
    as  grant number  sqlbuf
    asc group of  successful
    audit having  offline synonym
    between identified  on  sysdate
    by  immediate online  table
    char  in  option  then
    check increment or  to
    cluster index order trigger
    column  initial pctfree uid
    comment insert  prior union
    compress  integer privileges  unique
    connect intersect public  update
    create  into  raw user
    current is  rename  validate
    date  level resource  values
    decimal like  revoke  varchar
    default lock  row varchar2
    delete  long  rowid view
    desc  maxextents  rowlabel  whenever
    distinct  minus rownum  where
    drop  mode  rows  with
  ]

  module Shell 
    def before_loop
      super
    end

    def loop_eval(expression)
      case expression

      # State Commands
      when /^(connect)/
        args = expression.split /\s+/
        Shell.runtime.send(*args)
        
      # Oracle Commands
      when /^#{ORACLE_KEYWORDS.join("|")}/
        Ripl.config[:rocket_mode] = false
        puts "ORACLE COMMAND!"
        puts expression
        #puts Kernel.eval(expression, self)

      else 
        Ripl.config[:rocket_mode] = true
        puts super
      end
    end

    def self.runtime
      @runtime ||= ::Ocli::Runtime.new
    end
  end

  class Runtime

    # connection_string
    #   yaml_name [username] [password]
    #   tns_name username [password]
    #   //host:port/service_name username [password]
    #
    def connect(connection_string,*args)
      tns_names = []
      case connection_string
      when tns_names.include?(connection_string)
        puts "establishing tns_name connection"
      when /^:/

      # Oracle dsn [username] [password]
      when /^\/\//
        #match = connection_string.match(/^\/\/(\w+):(\d+)\/(\w+)/)
        #cmd, host, port, service_name = match.to_a
        #p [host, port, service_name]

        @dsn = connection_string
        p @dsn
        p [@username, @password]
        username, password = args
        @username = username unless username.nil?
        @password = password unless password.nil?
        p [@username, @password]

        @db = OCI8.new(@username,@password, @dsn)

        @result = {
          db: @db,
          time: Time.new
        }
        p @result
      else
        $stderr.puts "unknown connection string '#{connection_string}'"
      end

      #@db = OCI8.new(username, password, dsn)
    end
  end


  def self.init
  end

  def exec(*sql)
    puts 'sql:'
    puts sql.join(' ')
  end

  def echo(str="")
    puts "-- #{str}"
  end

  def help(usage_for=nil)
    case usage_for
    when 'readme'
    else
      puts <<-HELP
> help # for a list of commands
      HELP
    end
  end

  #def method_missing(m, *args, &block)
  #  if ORACLE_KEYWORDS.include? m.downcase
  #    puts [m,args].flatten.join(" ")
  #  else
  #    super
  #  end
  #end

  def to_s
    "ocli"
  end

end

Ripl::Shell.send :include, Ocli::Shell

