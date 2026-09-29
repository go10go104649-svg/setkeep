import test from 'node:test';
import assert from 'node:assert/strict';
import {parseAnytime,semanticData,hash,changes,normalize} from './parser.mjs';
import {OfficialSourceFetcher,safeUrl,publicAddress,robotsAllowed,retryAfter} from './fetcher.mjs';
import {createMonitorHandler} from './handler.mjs';
const source={url:'https://www.anytimefitness.co.jp/test/facility/',source_type:'facility_page',parser_type:'anytime',store_name:'テスト店',policy_status:'approved'};
const html=(items='<li>ダンベル</li><li>トレッドミル 3台</li>')=>`<h1>エニタイムフィットネス テスト店<span>マシンラインナップ</span></h1><div class="sub-machine-list"><div class="machine-item"><h2 class="area">マシンエリア</h2><div class="machine-list"><ul>${items}</ul></div></div></div>`;
const store=status=>`<div id="shop-main-name"><h1>テスト店</h1><span id="info-close">${status}</span></div><div id="shop-access"><div class="list"><div class="t">住所</div><div class="c">テスト住所<p>地図</p></div></div></div>`;
test('importer-compatible normalization, explicit quantity and no inferred kg counts',()=>{assert.equal(normalize(' Ａ B　'),'ab');const p=parseAnytime(html('<li>ダンベル 1~50kg</li><li>バイク 3台</li>'),source);assert.equal(p.equipment.find(e=>e.name.startsWith('ダンベル')).quantity,null);assert.equal(p.equipment.find(e=>e.name==='バイク').quantity,3);});
test('semantic hash ignores ads, comments, whitespace, item order and markup',async()=>{const a=parseAnytime(html(),source),b=parseAnytime('<script>closed</script><!-- changed -->'+html('<li><b>トレッドミル</b>　３台</li><li>ダンベル</li>')+'<footer>random ad</footer>',source);assert.equal(await hash(semanticData(a)),await hash(semanticData(b)));});
test('disappearance is ignored; explicit removal alone is tagged',()=>{const a=parseAnytime(html(),source),b=parseAnytime(html('<li>ダンベル</li>'),source);assert.equal(changes(a,b).missing_ignored.length,1);assert.equal(b.equipment.some(e=>e.explicit_removed),false);const c=parseAnytime(html('<li>ダンベル（撤去済み）</li>'),source);assert.equal(c.equipment[0].explicit_removed,true);});
test('scoped store status; generic advertising does not assert operating or closure',()=>{for(const [word,status]of [['一時休業中','temporarily_closed'],['営業再開','active'],['閉店しました','closed'],['ただいまオープン準備中','preopening'],['','unknown']])assert.equal(parseAnytime(store(word)+'<footer>他店舗閉店</footer>',{...source,source_type:'store_page'}).store.status,status);});
test('conflicting status is review only; identity/structure failure is not closure',()=>{assert.equal(parseAnytime(store('一時休業 営業再開'),{...source,source_type:'store_page'}).store.status,'conflict');assert.throws(()=>parseAnytime('page missing',source));assert.throws(()=>parseAnytime(html(),{...source,store_name:'別店'}));});
test('SSRF rejects IPs, other domains, credentials, file, query and redirects',async()=>{for(const url of ['http://www.anytimefitness.co.jp/test/','https://127.0.0.1/','https://169.254.169.254/','file:///etc/passwd','https://www.anytimefitness.co.jp.evil.test/','https://user@www.anytimefitness.co.jp/test/','https://www.anytimefitness.co.jp/test/?url=x'])assert.throws(()=>safeUrl(url));for(const ip of ['127.0.0.1','10.1.2.3','169.254.169.254','172.16.1.1','192.168.0.1','::1','fc00::1','::ffff:127.0.0.1'])assert.equal(publicAddress(ip),false);assert.equal(publicAddress('8.8.8.8'),true);const f=new OfficialSourceFetcher({resolve:async()=>['127.0.0.1'],fetchImpl:()=>{throw Error('must not fetch');},sleep:async()=>{}});assert.match((await f.run(source)).error,/unsafe DNS/);});
test('robots groups, allow/disallow, crawl delay and Retry-After',()=>{assert.equal(robotsAllowed('User-Agent : *\nDisallow:','/test/'),true);assert.equal(robotsAllowed('User-agent: *\nDisallow: /','/test/'),false);assert.equal(robotsAllowed('User-agent: *\nDisallow: /\nAllow: /test/','/test/'),true);assert.equal(robotsAllowed('User-agent: *\nCrawl-delay: 20','/test/'),false);assert.equal(retryAfter('120',0),'1970-01-01T00:02:00.000Z');});
function fetcher(response){const requests=[];const f=new OfficialSourceFetcher({resolve:async()=>['8.8.8.8'],sleep:async()=>{},fetchImpl:async(url,opts)=>{requests.push({url,opts});return url.endsWith('robots.txt')?new Response('User-agent: *\nDisallow:'):response();}});return {f,requests};}
test('ETag/Last-Modified and 304 skip parser; no baseline 304 is an error',async()=>{const {f,requests}=fetcher(()=>new Response(null,{status:304}));const r=await f.run({...source,current_data:parseAnytime(html(),source),etag:'test',last_modified:'yesterday'});assert.equal(r.not_modified,true);assert.equal(requests[1].opts.headers['If-None-Match'],'test');assert.equal((await f.run(source)).not_modified,undefined);});
test('404/403/5xx/timeout/parse errors yield no normalized observations',async()=>{for(const status of [404,403,500,429]){const {f}=fetcher(()=>new Response('',{status,headers:{'Retry-After':'300'}}));const r=await f.run(source);assert.ok(r.error);assert.equal(r.parsed_data,undefined);}const {f}=fetcher(()=>new Response('<html>broken</html>',{headers:{'Content-Type':'text/html'}}));assert.match((await f.run(source)).error,/parse_error/);const timeout=fetcher(()=>{throw Error('timeout');});assert.match((await timeout.f.run(source)).error,/timeout/);});
test('policy unapproved never performs network access',async()=>{const {f,requests}=fetcher(()=>{throw Error('no');});assert.match((await f.run({...source,policy_status:'needs_review'})).error,/policy/);assert.equal(requests.length,0);});
test('external redirect rejected before fetching destination',async()=>{const {f,requests}=fetcher(()=>new Response(null,{status:302,headers:{Location:'https://example.com/'}}));assert.match((await f.run(source)).error,/disallowed URL/);assert.equal(requests.length,2);});
test('one-use job claim gates handler; user supplied URL is never fetched',async()=>{let calls=0;const h=createMonitorHandler({rpc:async()=>null,resolve:async()=>[],fetchImpl:()=>{calls++;}});const r=await h(new Request('https://edge.test/',{method:'POST',body:JSON.stringify({token:'00000000-0000-4000-8000-000000000001',url:'http://localhost/'})}));assert.equal(r.status,401);assert.equal(calls,0);});
test('parser upgrade forces a full fetch and rejects an unexpected 304',async()=>{
 const {f,requests}=fetcher(()=>new Response(null,{status:304}));
 const result=await f.run({...source,current_parser_version:'old-version',current_data:{},etag:'old',last_modified:'yesterday'});
 assert.equal(requests[1].opts.headers['If-None-Match'],undefined);
 assert.equal(requests[1].opts.headers['If-Modified-Since'],undefined);
 assert.match(result.error,/parser upgrade/);
});
test('size limit rejects response before parsing',async()=>{
 const {f}=fetcher(()=>new Response('x',{headers:{'Content-Type':'text/html','Content-Length':'1500001'}}));
 assert.match((await f.run(source)).error,/too large/);
});
test('successful worker uses claimed source and persists one normalized result',async()=>{
 const calls=[];let claim=0;
 const handler=createMonitorHandler({
  rpc:async(name,args)=>{calls.push({name,args});if(name==='claim_official_fetch')return claim++===0?source:null;return {snapshot_id:'snapshot'};},
  resolve:async()=>['8.8.8.8'],sleep:async()=>{},
  fetchImpl:async url=>url.endsWith('robots.txt')?new Response('User-agent: *\nDisallow:'):new Response(html(),{headers:{'Content-Type':'text/html'}}),
 });
 const request=()=>new Request('https://edge.test/',{method:'POST',body:JSON.stringify({token:'00000000-0000-4000-8000-000000000001',url:'http://localhost/'})});
 assert.equal((await handler(request())).status,200);
 assert.equal(calls[1].name,'finish_official_fetch');
 assert.equal(calls[1].args.result.parsed_data.equipment.length,2);
 assert.equal((await handler(request())).status,401);
 assert.equal(calls.length,3);
});

test('oversized untrusted body is rejected before any database or fetch call',async()=>{
 let called=false;
 const handler=createMonitorHandler({rpc:async()=>{called=true;},resolve:async()=>[]});
 const r=await handler(new Request('https://edge.test/',{method:'POST',body:'x'.repeat(1100)}));
 assert.equal(r.status,413);assert.equal(called,false);
});
