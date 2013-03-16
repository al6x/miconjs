Fiber = require 'fibers'

global.app    = require '../micon'
global.expect = require('chai').expect
global.p = (args...) -> console.log args...

global.activateFiber = (fn) -> Fiber(fn).run()

beforeEach -> app.clear()