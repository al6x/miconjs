Micon = require '../micon'

global.app    = new Micon()
global.expect = require('chai').expect
global.p      = (args...) -> console.log args...

global.sync = require 'synchronize'

beforeEach ->
  app.clear()
  Micon.clear()