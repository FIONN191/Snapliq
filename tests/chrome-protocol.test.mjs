import test from "node:test";
import assert from "node:assert/strict";
import {request,responseStatus,ACTIONS} from "../apps/chrome/protocol.mjs";
test("only desktop request actions can be serialized",()=>{for(const action of ACTIONS)assert.deepEqual(request(action,"123"),{action,requestId:"123"});for(const action of ["execute","file","captureTab",null,{}])assert.throws(()=>request(action,"id"));assert.equal(request("ping","a".repeat(300)).requestId.length,128)});
test("acknowledgements do not claim capture completion",()=>{assert.match(responseStatus({ok:true},"capture"),/请求/);assert.match(responseStatus({ok:true},"record"),/选择/);for(const error of ["desktop_timeout","desktop_not_running","invalid_request"])assert.equal(typeof responseStatus({ok:false,error},"capture"),"string")});
