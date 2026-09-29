import {OfficialSourceFetcher} from './fetcher.mjs';
export function createMonitorHandler({rpc,resolve,fetchImpl=fetch}) {
 const fetcher=new OfficialSourceFetcher({resolve,fetchImpl});
 return async request=>{
  if(request.method!=='POST')return new Response('Method not allowed',{status:405});
  try {
   if(Number(request.headers.get('content-length')??0)>1024)return new Response('Too large',{status:413});
   const reader=request.body?.getReader();let size=0;const chunks=[];
   if(reader)while(true){const {done,value}=await reader.read();if(done)break;size+=value.length;
    if(size>1024){await reader.cancel();return new Response('Too large',{status:413});}chunks.push(value);}
   const bytes=new Uint8Array(size);let offset=0;for(const chunk of chunks){bytes.set(chunk,offset);offset+=chunk.length;}
   const body=new TextDecoder().decode(bytes);
   const {token}=JSON.parse(body);if(!/^[0-9a-f]{8}-(?:[0-9a-f]{4}-){3}[0-9a-f]{12}$/.test(token??''))return new Response('Unauthorized',{status:401});
   const source=await rpc('claim_official_fetch',{job_token:token});
   if(!source)return new Response('Unauthorized',{status:401});
   const result=await fetcher.run(source);
   const saved=await rpc('finish_official_fetch',{job_token:token,result});
   return Response.json({ok:!result.error,snapshot_id:saved.snapshot_id});
  }catch {return Response.json({error:'Monitor run failed'},{status:500});}
 };
}
