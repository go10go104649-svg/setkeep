import {parsers, PARSER_VERSION, hash, semanticData, changes} from './parser.mjs';
export const USER_AGENT = 'SETKEEP-OfficialMonitor/1.0 (+https://github.com/setkeep/setkeep)';
export const ALLOWED_HOSTS = ['www.anytimefitness.co.jp'];
export function safeUrl(input) {
  const u = new URL(input);
  if (u.protocol !== 'https:' || u.port || u.username || u.password || !ALLOWED_HOSTS.includes(u.hostname) || u.search || u.hash) throw new Error('manual_review: disallowed URL');
  return u;
}
export function publicAddress(ip) {
  if (ip.includes(':')) return /^(2|3)[0-9a-f]{0,3}:/i.test(ip) && !/^2001:db8:/i.test(ip);
  const a=ip.split('.').map(Number);
  return a.length===4 && a.every(n=>Number.isInteger(n)&&n>=0&&n<=255) && ![0,10,127].includes(a[0]) && a[0]<224 && !(a[0]===169&&a[1]===254) && !(a[0]===172&&a[1]>=16&&a[1]<=31) && !(a[0]===192&&(a[1]===168||a[1]===0)) && !(a[0]===100&&a[1]>=64&&a[1]<=127) && !(a[0]===198&&[18,19,51].includes(a[1])) && !(a[0]===203&&a[1]===0);
}
export function robotsAllowed(body,path) {
  const groups=[];let agents=[],rules=[],sawRules=false;
  const flush=()=>{if(agents.length)groups.push({agents,rules});agents=[];rules=[];sawRules=false;};
  for(const line of body.split(/\r?\n/)) {
    const m=line.replace(/#.*/,'').match(/^\s*([\w-]+)\s*:\s*(.*?)\s*$/);if(!m)continue;
    const k=m[1].toLowerCase(),v=m[2];
    if(k==='user-agent'){if(sawRules)flush();agents.push(v.toLowerCase());}
    else if(['allow','disallow','crawl-delay'].includes(k)){sawRules=true;rules.push({k,v});}
  }flush();
  const specific=groups.filter(g=>g.agents.some(a=>a!=='*'&&USER_AGENT.toLowerCase().startsWith(a)));
  const matching=(specific.length?specific:groups.filter(g=>g.agents.includes('*'))).flatMap(g=>g.rules);
  // Larger delays than our per-host spacing require manual policy review.
  if(matching.some(r=>r.k==='crawl-delay'&&Number(r.v)>2)) return false;
  const applicable=matching.filter(r=>r.k!=='crawl-delay'&&r.v).filter(r=>new RegExp('^'+r.v.split('*').map(x=>x.replace(/[.+?^{}()|[\]\\]/g,'\\$&')).join('.*')).test(path));
  applicable.sort((a,b)=>b.v.length-a.v.length || (a.k==='allow'?-1:1));
  return !applicable.length || applicable[0].k==='allow';
}
export function retryAfter(value,now=Date.now()) {
  const seconds=/^\d+$/.test(value??'')?Number(value)*1000:Date.parse(value??'')-now;
  return Number.isFinite(seconds)?new Date(now+Math.max(0,seconds)).toISOString():null;
}
export class OfficialSourceFetcher {
  constructor({fetchImpl=fetch,resolve,sleep=ms=>new Promise(r=>setTimeout(r,ms))}) {this.fetch=fetchImpl;this.resolve=resolve;this.sleep=sleep;}
  async request(url,headers={}) {
    for(let i=0;i<4;i++) {
      const u=safeUrl(url);const addresses=await this.resolve(u.hostname);
      if(!addresses.length||addresses.some(ip=>!publicAddress(ip)))throw new Error('manual_review: unsafe DNS');
      const r=await this.fetch(u.href,{redirect:'manual',headers:{'User-Agent':USER_AGENT,...headers},signal:AbortSignal.timeout(15000)});
      if([301,302,303,307,308].includes(r.status)) {url=safeUrl(new URL(r.headers.get('location')??'',u).href).href;await r.body?.cancel();await this.sleep(2000);continue;}
      return r;
    }throw new Error('manual_review: redirect limit');
  }
  async body(r,max=1500000) {
    if(Number(r.headers.get('content-length'))>max) {await r.body?.cancel();throw new Error('parse_error: response too large');}
    const reader=r.body?.getReader();if(!reader)return '';
    const chunks=[];let size=0;
    while(true){const {done,value}=await reader.read();if(done)break;size+=value.length;if(size>max){await reader.cancel();throw new Error('parse_error: response too large');}chunks.push(value);}
    const bytes=new Uint8Array(size);let i=0;for(const c of chunks){bytes.set(c,i);i+=c.length;}return new TextDecoder().decode(bytes);
  }
  async run(source) {
    const result={http_status:null,parser_version:PARSER_VERSION,fetched_at:new Date().toISOString(),fetch_metadata:{user_agent:USER_AGENT},error:null};
    try {
      safeUrl(source.url);
      if(source.policy_status!=='approved')throw new Error('manual_review: site policy requires review');
      const robots=await this.request(new URL('/robots.txt',source.url).href);
      if(robots.status!==200) {result.fetch_metadata.retry_after=retryAfter(robots.headers.get('retry-after'));await robots.body?.cancel();throw new Error('manual_review: robots unavailable');}
      if(!robotsAllowed(await this.body(robots,100000),new URL(source.url).pathname))throw new Error('manual_review: robots disallow');
      await this.sleep(2000);
      const headers={};const compatible=!source.current_parser_version||source.current_parser_version===PARSER_VERSION;if(compatible&&source.etag)headers['If-None-Match']=source.etag;if(compatible&&source.last_modified)headers['If-Modified-Since']=source.last_modified;
      const r=await this.request(source.url,headers);result.http_status=r.status;
      result.fetch_metadata={...result.fetch_metadata,etag:r.headers.get('etag'),last_modified:r.headers.get('last-modified'),retry_after:retryAfter(r.headers.get('retry-after'))};
      if(r.status===304) {await r.body?.cancel();if(!compatible)throw new Error('parse_error: 304 after parser upgrade');if(!source.current_data)throw new Error('parse_error: 304 without baseline');return {...result,not_modified:true};}
      if(r.status!==200){await r.body?.cancel();throw new Error([401,403,429].includes(r.status)?'manual_review: HTTP '+r.status:'fetch_error: HTTP '+r.status);}
      if(!r.headers.get('content-type')?.includes('text/html')) {await r.body?.cancel();throw new Error('parse_error: expected HTML');}
      const html=await this.body(r),parser=parsers[source.parser_type];if(!parser)throw new Error('parse_error: unknown parser');
      const parsed=parser(html,source);
      return {...result,content_hash:await hash(html),parsed_hash:await hash(semanticData(parsed)),parsed_data:parsed,fetch_metadata:{...result.fetch_metadata,diff:changes(source.current_data,parsed)}};
    } catch(e) {return {...result,error:String(e.message).slice(0,400)};}
  }
}
