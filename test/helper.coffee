_     = require 'underscore'
Fiber = require 'fibers'

global.expect = require('chai').expect
global.p = (args...) -> console.log args...

global.activateFiber = (fn) -> Fiber(fn).run()

beforeEach -> app.clear()

# `Object.defineProperty(Object.prototype, 'should', {
#   set: function(){},
#   get: function(){
#     return expect(this.valueOf() == this ? this.valueOf() : this).to;
#   },
#   configurable: true
# });`