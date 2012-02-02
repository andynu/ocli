#
# usage:
#   watchr test/tests.watchr
#
watch("#{__FILE__}|(bin|lib|test)/.*") { |match|
  puts "---"
  puts "running tests #{Time.new}"
  puts
  system('ruby test/*.rb')
  puts
}

# vim: ft=ruby
