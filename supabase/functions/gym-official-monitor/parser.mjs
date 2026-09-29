// Same NFKC + lowercase + whitespace rule as import_anytime_master.normalized.
export const normalize = value => String(value ?? '').normalize('NFKC').toLowerCase().replace(/\s+/gu, '');
export const PARSER_VERSION = 'anytime-1';
const decode = s => s.replace(/&#(x[\da-f]+|\d+);/gi, (_, n) => String.fromCodePoint(n[0].toLowerCase() === 'x' ? parseInt(n.slice(1), 16) : Number(n))).replace(/&(amp|lt|gt|quot|apos|nbsp);/g, (_, k) => ({amp:'&',lt:'<',gt:'>',quot:'"',apos:"'",nbsp:' '})[k]);
// Small structural tokenizer, not a whole-page keyword scraper. Ignore scripts,
// comments and styles; select only known local store/facility sections.
function tree(html) {
  const root = {tag:'root',attrs:{},children:[]}, stack = [root];
  html = html.replace(/<!--[\s\S]*?-->|<(script|style)\b[^>]*>[\s\S]*?<\/\1>/gi, '');
  for (const token of html.match(/<[^>]+>|[^<]+/g) ?? []) {
    if (token.startsWith('</')) {
      const tag = token.match(/^<\/([\w-]+)/)?.[1].toLowerCase();
      const i = stack.findLastIndex(n => n.tag === tag); if (i > 0) stack.length = i;
    } else if (/^<[a-z]/i.test(token)) {
      const tag = token.match(/^<([\w-]+)/)[1].toLowerCase(), attrs = {};
      for (const m of token.matchAll(/([\w-]+)\s*=\s*(?:"([^"]*)"|'([^']*)'|([^\s>]+))/g)) attrs[m[1]] = decode(m[2] ?? m[3] ?? m[4]);
      const node = {tag, attrs, children:[]};stack.at(-1).children.push(node);
      if (!['br','img','meta','link','input','hr','source','wbr'].includes(tag) && !token.endsWith('/>')) stack.push(node);
    } else if (!token.startsWith('<')) stack.at(-1).children.push(decode(token));
  }
  return root;
}
const all = (n, predicate) => typeof n === 'string' ? [] : [...(predicate(n) ? [n] : []), ...n.children.flatMap(c => all(c,predicate))];
const text = n => !n ? '' : (typeof n === 'string' ? n : n.children.map(text).join(' ')).replace(/\s+/gu,' ').trim();
const byId = (n,id) => all(n,e => e.attrs.id === id)[0];
const hasClass = (n,c) => (n.attrs.class ?? '').split(/\s+/).includes(c);
export function parseAnytime(html, source) {
  const dom = tree(html), facility = source.source_type === 'facility_page';
  const header = facility ? all(dom,n=>n.tag==='h1')[0] : byId(dom,'shop-main-name');
  let name = text(facility ? header : all(header ?? dom,n=>n.tag==='h1')[0]);
  name = name.replace(/^エニタイムフィットネス\s*/,'').replace(/\s*マシンラインナップ$/,'').trim();
  if (!name || !header || !name.endsWith('店')) throw new Error('parse_error: store identity missing');
  if (source.store_name && normalize(name) !== normalize(source.store_name)) throw new Error('manual_review: store identity changed');
  const statusNodes = [byId(dom,'info-close'),byId(dom,'preparing')].filter(Boolean);
  const statusText = statusNodes.map(text).join(' ').trim();
  const statuses = new Set();
  if (/オープン準備中|オープン予定/.test(statusText)) statuses.add('preopening');
  if (/一時休業|臨時休業/.test(statusText)) statuses.add('temporarily_closed');
  if (/閉店|営業終了/.test(statusText)) statuses.add('closed');
  if (/営業再開|営業中/.test(statusText)) statuses.add('active');
  const status = statuses.size === 1 ? [...statuses][0] : statuses.size ? 'conflict' : 'unknown';
  const access = byId(dom,'shop-access');
  const addressRow = all(access ?? {children:[],attrs:{}}, n => hasClass(n,'list')).find(n => all(n,c=>hasClass(c,'t')).some(c=>text(c)==='住所'));
  const addressNode = addressRow && all(addressRow,n=>hasClass(n,'c'))[0];
  const address = addressNode ? text({...addressNode, children: addressNode.children.filter(n=>typeof n==='string' || !['a','p'].includes(n.tag))}) : null;
  const items = [];
  if (facility) {
    const container = all(dom,n=>hasClass(n,'sub-machine-list'))[0];
    if (!container) throw new Error('parse_error: facility structure missing');
    for (const block of all(container,n=>hasClass(n,'machine-item'))) {
      const area = text(all(block,n=>n.tag==='h2' && hasClass(n,'area'))[0]);
      for (const li of all(block,n=>n.tag==='li')) {
        const raw = text(li).normalize('NFKC'); if (!raw || raw.length > 200) throw new Error('parse_error: invalid equipment');
        // Only explicit terminal removal phrases. Mere disappearance never yields removal.
        const removed = /[（(\s:：](?:撤去済み|設置終了|撤去しました)[）)]?$/.test(raw);
        const clean = raw.replace(/[（(\s:：](?:撤去済み|設置終了|撤去しました)[）)]?$/,'').trim();
        const quantityMatch = clean.match(/\s+(\d+)台$/);
        const base = clean.replace(/\s+\d+台$/,'').trim();
        items.push({raw_name:raw,normalized_name:normalize(base),name:base,area,quantity:quantityMatch ? Number(quantityMatch[1]) : null,explicit_removed:removed});
      }
    }
    if (!items.length) throw new Error('parse_error: empty facility listing');
  }
  const equipment = [...new Map(items.map(e=>[e.area+'|'+e.normalized_name+'|'+e.explicit_removed,e])).values()].sort((a,b)=>(a.area+a.normalized_name).localeCompare(b.area+b.normalized_name,'en'));
  const links = all(dom,n=>n.tag==='a' && n.attrs.href?.endsWith('/facility/')).map(n=>new URL(n.attrs.href,source.url).href);
  return {schema_version:1,store:{name,status,address,official_url:source.url,exists:true,status_basis:statusText.slice(0,200)},equipment,equipment_listed:facility,facility_url:links[0] ?? null};
}
export const parsers = {anytime: parseAnytime};
export function semanticData(parsed) {
  return {store:{name:normalize(parsed.store.name),status:parsed.store.status,address:normalize(parsed.store.address)},equipment:parsed.equipment.map(e=>({name:e.normalized_name,area:normalize(e.area),quantity:e.quantity,removed:e.explicit_removed})).sort((a,b)=>JSON.stringify(a).localeCompare(JSON.stringify(b),'en'))};
}
export async function hash(value) {
  return [...new Uint8Array(await crypto.subtle.digest('SHA-256',new TextEncoder().encode(typeof value==='string'?value:JSON.stringify(value))))].map(v=>v.toString(16).padStart(2,'0')).join('');
}
export function changes(previous, current) {
  if (!previous) return {baseline:true,listed:current.equipment.length,missing_ignored:[]};
  const keys = new Set(current.equipment.map(e=>e.area+'|'+e.normalized_name));
  return {baseline:false,previous_status:previous.store.status,current_status:current.store.status,missing_ignored:previous.equipment.filter(e=>!keys.has(e.area+'|'+e.normalized_name)).map(e=>e.raw_name)};
}
