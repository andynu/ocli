#!/usr/bin/ruby env
$:.push File.expand_path('../../lib',__FILE__)

require 'ocli'
require 'test/unit'

class OcliTest < Test::Unit::TestCase
  def test_run
    ocli = Ocli.new
    assert !ocli.nil?
  end

  def test_runtime
    run = Ocli::Runtime.new
    assert run
    assert run.connect("//host:1521/sn")
  end
end

