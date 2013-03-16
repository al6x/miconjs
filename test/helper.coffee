require '../micon'

global.expect = require('chai').expect
global.p = (args...) -> console.log args...

Fiber = require 'fibers'
global.activateFiber = (fn) -> Fiber(fn).run()

beforeEach -> app.clear()