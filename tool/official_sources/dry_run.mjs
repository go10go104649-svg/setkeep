// Read-only: saved HTTP responses or explicit approved registry fetches. Never writes DB.
import {readFile,writeFile} from 'node:fs/promises';
import {lookup} from 'node:dns/promises';
import {OfficialSourceFetcher} from '../../supabase/functions/gym-official-monitor/fetcher.mjs';
import {parseAnytime,hash,semanticData,changes,PARSER_VERSION} from '../../supabase/functions/gym-official-monitor/parser.mjs';
const [input, output] = process.argv.slice(2);
if(!input || !output)throw new Error('Usage: node dry_run.mjs sources.json output.json');
const sources=JSON.parse(await readFile(input,'utf8')),results=[];
const fetcher=new OfficialSourceFetcher({resolve:async host=>(await lookup(host,{all:true})).map(x=>x.address)});
for(const source of sources){
 let result;
 if(source.saved_html){
  try {const html=await readFile(source.saved_html,'utf8'),parsed=parseAnytime(html,source);result={http_status:200,parser_version:PARSER_VERSION,parsed_data:parsed,content_hash:await hash(html),parsed_hash:await hash(semanticData(parsed)),diff:changes(source.current_data,parsed),mode:'saved_response_dry_run'};}
  catch(e){result={error:e.message,mode:'saved_response_dry_run'};}
 }else result=await fetcher.run(source);
 results.push({id:source.id,url:source.url,...result});
}
await writeFile(output,JSON.stringify(results,null,2));
console.log(JSON.stringify({sources:results.length,parsed:results.filter(r=>r.parsed_data).length,errors:results.filter(r=>r.error).length,equipment:results.map(r=>({id:r.id,count:r.parsed_data?.equipment.length??0}))}));
